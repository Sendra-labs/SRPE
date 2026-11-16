// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {SRPELib} from "../src/libs/SRPE/SRPE.lib.sol";
import {SendraLib} from "../src/libs/core/Sendra.lib.sol";
import {MockedAddressProvider} from "../src/core/demo/MockedAddressProv.sol";
import {MockedSendra} from "../src/core/demo/MockedSendra.sol";
import {MockedRoles} from "../src/core/demo/MockedRoles.sol";
import {RPFPStorage} from "../src/core/storage/RPFPStorage.sol";
import {UniversalRuler} from "../src/core/UniversalRuler.sol";
import {UniversalExecutorFactory} from "../src/core/UniversalExecutorFactory.sol";
import {RPFPDeployer} from "../src/core/RPFPDeployer.sol";
import {UniversalExecutor} from "../src/core/execution/UniversalExecutor.sol";
import {RulesHelper} from "../src/core/RulesHelper.sol";
import {SRPERules} from "../src/libs/SRPE/SRPERules.sol";

contract TouchLogic {
    function touch() external pure returns (bool) {
        return true;
    }

    function fund() external payable returns (bool) {
        return true;
    }

    function again() external pure returns (bool) {
        return true;
    }

    function setAmount(uint256) external pure returns (bool) {
        return true;
    }
}

contract LpLogic {
    function provideLiquidity(address, address, address, uint256, address) external pure returns (bool) {
        return true;
    }

    function useToken(address) external pure returns (bool) {
        return true;
    }
}

contract ReenterLogic {
    function reenter(uint256 rpfpId, bytes calldata inner) external {
        UniversalExecutor(address(this)).execute(
            SRPELib.ExecutionParams({targetFunction: 0, rpfpId: rpfpId, actionData: inner})
        );
    }
}

/// @notice Audit regressions and the V2 input / accumulator rules.
contract SRPEV2Test is Test {
    MockedAddressProvider internal addressProvider;
    MockedSendra internal sendra;
    MockedRoles internal roles;
    RPFPStorage internal rpfpStorage;
    UniversalRuler internal ruler;
    RPFPDeployer internal deployer;

    TouchLogic internal touch;
    LpLogic internal lp;

    address internal constant POOL_A = 0x1111111111111111111111111111111111111111;
    address internal constant POOL_B = 0x2222222222222222222222222222222222222222;
    address internal constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address internal constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address internal constant SCAM = 0x3333333333333333333333333333333333333333;
    address internal constant POOR = 0x4444444444444444444444444444444444444444;
    address internal constant REPUTED = 0x7F4C831de10684f85867899708cB49FfbF4983B9;

    bytes4 internal constant TOUCH = bytes4(keccak256("touch()"));
    bytes4 internal constant FUND = bytes4(keccak256("fund()"));
    bytes4 internal constant AGAIN = bytes4(keccak256("again()"));
    bytes4 internal constant SET_AMOUNT = bytes4(keccak256("setAmount(uint256)"));
    bytes4 internal constant PROVIDE =
        bytes4(keccak256("provideLiquidity(address,address,address,uint256,address)"));
    bytes4 internal constant USE_TOKEN = bytes4(keccak256("useToken(address)"));
    bytes4 internal constant REENTER = bytes4(keccak256("reenter(uint256,bytes)"));

    function setUp() public {
        vm.warp(20_000);
        touch = new TouchLogic();
        lp = new LpLogic();
        addressProvider = new MockedAddressProvider();
        sendra = new MockedSendra();
        roles = new MockedRoles();
        addressProvider.setRoles(address(roles));
        rpfpStorage = new RPFPStorage(address(addressProvider));
        ruler = new UniversalRuler(address(addressProvider), address(rpfpStorage), address(sendra));
        UniversalExecutorFactory factory = new UniversalExecutorFactory();
        deployer = new RPFPDeployer(address(addressProvider));
        roles.allowContract(address(deployer));
        addressProvider.setMockedSendra(address(sendra));
        addressProvider.setRPFPStorage(address(rpfpStorage));
        addressProvider.setUniversalRuler(address(ruler));
        addressProvider.setUniversalExecutorFactory(address(factory));
        addressProvider.setRPFPDeployer(address(deployer));
    }

    function test_negativePnlDoesNotPassAGreaterThanCheck() public {
        SendraLib.GlobalAccumulators memory book = _book();
        book.cumulativeRealizedPnl = -500;
        sendra.setGlobalAccumulators(POOR, book);

        (UniversalExecutor passExec, uint256 passId) = _deployTouch(
            _rule(SRPELib.RULE_REALIZED_PNL, abi.encode(int256(0), uint256(SRPELib.OP_LT)))
        );
        (UniversalExecutor failExec, uint256 failId) = _deployTouch(
            _rule(SRPELib.RULE_REALIZED_PNL, abi.encode(int256(0), uint256(SRPELib.OP_GT)))
        );

        vm.prank(POOR);
        assertTrue(abi.decode(passExec.execute(_params(passId, abi.encodeWithSelector(TOUCH))), (bool)));

        vm.prank(POOR);
        vm.expectRevert(abi.encodeWithSelector(UniversalRuler.InvalidAction.selector, 0, TOUCH));
        failExec.execute(_params(failId, abi.encodeWithSelector(TOUCH)));
    }

    function test_specificKeyIsIsolated() public {
        SendraLib.SpecificAccumulators memory good;
        good.realizedPnl = 100;
        SendraLib.SpecificAccumulators memory bad;
        bad.realizedPnl = -20;
        sendra.setSpecificAccumulators(POOR, 7, good);
        sendra.setSpecificAccumulators(POOR, 8, bad);

        bytes4[] memory sels = new bytes4[](2);
        sels[0] = TOUCH;
        sels[1] = AGAIN;
        SRPELib.Rules[] memory sets = new SRPELib.Rules[](2);
        sets[0] = _one(_rule(SRPELib.RULE_SPECIFIC_PNL, abi.encode(uint64(7), int256(0), uint256(SRPELib.OP_GT))));
        sets[1] = _one(_rule(SRPELib.RULE_SPECIFIC_PNL, abi.encode(uint64(8), int256(0), uint256(SRPELib.OP_GT))));
        (UniversalExecutor exec, uint256 id) = _deploy(address(touch), sels, sets, _emptyGlobal());

        vm.prank(POOR);
        exec.execute(_params(id, abi.encodeWithSelector(TOUCH)));
        vm.prank(POOR);
        vm.expectRevert(abi.encodeWithSelector(UniversalRuler.InvalidAction.selector, 0, AGAIN));
        exec.execute(_params(id, abi.encodeWithSelector(AGAIN)));
    }

    function test_specificMetricUint() public {
        SendraLib.SpecificAccumulators memory book;
        book.specificMetrics = new bytes[](1);
        book.specificMetrics[0] = abi.encode(uint256(50));
        sendra.setSpecificAccumulators(POOR, 3, book);

        (UniversalExecutor exec, uint256 id) = _deployTouch(
            _rule(
                SRPELib.RULE_SPECIFIC_METRIC,
                abi.encode(uint64(3), uint256(0), SRPELib.METRIC_UINT, int256(40), uint256(SRPELib.OP_GT))
            )
        );
        vm.prank(POOR);
        exec.execute(_params(id, abi.encodeWithSelector(TOUCH)));

        (UniversalExecutor strict, uint256 strictId) = _deployTouch(
            _rule(
                SRPELib.RULE_SPECIFIC_METRIC,
                abi.encode(uint64(3), uint256(0), SRPELib.METRIC_UINT, int256(80), uint256(SRPELib.OP_GT))
            )
        );
        vm.prank(POOR);
        vm.expectRevert(abi.encodeWithSelector(UniversalRuler.InvalidAction.selector, 0, TOUCH));
        strict.execute(_params(strictId, abi.encodeWithSelector(TOUCH)));
    }

    function test_derivedWinRate() public {
        SendraLib.GlobalAccumulators memory book = _book();
        book.winCount = 8;
        book.totalPositionsClosed = 10;
        sendra.setGlobalAccumulators(POOR, book);

        (UniversalExecutor exec, uint256 id) = _deployTouch(
            _rule(SRPELib.RULE_DERIVED, abi.encode(SRPELib.DERIVED_WIN_RATE_BPS, int256(7000), uint256(SRPELib.OP_GE)))
        );
        vm.prank(POOR);
        exec.execute(_params(id, abi.encodeWithSelector(TOUCH)));

        (UniversalExecutor strict, uint256 strictId) = _deployTouch(
            _rule(SRPELib.RULE_DERIVED, abi.encode(SRPELib.DERIVED_WIN_RATE_BPS, int256(9000), uint256(SRPELib.OP_GE)))
        );
        vm.prank(POOR);
        vm.expectRevert(abi.encodeWithSelector(UniversalRuler.InvalidAction.selector, 0, TOUCH));
        strict.execute(_params(strictId, abi.encodeWithSelector(TOUCH)));
    }

    function test_lpEnclaveConstrainsPoolTokensAmountAndRecipient() public {
        (UniversalExecutor exec, uint256 id) = _deployLp();
        bytes memory ok = abi.encodeWithSelector(PROVIDE, POOL_A, USDC, WETH, uint256(100), address(exec));
        vm.prank(REPUTED);
        assertTrue(abi.decode(exec.execute(_params(id, ok)), (bool)));

        bytes memory flipped = abi.encodeWithSelector(PROVIDE, POOL_A, WETH, USDC, uint256(1000), address(exec));
        vm.prank(REPUTED);
        exec.execute(_params(id, flipped));

        vm.prank(REPUTED);
        vm.expectRevert(abi.encodeWithSelector(UniversalRuler.InvalidAction.selector, 1, PROVIDE));
        exec.execute(_params(id, abi.encodeWithSelector(PROVIDE, POOL_B, USDC, WETH, uint256(100), address(exec))));

        vm.prank(REPUTED);
        vm.expectRevert(abi.encodeWithSelector(UniversalRuler.InvalidAction.selector, 2, PROVIDE));
        exec.execute(_params(id, abi.encodeWithSelector(PROVIDE, POOL_A, USDC, SCAM, uint256(100), address(exec))));

        vm.prank(REPUTED);
        vm.expectRevert(abi.encodeWithSelector(UniversalRuler.InvalidAction.selector, 3, PROVIDE));
        exec.execute(_params(id, abi.encodeWithSelector(PROVIDE, POOL_A, USDC, WETH, uint256(99), address(exec))));

        vm.prank(REPUTED);
        vm.expectRevert(abi.encodeWithSelector(UniversalRuler.InvalidAction.selector, 4, PROVIDE));
        exec.execute(_params(id, abi.encodeWithSelector(PROVIDE, POOL_A, USDC, WETH, uint256(100), POOR)));

        vm.prank(POOR);
        vm.expectRevert(abi.encodeWithSelector(UniversalRuler.InvalidAction.selector, 5, PROVIDE));
        exec.execute(_params(id, abi.encodeWithSelector(PROVIDE, POOL_A, USDC, WETH, uint256(100), address(exec))));

        vm.deal(REPUTED, 1);
        vm.prank(REPUTED);
        vm.expectRevert(UniversalRuler.UnexpectedCallValue.selector);
        exec.execute{value: 1}(_params(id, ok));
    }

    function test_paramDenylistBlocksToken() public {
        SRPELib.Rule memory deny;
        deny.ruleType = SRPELib.RULE_PARAM_DENYLIST;
        address[] memory banned = new address[](1);
        banned[0] = SCAM;
        deny.ruleData = abi.encode(uint256(0), banned);

        bytes4[] memory sels = new bytes4[](1);
        sels[0] = USE_TOKEN;
        SRPELib.Rules[] memory sets = new SRPELib.Rules[](1);
        sets[0] = _one(deny);
        (UniversalExecutor exec, uint256 id) = _deploy(address(lp), sels, sets, _emptyGlobal());

        exec.execute(_params(id, abi.encodeWithSelector(USE_TOKEN, USDC)));
        vm.expectRevert(abi.encodeWithSelector(UniversalRuler.InvalidAction.selector, 0, USE_TOKEN));
        exec.execute(_params(id, abi.encodeWithSelector(USE_TOKEN, SCAM)));
    }

    function test_uintRangeIsInclusive() public {
        (UniversalExecutor exec, uint256 id) = _deploy(
            address(touch),
            _sels(SET_AMOUNT),
            _sets(_one(_rule(SRPELib.RULE_PARAM_UINT_RANGE, abi.encode(uint256(0), uint256(100), uint256(1000))))),
            _emptyGlobal()
        );
        exec.execute(_params(id, abi.encodeWithSelector(SET_AMOUNT, uint256(100))));
        exec.execute(_params(id, abi.encodeWithSelector(SET_AMOUNT, uint256(1000))));
        vm.expectRevert(abi.encodeWithSelector(UniversalRuler.InvalidAction.selector, 0, SET_AMOUNT));
        exec.execute(_params(id, abi.encodeWithSelector(SET_AMOUNT, uint256(99))));
        vm.expectRevert(abi.encodeWithSelector(UniversalRuler.InvalidAction.selector, 0, SET_AMOUNT));
        exec.execute(_params(id, abi.encodeWithSelector(SET_AMOUNT, uint256(1001))));
    }

    function test_callValueRuleBoundsEth() public {
        (UniversalExecutor exec, uint256 id) = _deploy(
            address(touch),
            _sels(FUND),
            _sets(_one(_rule(SRPELib.RULE_CALL_VALUE, abi.encode(uint256(1 ether), uint256(SRPELib.OP_LE))))),
            _emptyGlobal()
        );
        vm.deal(address(this), 3 ether);
        exec.execute{value: 1 ether}(_params(id, abi.encodeWithSelector(FUND)));
        vm.expectRevert(abi.encodeWithSelector(UniversalRuler.InvalidAction.selector, 0, FUND));
        exec.execute{value: 1 ether + 1}(_params(id, abi.encodeWithSelector(FUND)));
    }

    function test_cooldownIsPerSenderAndSelector() public {
        (UniversalExecutor exec, uint256 id) = _deployTouch(_rule(SRPELib.RULE_COOLDOWN, abi.encode(uint256(100))));
        exec.execute(_params(id, abi.encodeWithSelector(TOUCH)));
        vm.expectRevert(abi.encodeWithSelector(UniversalRuler.CooldownActive.selector, TOUCH, block.timestamp + 100));
        exec.execute(_params(id, abi.encodeWithSelector(TOUCH)));
        vm.warp(block.timestamp + 100);
        exec.execute(_params(id, abi.encodeWithSelector(TOUCH)));
    }

    function test_previewMatchesARevertAndDoesNotConsumeCooldown() public {
        (UniversalExecutor exec, uint256 id) = _deployTouch(_rule(SRPELib.RULE_COOLDOWN, abi.encode(uint256(100))));
        bytes memory data = abi.encodeWithSelector(TOUCH);
        ruler.previewExecution(data, address(this), id, 0);
        exec.execute(_params(id, data));
        vm.expectRevert(abi.encodeWithSelector(UniversalRuler.CooldownActive.selector, TOUCH, block.timestamp + 100));
        ruler.previewExecution(data, address(this), id, 0);
        assertEq(ruler.lastExecutedAt(keccak256(abi.encode(id, TOUCH, address(this)))), block.timestamp);
    }

    function test_reentrancyIntoExecuteReverts() public {
        ReenterLogic logic = new ReenterLogic();
        (UniversalExecutor exec, uint256 id) = _deploy(address(logic), _sels(REENTER), _sets(_noop()), _emptyGlobal());
        bytes memory inner = abi.encodeWithSelector(REENTER, id, bytes(""));
        vm.expectRevert(UniversalExecutor.Reentrancy.selector);
        exec.execute(_params(id, abi.encodeWithSelector(REENTER, id, inner)));
    }

    function test_checkExecutionIsExecutorOnly() public {
        (UniversalExecutor exec, uint256 id) = _deployTouch(_noopRule());
        vm.expectRevert(abi.encodeWithSelector(UniversalRuler.OnlyExecutor.selector, address(this)));
        ruler.checkExecution(abi.encodeWithSelector(TOUCH), address(this), id, 0);
        exec.execute(_params(id, abi.encodeWithSelector(TOUCH)));
    }

    function test_globalAllowlistIsEnforced() public {
        address[] memory allowed = new address[](1);
        allowed[0] = REPUTED;
        SRPELib.Rules memory global = _one(_rule(SRPELib.RULE_SENDER_ALLOWLIST, abi.encode(allowed)));
        (UniversalExecutor exec, uint256 id) = _deploy(address(touch), _sels(TOUCH), _sets(_noop()), global);

        vm.prank(REPUTED);
        exec.execute(_params(id, abi.encodeWithSelector(TOUCH)));
        vm.prank(POOR);
        vm.expectRevert(abi.encodeWithSelector(UniversalRuler.InvalidGlobalRule.selector, 0, TOUCH));
        exec.execute(_params(id, abi.encodeWithSelector(TOUCH)));
    }

    function test_providerSwapDoesNotRetargetALiveEnclave() public {
        (UniversalExecutor exec, uint256 id) = _deployTouch(_noopRule());
        RPFPStorage swapped = new RPFPStorage(address(addressProvider));
        addressProvider.setRPFPStorage(address(swapped));
        addressProvider.setUniversalRuler(address(0xBEEF));
        assertTrue(abi.decode(exec.execute(_params(id, abi.encodeWithSelector(TOUCH))), (bool)));
        assertEq(address(exec.rpfpStorage()), address(rpfpStorage));
        assertEq(address(exec.ruler()), address(ruler));
    }

    function test_anyoneCanDeployAnRpfp() public {
        address stranger = address(0xA11CE);
        vm.prank(stranger);
        (address executor, uint256 id) = deployer.deployRPFP(SRPERules.publicAction(address(touch), TOUCH, "open"));
        SRPELib.RPFPForRead memory rpfp = rpfpStorage.readRPFPById(id);
        assertEq(rpfp.creator, stranger);
        assertEq(rpfp.owners.length, 1);
        assertEq(rpfp.owners[0], stranger);
        assertEq(rpfp.executor, executor);
        vm.prank(POOR);
        assertTrue(abi.decode(UniversalExecutor(executor).execute(_params(id, abi.encodeWithSelector(TOUCH))), (bool)));
    }

    function test_deployRejectsUnknownRuleDuplicateSelectorAndGlobalInputRule() public {
        SRPELib.NewRPFPInputs memory bad = _inputs(address(touch), _sels(TOUCH), _sets(_one(_rule(99, ""))), _emptyGlobal());
        vm.expectRevert(abi.encodeWithSelector(RulesHelper.UnsupportedRule.selector, uint16(99)));
        deployer.deployRPFP(bad);

        bytes4[] memory dup = new bytes4[](2);
        dup[0] = TOUCH;
        dup[1] = TOUCH;
        SRPELib.Rules[] memory sets = new SRPELib.Rules[](2);
        sets[0] = _noop();
        sets[1] = _noop();
        vm.expectRevert(abi.encodeWithSelector(RPFPDeployer.DuplicateSelector.selector, TOUCH));
        deployer.deployRPFP(_inputs(address(touch), dup, sets, _emptyGlobal()));

        address[] memory pools = new address[](1);
        pools[0] = POOL_A;
        SRPELib.Rules memory global =
            _one(_rule(SRPELib.RULE_PARAM_ALLOWLIST, abi.encode(uint256(0), pools)));
        vm.expectRevert(abi.encodeWithSelector(RulesHelper.InvalidRuleData.selector, SRPELib.RULE_PARAM_ALLOWLIST));
        deployer.deployRPFP(_inputs(address(touch), _sels(TOUCH), _sets(_noop()), global));
    }

    function test_deployRejectsSelectorMismatchAndForeignRuler() public {
        SRPELib.Rule memory wrong;
        wrong.ruleType = SRPELib.RULE_SELECTOR_WORD;
        wrong.ruleData = abi.encode(AGAIN, uint256(0), bytes32(uint256(1)));
        vm.expectRevert(abi.encodeWithSelector(RulesHelper.InvalidRuleData.selector, SRPELib.RULE_SELECTOR_WORD));
        deployer.deployRPFP(_inputs(address(touch), _sels(TOUCH), _sets(_one(wrong)), _emptyGlobal()));

        SRPELib.NewRPFPInputs memory inputs = _inputs(address(touch), _sels(TOUCH), _sets(_noop()), _emptyGlobal());
        inputs.ruler = address(0xBEEF);
        vm.expectRevert(RPFPDeployer.InvalidRuler.selector);
        deployer.deployRPFP(inputs);
    }

    function _deployLp() internal returns (UniversalExecutor exec, uint256 id) {
        address[] memory senders = new address[](2);
        senders[0] = REPUTED;
        senders[1] = POOR;
        address[] memory pools = new address[](1);
        pools[0] = POOL_A;
        address[] memory tokenA = new address[](1);
        address[] memory tokenB = new address[](1);
        tokenA[0] = USDC;
        tokenB[0] = WETH;

        SRPELib.Rule[] memory rules = new SRPELib.Rule[](6);
        rules[0] = _rule(SRPELib.RULE_SENDER_ALLOWLIST, abi.encode(senders));
        rules[1] = _rule(SRPELib.RULE_PARAM_ALLOWLIST, abi.encode(uint256(0), pools));
        rules[2] = _rule(SRPELib.RULE_PARAM_PAIR, abi.encode(uint256(1), uint256(2), true, tokenA, tokenB));
        rules[3] = _rule(SRPELib.RULE_PARAM_UINT_RANGE, abi.encode(uint256(3), uint256(100), uint256(1000)));
        rules[4] = _rule(SRPELib.RULE_PARAM_ACCOUNT, abi.encode(uint256(4), uint256(SRPELib.ACCOUNT_EXECUTOR)));
        rules[5] = _rule(SRPELib.RULE_CAPITAL_IN, abi.encode(uint256(5000), uint256(SRPELib.OP_GE)));

        return _deploy(address(lp), _sels(PROVIDE), _sets(_pack(rules)), _emptyGlobal());
    }

    function _deployTouch(SRPELib.Rule memory rule) internal returns (UniversalExecutor exec, uint256 id) {
        return _deploy(address(touch), _sels(TOUCH), _sets(_one(rule)), _emptyGlobal());
    }

    function _deploy(address implementation, bytes4[] memory sels, SRPELib.Rules[] memory sets, SRPELib.Rules memory global)
        internal
        returns (UniversalExecutor exec, uint256 id)
    {
        (address executor, uint256 rpfpId) = deployer.deployRPFP(_inputs(implementation, sels, sets, global));
        return (UniversalExecutor(executor), rpfpId);
    }

    function _inputs(address implementation, bytes4[] memory sels, SRPELib.Rules[] memory sets, SRPELib.Rules memory global)
        internal
        view
        returns (SRPELib.NewRPFPInputs memory inputs)
    {
        inputs.implementation = implementation;
        inputs.ruler = address(ruler);
        inputs.description = "v2";
        inputs.owners = new address[](0);
        inputs.rules = global;
        inputs.instructions = SRPELib.Instructions({instructions: new SRPELib.Instruction[](0)});
        inputs.functionSelectors = sels;
        inputs.functionSelectorRules = sets;
    }

    function _params(uint256 id, bytes memory data) internal pure returns (SRPELib.ExecutionParams memory p) {
        p.rpfpId = id;
        p.actionData = data;
    }

    function _rule(uint16 ruleType, bytes memory data) internal pure returns (SRPELib.Rule memory rule) {
        rule.ruleType = ruleType;
        rule.ruleData = data;
    }

    function _noopRule() internal pure returns (SRPELib.Rule memory rule) {
        rule.ruleType = SRPELib.RULE_NONE;
    }

    function _one(SRPELib.Rule memory rule) internal pure returns (SRPELib.Rules memory rules) {
        rules.rules = new SRPELib.Rule[](1);
        rules.rules[0] = rule;
        rules.ruleCount = 1;
    }

    function _noop() internal pure returns (SRPELib.Rules memory) {
        return _one(_noopRule());
    }

    function _pack(SRPELib.Rule[] memory rules) internal pure returns (SRPELib.Rules memory packed) {
        packed.rules = rules;
        packed.ruleCount = rules.length;
    }

    function _sels(bytes4 selector) internal pure returns (bytes4[] memory sels) {
        sels = new bytes4[](1);
        sels[0] = selector;
    }

    function _sets(SRPELib.Rules memory rules) internal pure returns (SRPELib.Rules[] memory sets) {
        sets = new SRPELib.Rules[](1);
        sets[0] = rules;
    }

    function _emptyGlobal() internal pure returns (SRPELib.Rules memory rules) {
        rules.rules = new SRPELib.Rule[](0);
    }

    function _book() internal pure returns (SendraLib.GlobalAccumulators memory book) {}
}
