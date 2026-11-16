# SendraLabs Rule-Programmable Environment (SRPE)

Non-custodial execution for financial products. Each product is an enclave: a dedicated executor, a logic contract, and a policy that is checked before that logic runs. Policy can require a sender, a calldata argument (pool, token, amount, recipient), a cooldown, or a figure from Sendra Storage's financial accumulators.

The branch `srpe-v2` is the current implementation. V1 remains the behaviour this version replaces.

## What V1 did

V1 (`develop` before this branch) deployed one `UniversalExecutor` per RPFP and `delegatecall`ed into a logic contract after `UniversalRuler.checkExecution`.

It could:

- allow or deny `msg.sender` (rules 1 and 2)
- bound `block.timestamp` (rule 3)
- require an exact selector plus sender and, optionally, one calldata word (rules 5–7)
- bound one `uint256` argument with an open interval (rule 8)
- compare the caller's **global** Sendra accumulators with a strict greater-than or less-than (rules 10–28)

Rules on one selector were AND. A selector with an explicit no-op (rule 0) was public. Global rules were stored and not enforced. The per-enclave `ruler` field was stored and ignored; every enclave used whatever `UniversalRuler` the AddressProvider currently returned.

V1 did **not** enforce specific accumulators (rules 30–36 were documented only). Rule 4 (frequency) was an empty branch. Any other id was skipped. A selector with no stored rules was allowed. `cumulativeRealizedPnl` and `highWaterMark` were cast to `uint256`, so a negative PnL passed a "greater than" check. Rules could be rewritten later by any protocol contract. `msg.value` was forwarded with no policy.

## What V2 does

V2 keeps the same contracts, storage names, and numeric rule ids. It closes the fail-open paths and adds the rules an LP enclave actually needs.

Enforcement, before `delegatecall`:

1. The selector must have been registered. An unknown selector reverts.
2. Global rules and the selector's rules are both applied. Any failure reverts. There is no OR across rules.
3. Inside one rule, an address list or a token pair is the OR: the argument must be one of the configured values.
4. An unknown rule id reverts. A declared `ruleCount` that does not match the array reverts.
5. Non-zero `msg.value` reverts unless rule 43 is on the global set or on that selector.
6. Signed accumulator fields are compared as `int256`.
7. Specific Sendra books are readable by `uint64` key (rules 30–36), including one 32-byte metric blob.
8. Derived figures (rule 44) are computed from the global book: profit factor, win rate, ROI, current drawdown, average hold, net PnL, seniority, open positions. Undefined samples fail closed.
9. Calldata can be constrained without repeating the selector: exact word (37), address allow and deny (38, 39), inclusive uint range and bound (40, 41), recipient equal to the sender or the executor (42), and an ordered or unordered token pair (45).
10. Rule 4 is a real cooldown, per enclave, selector, and sender. The first call is allowed. `previewExecution` shows the same rejection and does not record the call.

After `deployRPFP` returns, function rules are frozen. A later protocol call cannot rewrite them. The executor pins `RPFPStorage` and `UniversalRuler`. The ruler pins `RPFPStorage` and `SendraStorage`. Changing the AddressProvider does not retarget an enclave that is already deployed. A custom ruler address is rejected, because a private ruler could allow every call.

`previewExecution(actionData, sender, rpfpId, callValue)` is the view path for wallets and UIs.

## Trust boundary

SRPE checks the call. It does not sandbox the logic contract.

- The logic contract is trusted to **use** the arguments the policy checked. A malicious implementation can ignore the pool argument and add liquidity somewhere else. That is a property of `delegatecall`, not something a calldata rule can fix.
- Product code may use the executor's persistent storage. The reentrancy guard lives in namespaced transient slots (`srpe.executor.depth`, `srpe.executor.logic`) and must not be overwritten by the product.
- Sendra Storage is the reputation root. If that contract reports a false book, accumulator rules follow it. V2 pins which storage the ruler reads so a provider swap cannot substitute a fake book for existing enclaves.
- Cooldown uses `block.timestamp`. It is a spacing rule, not a source of randomness.
- Only static ABI words are read. For `provideLiquidity(address pool, address token0, address token1, uint256 amount, address recipient, bytes data)` the indexes are 0..4. Index 5 is the offset of `data`, not the bytes themselves. Do not place a dynamic argument before a word you need to constrain.
- A function that accepts ETH must be `payable`. `delegatecall` preserves `msg.value`, and Solidity rejects value on a non-payable function.
- Rule 8's range is inclusive in V2. V1 used `min < value < max`.

Owners are metadata. They are not an admin key. To change policy, deploy a new enclave.

## Anyone can deploy an RPFP

`RPFPDeployer.deployRPFP` is public. There is no allowlist on the caller. The only gated writes are inside `RPFPStorage`, and they accept **the canonical deployer contract**, not the user. A third party does not need a Sendra role.

1. Deploy your logic contract (the functions you want the enclave to run).
2. Encode rules with `SRPERules` (`src/libs/SRPE/SRPERules.sol`).
3. Call `RPFPDeployer` from the AddressProvider (`getAddress("RPFPDeployer")`).
4. Use the returned `executor` and `rpfpId`. Users call `executor.execute({ rpfpId, actionData })`.

If `owners` is empty, the deployer stores `msg.sender` as owner and as `creator`. That is a label for indexers. It does not grant later writes.

```solidity
import {SRPERules} from "src/libs/SRPE/SRPERules.sol";
import {SRPELib} from "src/libs/SRPE/SRPE.lib.sol";

bytes4 sel = bytes4(keccak256("provideLiquidity(address,address,address,uint256,address)"));
address[] memory pools = new address[](1);
pools[0] = allowedPool;
address[] memory tokenA = new address[](1);
address[] memory tokenB = new address[](1);
tokenA[0] = usdc;
tokenB[0] = weth;

SRPELib.Rule[] memory rules = new SRPELib.Rule[](3);
rules[0] = SRPERules.paramAllowlist(0, pools);
rules[1] = SRPERules.paramPair(1, 2, true, tokenA, tokenB);
rules[2] = SRPERules.paramUintRange(3, 100e6, 1_000e6);

SRPELib.NewRPFPInputs memory inputs = SRPERules.publicAction(logic, sel, "LP enclave");
inputs.functionSelectorRules[0] = SRPERules.pack(rules);

(address executor, uint256 rpfpId) = RPFPDeployer(provider.getAddress("RPFPDeployer")).deployRPFP(inputs);
```

Template script: `script/deployRPFP.s.sol`. Set `ADDRESS_PROVIDER` and `IMPLEMENTATION`, then broadcast. Replace the public `touch()` payload with the rules above.

What you cannot do without being protocol: write `RPFPStorage` yourself, swap the ruler, or unfreeze an enclave. That is the integrity of the registry, not a gate on who may create products.

## Flow

1. `RPFPDeployer.deployRPFP` validates every rule, deploys an executor bound to the current storage and ruler, writes the enclave, stores selector rules, and freezes them.
2. A user calls `UniversalExecutor.execute`. The executor confirms the id belongs to itself, then `UniversalRuler.checkExecution`.
3. On success the executor `delegatecall`s `actionData` into the logic contract and emits `Executed`.

Unregistered selectors never reach the logic contract. The same is true of a failed rule.

Gas on the hot path: the executor reads executor and implementation only (not owners or description). The ruler loads global rules and selector rules in one call. Global accumulators are loaded once, and only if a rule needs them. A specific book is loaded once per key. AddressProvider is not consulted during `execute`.

Caps, set at deploy and checked again at runtime: 16 rules per set, 32 selectors, 16 addresses in a list, parameter index 0..15.

## Rule ids

| Id | Applies to | Payload |
| --- | --- | --- |
| 0, 9 | nothing | explicit no-op |
| 1, 2 | sender | `address[]` allow / deny |
| 3 | `block.timestamp` | `(uint256 threshold, uint256 op)` |
| 4 | cooldown | `(uint256 minInterval)` seconds, must be non-zero |
| 5 | sender and selector | `(bytes4 selector, address sender)` |
| 6 | sender, selector, word | `(bytes4, address, uint256 index, bytes32 expected)` |
| 7 | selector and word | `(bytes4, uint256 index, bytes32 expected)` |
| 8 | uint argument | `ruleData (min, max)`, `extraData (uint256 index)`, inclusive |
| 10–28 | global accumulator | `(uint256 threshold, uint256 op)`. 14 and 17 are signed |
| 30–35 | specific accumulator | `(uint64 key, int256 threshold, uint256 op)` |
| 36 | specific metric blob | `(uint64 key, uint256 index, uint8 kind, int256 threshold, uint256 op)`. Kind 0 is uint, 1 is int. The blob must be 32 bytes |
| 37 | calldata word | `(uint256 index, bytes32 expected)` |
| 38, 39 | address argument | `(uint256 index, address[] list)` allow / deny |
| 40 | uint argument | `(uint256 index, uint256 min, uint256 max)` inclusive |
| 41 | uint argument | `(uint256 index, uint256 threshold, uint256 op)` |
| 42 | address argument | `(uint256 index, uint8 account)`. 0 = sender, 1 = executor |
| 43 | `msg.value` | `(uint256 threshold, uint256 op)` |
| 44 | derived global metric | `(uint8 metricId, int256 threshold, uint256 op)` |
| 45 | token pair | `(uint256 indexA, uint256 indexB, bool unordered, address[] a, address[] b)` |

Comparison `op`: 0 observed > threshold, 1 observed < threshold, 2 `>=`, 3 `<=`, 4 `==`. Ops 0 and 1 are the V1 encoding.

Global rules may not mention a selector or a parameter index. Put input rules on the selector. Types 5–8, 37–42, and 45 are rejected on the global set.

Derived metric ids: 0 profit factor in bps, 1 win rate in bps, 2 ROI in bps (signed), 3 current drawdown, 4 average holding time, 5 net realized PnL (signed), 6 seniority in seconds, 7 open positions. ROI with zero capital in fails. A win rate with wins but zero closes fails. Zero wins and zero closes is a 0 win rate. Positive profit and zero losses is the maximum profit factor.

The authoritative encoding comments are on `SRPELib.Rule` in `src/libs/SRPE/SRPE.lib.sol`.

### LP enclave

`provideLiquidity(address pool, address token0, address token1, uint256 amount, address recipient)` can be gated, in one selector, by:

- rule 1: operator allowlist, or rule 21 / 44 if any reputed operator may act
- rule 38 on index 0: pool allowlist
- rule 45 on indexes 1 and 2: the USDC/WETH pair, either order
- rule 40 on index 3: amount between 100 and 1_000 USDC, inclusive
- rule 42 on index 4, account = 1: the position recipient is the executor, not the operator
- rule 30: specific PnL for that strategy key is above a threshold

A call that names another pool, another token, an out-of-range amount, or a recipient other than the enclave reverts with `InvalidAction(ruleIndex, selector)` before the logic runs. `test/SRPEV2.t.sol` deploys this shape.

## Tests

```bash
forge test --match-contract "RPFPFlowTest|SRPEV2Test"
```

`RPFPFlow` covers the V1 path that still holds: exact input word, deadline, win-count, explicit no-op, executor binding. It also covers the V2 fail-closed cases: unknown selector, bare ETH, frozen rules.

`SRPEV2` covers signed PnL, specific keys and metrics, derived win rate, the LP input rules, inclusive ranges, call value, cooldown, preview, reentrancy, global rules, provider swaps, and rejected deployments.
