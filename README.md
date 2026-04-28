# SendraLabs Rule-Programmable Finance Environment (SRPE)

Non-custodial, rule-enforced execution environment. Financial products operate within programmable constraints tied directly to the reputation and accounting layer. Capital moves under smart contract-defined rules, eliminating the need for trust while preserving custody and control.

This controlled environment enables new financial primitives that are currently impractical in DeFi without trusted intermediaries or overcollateralization.

This repository contains the **first MVP version** of SRPE. It is designed to be **scalable and flexible** for deploying new **Rule-Programmable Financial Products (RPFPs)**. RPFPs can be governed by:

- **Reputation rules** based on verifiable past behavior (on-chain accounting/accumulators).
- **Forward-looking policy rules** that constrain future actions (e.g., allowing only certain parameter ranges, or allowing a specific `msg.sender` to call a specific function with specific inputs).

In SRPE, **SendraExecutors (UniversalExecutors)** are execution gateways deployed per-RPFP. An executor can only `delegatecall` into the configured **LogicExecutor** (product implementation) set at `deployRPFP()` time, and every user action is always checked against the RPFP’s configured rules. This design preserves flexibility (any function on the LogicExecutor can be executed) while ensuring enforcement (execution is rule-gated by `UniversalRuler`).

<img width="1002" height="630" alt="image" src="https://github.com/user-attachments/assets/fcf1f1b0-2e95-486d-b945-33763464c74c" />


## Flow 

SRPE is designed to separate 4 responsibilities:

- **RPFPDeployer**: deploys and registers a new RPFP (Rule Programmable Financial Product).
- **RPFPStorage**: stores RPFP configuration (implementation, owners, global rules, per-selector rules, etc.).
- **UniversalExecutor**: the single user entrypoint (`execute()`), performs a `delegatecall` into the product implementation (LogicExecutor) **only if** rules pass.
- **UniversalRuler**: validates the action before execution by reading rules and (when applicable) reputation/accumulators from the Sendra system.

In practice the flow is:

1) A developer calls `deployRPFP()`. A `UniversalExecutor` instance wired to the `AddressProvider` is deployed, the RPFP is created in `RPFPStorage`, and per-function (selector) rules are registered.

Source: `src/core/RPFPDeployer.sol` (lines 19-55)

```solidity
function deployRPFP(SRPELib.NewRPFPInputs memory _newRPFPInputs) public {
    // Deploy an executor instance wired to the AddressProvider.
    address executor = UniversalExecutorFactory(addressProvider.getAddress("UniversalExecutorFactory"))
        .deploySendraExecutor(address(addressProvider));
    _newRPFPInputs.rules.ruleCount = _newRPFPInputs.rules.rules.length;

    if (_newRPFPInputs.rules.ruleCount == 0 || _newRPFPInputs.rules.ruleCount > MAX_RULES)
        revert InvalidRules(_newRPFPInputs.rules.ruleCount, MAX_RULES);

    if (_newRPFPInputs.functionSelectors.length != _newRPFPInputs.functionSelectorRules.length) {
        revert FunctionRulesLengthMismatch(_newRPFPInputs.functionSelectors.length, _newRPFPInputs.functionSelectorRules.length);
    }
    
    uint256 rpfpId = RPFPStorage(addressProvider.getAddress("RPFPStorage")).createRPFP(
        _newRPFPInputs._type,
        executor,
        _newRPFPInputs.implementation,
        _newRPFPInputs.ruler,
        _newRPFPInputs.owners,
        _newRPFPInputs.description,
        _newRPFPInputs.extraData,
        _newRPFPInputs.rules,
        _newRPFPInputs.instructions
    );

    // Store per-function rules blobs (selector => Rules)
    for (uint256 i = 0; i < _newRPFPInputs.functionSelectors.length; i++) {
        SRPELib.Rules memory fr = _newRPFPInputs.functionSelectorRules[i];
        fr.ruleCount = fr.rules.length;
        if (fr.ruleCount == 0 || fr.ruleCount > MAX_RULES) {
            revert InvalidRules(fr.ruleCount, MAX_RULES);
        }
        RPFPStorage(addressProvider.getAddress("RPFPStorage")).setFunctionRules(rpfpId, _newRPFPInputs.functionSelectors[i], fr);
    }

    emit RPFPDeployed(executor, rpfpId);
}
```

2) A user signs and calls `UniversalExecutor.execute(...)`. The executor:
- reads the RPFP (`readRPFPById`) to get the implementation (LogicExecutor)
- validates the action via `UniversalRuler`
- if it passes, performs `delegatecall` to the implementation

Source: `src/core/execution/UniversalExecutor.sol` (lines 17-32)

```solidity
function execute(SRPELib.ExecutionParams memory _executionParams) public payable returns (bytes memory) {
    SRPELib.RPFPForRead memory rpfp =
        RPFPStorage(addressProvider.getAddress("RPFPStorage")).readRPFPById(_executionParams.rpfpId);
    address target = rpfp.implementation;

    // Check rules (reverts if invalid).
    UniversalRuler(addressProvider.getAddress("UniversalRuler")).checkExecution(
        _executionParams.actionData,
        msg.sender,
        _executionParams.rpfpId
    );

    (bool success, bytes memory result) = target.delegatecall(_executionParams.actionData);

    if (!success) {
        assembly {
            revert(add(result, 0x20), mload(result))
        }
    }

    return result;
}
```

## Rules by `functionSelector` (set, read, validate)

### Setting rules (deploy-time)
At deploy-time, selector-specific rules are stored via `RPFPStorage.setFunctionRules(...)`.

Source: `src/core/storage/RPFPStorage.sol` (lines 68-70)

```solidity
function setFunctionRules(uint256 _id, bytes4 _functionSelector, SRPELib.Rules calldata _rules) public onlyProtocol {
    rpfps[_id].functionRules[_functionSelector] = _rules;
}
```

### Reading rules (runtime)
`UniversalRuler` derives the selector from `actionData` and fetches the configured rules for that selector.

Source: `src/core/UniversalRuler.sol` (lines 18-26)

```solidity
function getFunctionsRules(uint256 _rpfpId, bytes4 _functionSelector) internal view returns (SRPELib.Rules memory) {
    SRPELib.Rules memory rules =
        RPFPStorage(addressProvider.getAddress("RPFPStorage")).getFunctionRules(_rpfpId, _functionSelector);
    return rules;
}

function checkExecution(bytes memory _actionData, address _sender, uint256 _rpfpId) public view {
    bytes4 functionSelector = _getSelector(_actionData);
    SRPELib.Rules memory rules = getFunctionsRules(_rpfpId, functionSelector);
    // ...
}
```

### Validation (runtime)
`checkExecution()` iterates the rules registered for that selector and reverts if any of them fails (AND semantics).
Additionally, when reputation rules are present (10+), it reads accumulators from `SendraStorage` (resolved via `AddressProvider`).

Source: `src/core/UniversalRuler.sol` (lines 23-116)

```solidity
function checkExecution(bytes memory _actionData, address _sender, uint256 _rpfpId) public view {
    bytes4 functionSelector = _getSelector(_actionData);
    SRPELib.Rules memory rules = getFunctionsRules(_rpfpId, functionSelector);
    SendraLib.GlobalAccumulators memory gAccumulators;
    bool isGlobalAccumulatorsInitialized = false;

    for (uint256 i = 0; i < rules.ruleCount; i++) {
        if (
            !isGlobalAccumulatorsInitialized &&
            (rules.rules[i].ruleType == 10 ||
                rules.rules[i].ruleType == 11 ||
                rules.rules[i].ruleType == 12 ||
                rules.rules[i].ruleType == 13 ||
                rules.rules[i].ruleType == 14 ||
                rules.rules[i].ruleType == 15 ||
                rules.rules[i].ruleType == 16 ||
                rules.rules[i].ruleType == 17 ||
                rules.rules[i].ruleType == 18 ||
                rules.rules[i].ruleType == 19 ||
                rules.rules[i].ruleType == 20)
        ) {
            ISendraStorage sendraStorage = ISendraStorage(addressProvider.getAddress("SendraStorage"));
            gAccumulators = sendraStorage.getUserGlobalAccumulators(_sender);
            isGlobalAccumulatorsInitialized = true;
        }

        // Examples: whitelist/blacklist/limits by input/reputation...
        // If any rule fails, it reverts with InvalidAction(i, functionSelector)
    }
}
```