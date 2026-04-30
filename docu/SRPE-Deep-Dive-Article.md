## SRPE Deep Dive Article

**SendraLabs Rule-Programmable Finance Environment (SRPE)** is a **non-custodial, rule-enforced execution environment** where financial products operate inside programmable constraints that can be tied to a reputation/accounting layer. The goal is to enable financial primitives that are impractical in DeFi without trusted intermediaries or heavy overcollateralization.

This repository contains the **first MVP version** of SRPE, designed to be **scalable and flexible** for deploying new **Rule-Programmable Financial Products (RPFPs)** governed by:

- **Reputation rules** based on verifiable past behavior (on-chain accounting/accumulators).
- **Forward-looking policy rules** that constrain future actions (e.g., parameter ranges, sender allowlists, etc.).

In SRPE, **SendraExecutors (UniversalExecutors)** are execution gateways deployed **per RPFP**. An executor can only `delegatecall` into the configured **LogicExecutor** (the product implementation) set at `deployRPFP()` time, and **every user action** is checked against the RPFP’s configured rules. This preserves flexibility (any function on the LogicExecutor can be executed) while ensuring enforcement (execution is rule-gated by `UniversalRuler`).

This MVP demonstrates **deterministic constraints on execution that bound system behavior**: rule evaluation happens before any product logic runs, and any violation results in a deterministic revert.

It also integrates the hooks required for **reputation-based constraints**, with initial rule types already supported.

---

## 1) What is an RPFP (Rule-Programmable Financial Product)?

An **RPFP** is not a single contract; it is a **bundle of related components** that together define a financial product with programmable constraints:

- **LogicExecutor (implementation contract)**: contains the product logic (implementation-only, no gateway responsibilities).
- **UniversalExecutor (SendraExecutor)**: a per-RPFP execution gateway that `delegatecall`s into the LogicExecutor after rule checks.
- **Rules configuration**: a set of global and per-function rules registered at deployment time and stored in SRPE storage.
- **RPFP registration**: an entry in `RPFPStorage` that ties everything together and makes the product discoverable and enforceable at runtime.

### A simplified RPFP view (only what is actually used at runtime)

Below is a *simplified, documentation-only* representation of the data SRPE uses to execute and validate actions. It intentionally omits older/unused fields and storage-only details.

```solidity

struct RPFP {
  uint16 _type;
  uint256 id;
  address executor;
  address implementation;
  string description;
  bytes extraData;
  uint256 createdAt;
  // Function-specific rules mapped by selector.
  mapping(bytes4 => Rules) functionRules;
}

struct Rules {
  uint256 ruleCount;
  Rule[]  rules;
}

struct Rule {
  uint16 ruleType;
  bytes  ruleData;
  bytes  extraData; // used by specific rules (e.g. param index for range checks)
}
```

### Deployment-time assembly

At `deployRPFP(...)`, SRPE:

- Deploys a new `UniversalExecutor` instance (one per RPFP).
- Stores an RPFP record in `RPFPStorage` (implementation, owners, metadata, global rules/instructions).
- Stores **per-function (selector) rules** in `RPFPStorage` as `(rpfpId, selector) -> Rules`.

This “product bundle” is what we refer to as an RPFP.

---

## 2) Rules

Rules are the heart of SRPE. They answer:

- **What can be done**? (which function selector, which parameter constraints)
- **Who can do it**? (`msg.sender` allow/deny)
- **When can it be done**? (time windows)
- **Under what reputation/accounting constraints**? (global accumulators from the Sendra system)

### How rules are represented

Rules are encoded in `SRPELib` as:

- `Rules`: a blob containing `ruleCount` and an array of `Rule`.
- `Rule`: `(ruleType, ruleData, extraData)`.

In storage, SRPE keeps:

- **Global rules**: `rpfps[id].rules` (catalog, useful for UX / documentation / instructions).
- **Per-function rules**: `rpfps[id].functionRules[selector]`.

At runtime, the actual enforcement path is *selector-based*: the `UniversalRuler` extracts the selector from `actionData` and fetches the rule blob for that selector.

### Rules available in this MVP

The following list reflects what is currently implemented in `UniversalRuler.checkExecution(...)` and `RulesHelper`:

- **0 — No rule**: placeholder/no-op.
- **1 — Whitelist**: allow only senders inside an address list.
- **2 — Blacklist**: deny senders inside an address list.
- **3 — Time limit**: compare `block.timestamp` against a threshold.
- **4 — Frequency limit**: *placeholder (not implemented yet)*.
- **5 — Allow specific sender for a specific function**: exact `(selector, sender)` match.
- **6 — Allow specific sender + function + exact input word**: exact match on `(selector, sender, paramIndex, expectedWord)`.
- **7 — Allow specific function + exact input word**: exact match on `(selector, paramIndex, expectedWord)`.
- **8 — Uint range check**: read a uint256 parameter by index and ensure it is within a configured range.
- **9 — Empty rule**: placeholder/no-op.
- **10..28 — Reputation/accumulator limits (global)**: compare a Sendra global accumulator field against a threshold (see “UniversalRuler” section).

> Notes for future extension
>
> - There are additional rule type IDs documented in `SRPELib` beyond what `UniversalRuler` currently enforces.
> - The set above is the *effective* rule surface today (what actually gates execution).

### Rule building patterns (encodings)

Most rules are expressed as `abi.encode(...)` payloads in `ruleData` (and sometimes `extraData`). Here are the canonical encodings used by the helper methods.

#### Whitelist / blacklist (ruleType 1 / 2)

```solidity
address[] memory allowed = new address[](2);
allowed[0] = 0x1111111111111111111111111111111111111111;
allowed[1] = 0x2222222222222222222222222222222222222222;

Rule memory r = Rule({
  ruleType: 1, // whitelist
  ruleData: abi.encode(allowed),
  extraData: ""
});
```

#### Time limit (ruleType 3)

`ruleData = abi.encode(uint256[2]([value, type]))` where:

- `type = 0`: rule expects `value < observed` (i.e., observed must be *after* `value`)
- `type = 1`: rule expects `value > observed` (i.e., observed must be *before* `value`)

For example: “only before a future timestamp”:

```solidity
uint256 deadline = 1_800_000_000;
Rule memory r = Rule({
  ruleType: 3,
  ruleData: abi.encode([deadline, uint256(1)]),
  extraData: ""
});
```

#### Allow `(selector, sender)` (ruleType 5)

```solidity
bytes4 sel = bytes4(keccak256("provideLiquidity(uint256,address)"));
address allowedSender = 0x3333333333333333333333333333333333333333;

Rule memory r = Rule({
  ruleType: 5,
  ruleData: abi.encode(sel, allowedSender),
  extraData: ""
});
```

#### Allow `(selector, sender, paramIndex, expectedWord)` (ruleType 6)

This performs a 32-byte word equality check on the ABI-encoded calldata at the given parameter index.

```solidity
bytes4 sel = bytes4(keccak256("setVault(address)"));
address allowedSender = 0x4444444444444444444444444444444444444444;
uint256 paramIndex = 0;
bytes32 expected = bytes32(uint256(uint160(0x5555555555555555555555555555555555555555)));

Rule memory r = Rule({
  ruleType: 6,
  ruleData: abi.encode(sel, allowedSender, paramIndex, expected),
  extraData: ""
});
```

#### Allow `(selector, paramIndex, expectedWord)` (ruleType 7)

```solidity
bytes4 sel = bytes4(keccak256("setFee(uint256)"));
uint256 paramIndex = 0;
bytes32 expected = bytes32(uint256(50)); // e.g., exact fee = 50 (word-equality)

Rule memory r = Rule({
  ruleType: 7,
  ruleData: abi.encode(sel, paramIndex, expected),
  extraData: ""
});
```

#### Uint range check by parameter index (ruleType 8)

This reads a `uint256` argument from calldata by index and checks it with `checkUintRange(ruleData, value)`.

```solidity
uint256 min = 100e6; // example: USDC has 6 decimals
uint256 max = 10_000e6;
uint256 paramIndex = 0; // which argument in calldata we want to check

Rule memory r = Rule({
  ruleType: 8,
  ruleData: abi.encode([min, max]),
  extraData: abi.encode(paramIndex)
});
```

### “Rules struct + functionSelectors + functionSelectorRules” (deployment payload)

Deployment uses `SRPELib.NewRPFPInputs`, which includes parallel arrays:

- `functionSelectors`: list of selectors you want to constrain
- `functionSelectorRules`: the `Rules` blob for each selector

Here is how that payload looks conceptually (documentation-oriented):

```solidity
SRPELib.NewRPFPInputs memory inputs;
inputs.implementation = logicExecutor;
inputs.owners = owners;
inputs.description = "My RPFP";

// 1) optional: global rules catalog (not the gating source in current flow)
inputs.rules = SRPELib.Rules({
  ruleCount: 2,
  rules: globalRulesArray
});

// 2) per-selector gating rules (enforced in UniversalRuler.checkExecution)
inputs.functionSelectors = new bytes4[](2);
inputs.functionSelectorRules = new SRPELib.Rules[](2);

inputs.functionSelectors[0] = bytes4(keccak256("provideLiquidity(uint256,address)"));
inputs.functionSelectorRules[0] = SRPELib.Rules({ ruleCount: 2, rules: provideLiquidityRules });

inputs.functionSelectors[1] = bytes4(keccak256("withdraw(uint256)"));
inputs.functionSelectorRules[1] = SRPELib.Rules({ ruleCount: 1, rules: withdrawRules });
```

---

## 3) LogicExecutors

**LogicExecutors** are **implementation contracts**: they define product logic only.

Key expectations:

- They are designed to be called via `delegatecall` from the RPFP’s `UniversalExecutor`.
- They should keep state in an externalized manner compatible with being executed in the executor’s context (i.e., *storage layout must match the executor’s storage context used by the product*).
- Their functions are invoked by passing raw `actionData` (ABI-encoded selector + parameters) to `UniversalExecutor.execute(...)`.

In practice, this makes the LogicExecutor a “pure logic module”, while SRPE provides the gateway and policy enforcement.

---

## 4) UniversalExecutor (SendraExecutor)

SRPE deploys **one `UniversalExecutor` per RPFP**.

Responsibilities:

- Resolve RPFP configuration (to find the target LogicExecutor) from `RPFPStorage`.
- Call the rule controller (`UniversalRuler.checkExecution`) before executing any product action.
- Execute the action against the target implementation using `delegatecall`.

### Why `delegatecall`?

`delegatecall` executes LogicExecutor code **in the executor’s context**, which enables:

- flexible “plugin-like” logic execution (any function on the LogicExecutor is callable),
- while keeping the execution gateway stable and rule-controlled.

### Execution flow (runtime)

At runtime, `UniversalExecutor.execute(ExecutionParams)`:

1. Reads the RPFP to obtain `implementation`.
2. Calls `UniversalRuler.checkExecution(actionData, msg.sender, rpfpId)`.
3. Performs `delegatecall(implementation, actionData)` and bubbles revert reasons.

---

## 5) UniversalRuler

`UniversalRuler` is the **policy enforcement engine**. It is called by the executor *before* any `delegatecall` occurs.

### `checkExecution(...)` parameters

- `bytes actionData`: ABI-encoded function selector + arguments for the LogicExecutor call.
- `address sender`: the transaction sender (`msg.sender` from the executor).
- `uint256 rpfpId`: the RPFP identifier used to resolve selector rules from storage.

### Selector-based rule resolution

1. The selector is derived from `actionData` by reading the first 4 bytes.
2. The ruler loads the configured `Rules` blob for that selector from `RPFPStorage`.
3. The ruler evaluates each rule in-order.

The semantics are **AND**: *if any rule fails, the entire action is rejected*.

### Global accumulators (reputation rules)

Some rule types (10..28) require access to the user’s **Sendra global accumulators**. `checkExecution` lazily initializes them:

- It scans rules while iterating.
- The first time it sees a “reputation rule”, it queries `SendraStorage.getUserGlobalAccumulators(sender)` via the AddressProvider.
- The returned struct is cached in-memory and reused for subsequent reputation checks in the same call.

This avoids unnecessary external calls for rule sets that do not include reputation constraints.

### Failure behavior

If a rule fails, `checkExecution` reverts with:

- `InvalidAction(ruleIndex, functionSelector)`

This is useful for debugging which rule in the selector rule blob caused the rejection.

**Any violation of constraints results in a deterministic revert before execution.**

---

## 6) `src/core/rulesHelper.sol`

`RulesHelper` is a low-level helper that implements reusable, generic checks used by `UniversalRuler`.

### `checkSenderAndFunc(ruleData, actionData, sender)`

- Decodes `ruleData` as `(bytes4 allowedSelector, address allowedSender)`.
- Extracts the selector from `actionData`.
- Returns true only if both selector and sender match.

Used by ruleType **5**.

### `checkSenderAndFuncAndInput(ruleData, actionData, sender)`

- Decodes `ruleData` as `(bytes4 allowedSelector, address allowedSender, uint256 paramIndex, bytes32 expectedValue)`.
- Extracts selector and reads the ABI word at the parameter index from `actionData`.
- Returns true only if selector, sender, and the selected calldata word match.

Used by ruleType **6**.

### `checkFuncAndInput(ruleData, actionData)`

- Decodes `ruleData` as `(bytes4 allowedSelector, uint256 paramIndex, bytes32 expectedValue)`.
- Extracts selector and reads the ABI word at the parameter index from `actionData`.
- Returns true only if selector and calldata word match.

Used by ruleType **7**.

### `checkAddressList(ruleData, isWhitelist, sender)`

- Decodes `ruleData` as `address[]`.
- Checks membership of `sender`.
- Returns:
  - for whitelist: `found`
  - for blacklist: `!found`

Used by ruleTypes **1** and **2**.

### `checkUint(ruleData, value)`

- Decodes `ruleData` as `uint256[2]` where `[threshold, type]`.
- Applies a comparison that depends on `type`.

Used by:

- ruleType **3** for timestamps (`value = block.timestamp`)
- ruleTypes **10..28** for reputation accumulator comparisons

### `checkUintRange(ruleData, value)`

- Decodes `ruleData` as `uint256[2]` where `[min, max]`.
- Returns `min < value < max`.

Used by ruleType **8**.

### `_getSelector(actionData)`

- Reads the first 4 bytes of `actionData` and returns them as `bytes4`.
- Reverts if `actionData.length < 4`.

This is the primitive that makes selector-based rule gating possible.

---

## 7) End-to-end example (storytelling): “Idle USDC → Uniswap LP via reputation + policy”

This section ties SRPE’s three pillars together:

- **State**: accounting + reputation (Sendra global accumulators) and RPFP configuration in `RPFPStorage`
- **Policy**: the rule blobs registered per function selector
- **Execution**: `UniversalExecutor.execute(...)` → `UniversalRuler.checkExecution(...)` → `delegatecall` into a LogicExecutor

### Characters

- **User A (operator)**: a professional DeFi user. Their past performance is observable in Sendra Core (e.g., profitable LP behavior on Uniswap).
- **User B (capital provider)**: holds idle USDC on-chain but does not want to actively manage DeFi positions.

### High-level goal

User B wants to put USDC to work on Uniswap **without** giving custody away, and without relying on trust. User A wants to access more capital **based on reputation** (or with a small collateral requirement enforced by rules).

In other words: **capital + constraints + verifiable operator behavior**.

### Product template

Sendra (or a third-party developer) publishes a standard **Uniswap Liquidity Provision LogicExecutor template** (implementation contract). The template is designed to:

- Keep the product’s state in a dedicated storage pattern compatible with being executed via `delegatecall`.
- Expose a small set of functions such as:
  - `provideLiquidity(address pool, uint256 usdcAmount, ...)`
  - `withdrawUsdc(uint256 amount)`
  - (optionally) `rebalance(...)`, `collectFees(...)`, etc.

User B deploys an RPFP pointing to this template (or to a version wired to B’s customized storage), then configures policy with selector-level rules.

### Deployment: create the RPFP bundle

User B (or an app acting for B) calls `RPFPDeployer.deployRPFP(...)` with:

- `implementation`: the Uniswap LP LogicExecutor
- `owners`: includes User B (and optionally a multisig, or additional administrators)
- `functionSelectors` and `functionSelectorRules`: selector-gated policy for each exposed function
- `description`: human-readable intent (helps UX / indexing / auditing)

This produces:

- A new **per-RPFP `UniversalExecutor` instance**
- A new **RPFP record** stored in `RPFPStorage`
- Stored **selector → rules** mappings for runtime enforcement

### Policy: rules User B might configure

Below is an illustrative policy configuration that matches the intent described:

#### Policy for `provideLiquidity(...)`

**Intent**: only User A can operate; only a specific pool is allowed; cap each transaction to 1,000 USDC; only within the next week.

- **Only User A can call** `provideLiquidity(...)`
  - Use ruleType **5** (selector + sender) or ruleType **1** (whitelist)
- **Only the BTC/ETH pool address is allowed**
  - Use ruleType **7** (selector + paramIndex + expectedWord) to enforce the `pool` parameter
- **Per-call cap: max 1,000 USDC**
  - Use ruleType **8** (uint range) on the `usdcAmount` parameter
- **Time window: next 7 days**
  - Use ruleType **3** (time limit) against `block.timestamp`

Conceptually:

```solidity
bytes4 PROVIDE = bytes4(keccak256("provideLiquidity(address,uint256,bytes)"));

SRPELib.Rule[] memory provideRules = new SRPELib.Rule[](4);

// 1) Only User A operates
provideRules[0] = SRPELib.Rule({
  ruleType: 5,
  ruleData: abi.encode(PROVIDE, userA),
  extraData: ""
});

// 2) Only a specific pool address is allowed
// paramIndex depends on the function signature; here we assume pool is param 0.
provideRules[1] = SRPELib.Rule({
  ruleType: 7,
  ruleData: abi.encode(PROVIDE, uint256(0), bytes32(uint256(uint160(btcEthPool)))),
  extraData: ""
});

// 3) Only up to 1,000 USDC per tx (example uses open interval min<value<max)
// paramIndex depends on signature; here we assume usdcAmount is param 1.
provideRules[2] = SRPELib.Rule({
  ruleType: 8,
  ruleData: abi.encode([uint256(0), uint256(1_000e6)]),
  extraData: abi.encode(uint256(1))
});

// 4) Only for the next week
provideRules[3] = SRPELib.Rule({
  ruleType: 3,
  ruleData: abi.encode([block.timestamp + 7 days, uint256(1)]),
  extraData: ""
});
```

> Space for expansion
>
> - Add reputation constraints so **any operator** with verifiable success can execute, not just User A.
> - Add “cooldown / frequency” constraints once frequency rule types are implemented.

#### Policy for `withdrawUsdc(...)`

**Intent**: only User B can withdraw their USDC.

- Use ruleType **5** (selector + sender) for `withdrawUsdc(...)`.

```solidity
bytes4 WITHDRAW = bytes4(keccak256("withdrawUsdc(uint256)"));

SRPELib.Rule[] memory withdrawRules = new SRPELib.Rule[](1);
withdrawRules[0] = SRPELib.Rule({
  ruleType: 5,
  ruleData: abi.encode(WITHDRAW, userB),
  extraData: ""
});
```

### Optional: reputation-gated access (beyond a fixed “User A only” design)

If User B wants to allow *any* operator who has proven competence, the policy can be shifted from “identity-based” to “reputation-based”.

Conceptually:

- Replace “only User A” with “any sender with verifiable performance”
- Add one or more **reputation accumulator constraints** (rule types **10..28**) such as:
  - minimum total capital in/out
  - max drawdown constraint
  - win/loss counts, consecutive losses, etc.

This turns the RPFP into a **permissionless-but-constrained capital pool** where access is granted by policy backed by measurable on-chain performance.

### Runtime: what happens when User A calls `execute(...)`

1. **User A prepares** `actionData = abi.encodeWithSelector(PROVIDE, pool, usdcAmount, ...)`.
2. **User A calls** `UniversalExecutor.execute({ rpfpId, actionData, ... })`.
3. The executor loads the RPFP to find `implementation`.
4. The executor calls `UniversalRuler.checkExecution(actionData, msg.sender, rpfpId)`.
5. The ruler:
   - derives the selector from `actionData`,
   - loads the selector’s `Rules` blob,
   - lazily loads Sendra global accumulators if any reputation rule types are present,
   - evaluates rules with **AND** semantics.
6. If all rules pass, the executor `delegatecall`s into the LogicExecutor, executing product logic **in the executor context**.
7. If any rule fails, the call reverts with `InvalidAction(ruleIndex, selector)` and **nothing executes**.

### Execution Trace Examples

Below are concrete “attempts” to call `execute(...)` for the RPFP described above. Some pass; others deterministically revert *before* any Uniswap logic runs.

#### Trace A — PASS: User A provides 500 USDC to the allowed BTC/ETH pool (within the week)

- **sender**: `userA`
- **selector**: `provideLiquidity(...)`
- **params**:
  - `pool = btcEthPool` (allowed)
  - `usdcAmount = 500e6` (≤ 1,000e6)
  - `timestamp = now` (≤ deadline)
- **rule evaluation**:
  - ruleType 5: PASS (sender matches)
  - ruleType 7: PASS (pool matches expected word)
  - ruleType 8: PASS (amount within range)
  - ruleType 3: PASS (within time window)
- **result**: `checkExecution` returns → `delegatecall` executes → liquidity is provided on Uniswap.

#### Trace B — REVERT: User A tries the wrong pool

- **sender**: `userA`
- **selector**: `provideLiquidity(...)`
- **params**:
  - `pool = someOtherPool` (not allowed)
  - `usdcAmount = 500e6`
- **rule evaluation**:
  - ruleType 5: PASS
  - ruleType 7: **FAIL**
- **result**: revert `InvalidAction(ruleIndex, PROVIDE)` before execution.

#### Trace C — REVERT: User A tries to provide 2,000 USDC (over the cap)

- **sender**: `userA`
- **selector**: `provideLiquidity(...)`
- **params**:
  - `pool = btcEthPool`
  - `usdcAmount = 2_000e6` (over cap)
- **rule evaluation**:
  - ruleType 5: PASS
  - ruleType 7: PASS
  - ruleType 8: **FAIL**
- **result**: revert `InvalidAction(ruleIndex, PROVIDE)` before execution.

#### Trace D — REVERT: A random address tries to operate

- **sender**: `randomUser`
- **selector**: `provideLiquidity(...)`
- **params**:
  - `pool = btcEthPool`
  - `usdcAmount = 500e6`
- **rule evaluation**:
  - ruleType 5: **FAIL**
- **result**: revert `InvalidAction(ruleIndex, PROVIDE)` before execution.

#### Trace E — PASS: User B withdraws USDC

- **sender**: `userB`
- **selector**: `withdrawUsdc(uint256)`
- **params**:
  - `amount = 250e6`
- **rule evaluation**:
  - ruleType 5 (withdraw): PASS (sender matches)
- **result**: `delegatecall` executes withdraw logic; User B recovers USDC.

#### Trace F — REVERT: User A attempts to withdraw User B’s USDC

- **sender**: `userA`
- **selector**: `withdrawUsdc(uint256)`
- **rule evaluation**:
  - ruleType 5 (withdraw): **FAIL**
- **result**: revert `InvalidAction(ruleIndex, WITHDRAW)` before execution.

### Why this matters (SRPE’s promise)

This pattern enables:

- **Idle on-chain liquidity activation**: capital providers can deploy constrained products that put idle assets to work without trusting an operator.
- **More liquidity for external protocols**: more capital can safely flow into Uniswap and similar venues under programmable constraints.
- **Reputation-based leverage**: professional DeFi operators can scale by accessing capital based on verifiable performance, optionally combined with small collateral requirements enforced by policy.

In short: SRPE provides a programmable system of **state + policy + execution** that can coordinate capital and behavior without intermediaries.

**User B's USDC earns yield on Uniswap. User A scales their strategy. Neither had to trust the other.**

---

## Appendix: Current SRPE “separation of responsibilities”

SRPE separates four responsibilities:

- **RPFPDeployer**: deploys and registers a new RPFP.
- **RPFPStorage**: stores RPFP configuration and selector-based rule blobs.
- **UniversalExecutor**: the single user entrypoint (`execute()`), `delegatecall`s into the LogicExecutor only if rules pass.
- **UniversalRuler**: validates actions before execution by reading rules and (when applicable) Sendra accumulators.

