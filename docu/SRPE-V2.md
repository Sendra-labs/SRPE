# SRPE V2

V2 is the enclave runtime in this branch. V1 is the MVP it replaces. Names are unchanged: `RPFPDeployer`, `RPFPStorage`, `UniversalExecutor`, `UniversalRuler`, `RulesHelper`, `SRPELib`.

## V1

V1 gated `UniversalExecutor.execute` with selector rules stored in `RPFPStorage`.

Supported and actually enforced:

- 0 and 9, no-op
- 1 and 2, sender allowlist and denylist
- 3, timestamp, strict `>` or `<`
- 5, 6 and 7, selector plus sender and one exact calldata word
- 8, uint range on a parameter index carried in `extraData`, exclusive bounds
- 10–28, one global Sendra accumulator each, strict `>` or `<`

Not enforced, and skipped at runtime (fail open):

- 4, frequency
- 29 and every id above 28, including the documented specific-accumulator ids 30–36
- any selector that had never been registered
- the global rule catalog
- the `ruler` stored on the enclave; execution always used the AddressProvider's current ruler

Also wrong:

- `cumulativeRealizedPnl` and `highWaterMark` were cast to `uint256`. A negative book became a huge unsigned value and could satisfy a minimum.
- `setFunctionRules` stayed open to every protocol contract.
- `execute` forwarded ETH with no rule.
- The executor re-read storage and ruler from the AddressProvider, so an admin could point a live enclave at other code or other rules.
- Rule 8 could not express "at least 100 and at most 1_000" including the endpoints, and there was no way to say "pool is one of these" because every rule was AND and rule 7 stored a single word.

## V2

Same entrypoints. The ruler fails closed.

| Gap in V1 | V2 |
| --- | --- |
| Unknown selector runs the logic | `SelectorNotAllowed` |
| Unknown rule id is skipped | `UnsupportedRule` |
| `ruleCount` shorter than the array ignores the tail | `RuleCountMismatch` |
| Global rules are documentation | Global rules are AND-ed with the selector |
| Specific accumulators are comments | Rules 30–36 read `getUserSpecificAccumulators` |
| No derived ratios | Rule 44 |
| One exact address per input rule | Rules 38, 39 and 45: list or pair |
| Exclusive uint range | Rules 8 and 40 are inclusive |
| Negative PnL wraps | Rules 14 and 17 compare `int256` |
| Frequency is empty | Rule 4 records a cooldown on the ruler |
| ETH is unconditional | Rule 43, otherwise non-zero value reverts |
| Rules stay writable | `lockRules` at the end of `deployRPFP` |
| Provider can retarget an enclave | Executor pins storage and ruler. Ruler pins storage and Sendra Storage |
| Custom ruler field is silently ignored | Any ruler other than the canonical one is rejected |
| No simulation | `previewExecution` |

Rule ids, op codes, and encodings are specified on `SRPELib.Rule`.

### Comparison

`op` 0 and 1 keep the V1 meaning.

| op | Passes when |
| --- | --- |
| 0 | observed > threshold |
| 1 | observed < threshold |
| 2 | observed >= threshold |
| 3 | observed <= threshold |
| 4 | observed == threshold |

### Global accumulators (10–28)

The id minus 10 is the field order in `SendraLib.GlobalAccumulators`.

| Id | Field | Signed |
| --- | --- | --- |
| 10 | totalCapitalIn | no |
| 11 | totalCapitalOut | no |
| 12 | peakSimultaneousExposure | no |
| 13 | currentExposure | no |
| 14 | cumulativeRealizedPnl | yes |
| 15 | grossProfit | no |
| 16 | grossLoss | no |
| 17 | highWaterMark | yes |
| 18 | maxDrawdown | no |
| 19 | totalPositionsOpened | no |
| 20 | totalPositionsClosed | no |
| 21 | winCount | no |
| 22 | lossCount | no |
| 23 | totalDurationSeconds | no |
| 24 | firstActivityTimestamp | no |
| 25 | lastActivityTimestamp | no |
| 26 | totalLiquidationEvents | no |
| 27 | consecutiveLosses | no |
| 28 | maxConsecutiveLosses | no |

Payload: `abi.encode(uint256 threshold, uint256 op)`. A negative threshold is encoded as `abi.encode(int256 threshold, uint256 op)`; the ABI layout is the same two words.

### Specific accumulators (30–36)

`specificKey` selects `SendraPulse.specificPulse`. Use a different key per strategy or venue so an LP book is not mixed with a perps book.

| Id | Field |
| --- | --- |
| 30 | realizedPnl (`int256`) |
| 31 | totalCapitalIn |
| 32 | totalCapitalOut |
| 33 | winCount |
| 34 | lossCount |
| 35 | totalPositions |

Payload for 30–35: `abi.encode(uint64 specificKey, int256 threshold, uint256 op)`. A negative threshold on 31–35 fails closed.

Rule 36: `abi.encode(uint64 key, uint256 metricIndex, uint8 kind, int256 threshold, uint256 op)`.

- kind 0: `abi.decode(blob, (uint256))`
- kind 1: `abi.decode(blob, (int256))`
- any other length, kind, or missing index fails closed

The whole specific struct is loaded once per key per call. Large `specificMetrics` arrays cost gas proportional to their size. Keep metric blobs to one word when a rule must read them.

### Derived metrics (44)

`abi.encode(uint8 metricId, int256 threshold, uint256 op)`.

| metricId | Value |
| --- | --- |
| 0 | profit factor, bps. `grossProfit * 10000 / grossLoss`. Both zero is 0. Profit with zero losses is `type(uint256).max` |
| 1 | win rate, bps. `winCount * 10000 / totalPositionsClosed`. Both zero is 0. Wins with zero closes fails |
| 2 | ROI, signed bps. Undefined, and fails, when `totalCapitalIn` is 0 |
| 3 | current drawdown, `highWaterMark - cumulativeRealizedPnl` when that difference is positive, otherwise 0 |
| 4 | average holding time, seconds. Zero when nothing has closed |
| 5 | `cumulativeRealizedPnl` |
| 6 | `lastActivityTimestamp - firstActivityTimestamp`. Zero when there is no first activity. Fails if last is earlier than first |
| 7 | `totalPositionsOpened - totalPositionsClosed`. Fails if closed exceeds opened |

### Inputs

Indexes address the static ABI head: word `i` starts at byte `4 + 32 * i`. The ruler does not follow dynamic offsets.

| Id | Encoding | Use |
| --- | --- | --- |
| 37 | `(uint256 index, bytes32 expected)` | one pool, one fee, one flag |
| 38 | `(uint256 index, address[] allowed)` | pool or token allowlist, length 1–16 |
| 39 | `(uint256 index, address[] denied)` | token denylist |
| 40 | `(uint256 index, uint256 min, uint256 max)` | inclusive size |
| 41 | `(uint256 index, uint256 threshold, uint256 op)` | one-sided size |
| 42 | `(uint256 index, uint8 account)` | 0 the caller, 1 the executor. Stops an operator from redirecting an LP position |
| 45 | `(uint256 indexA, uint256 indexB, bool unordered, address[] a, address[] b)` | a pair. `unordered` accepts either orientation |

Address comparisons use the low 20 bytes. Rule 37 compares the full word, so a dirty high bit fails closed.

Rule 8 remains for existing payloads: `ruleData` is `(min, max)`, `extraData` is the index. Bounds are inclusive. Every other rule must use empty `extraData`. On a selector, rules 5–7 must embed that same selector.

Global rules are limited to ids that do not depend on calldata layout: 0–4, 9, 10–28, 30–36, 43, 44.

### Cooldown, value, preview

Rule 4 stores `lastExecutedAt[keccak256(rpfpId, selector, sender)]` on the ruler after a successful check. The first call has no previous timestamp and is allowed. A later call waits `minInterval` seconds. Two rule-4 entries on the same action use the longer interval. `previewExecution` reads the timestamp and does not write it.

Rule 43 compares `msg.value`. If value is non-zero and neither the global set nor the selector contains rule 43, the ruler reverts `UnexpectedCallValue`. The product function has to be `payable`; `delegatecall` does not clear `msg.value`.

### Deployment

`deployRPFP` is permissionless. Any EOA or contract may call it. `RPFPStorage` only accepts writes from the canonical `RPFPDeployer` (also listed as a protocol contract), so a forked deployer cannot insert enclaves. Empty `owners` is stored as `[msg.sender]`. `creator` is always the caller. Neither field can later change rules.

`deployRPFP` rejects:

- an implementation with no code, or one that is the storage, ruler, factory, provider, or deployer
- a ruler that is not the canonical `UniversalRuler`, or a ruler pinned to different storage
- duplicate selectors
- empty selector rules, more than 16 rules, more than 32 selectors
- a payload that cannot be enforced (empty list, `min > max`, bad op, negative threshold on an unsigned specific field, input rule on the global set, selector mismatch)

It then creates the executor, writes the enclave, writes each selector, and calls `lockRules`. `setFunctionRules` after that reverts `RulesLocked`.

Writes require the caller to be the AddressProvider's `RPFPDeployer` and a protocol contract.

### Execution

`execute` sets a transient depth flag, checks the pinned ruler, sets a second transient flag for the duration of the `delegatecall`, then clears both. A callback into `execute` reverts `Reentrancy`. A callback into `checkExecution` reverts because `isInsideLogic` is true. The flags sit at `keccak256("srpe.executor.depth")` and `keccak256("srpe.executor.logic")`, not in Solidity's transient allocation, so ordinary product storage does not collide with them. A logic contract that deliberately `tstore`s those slots can disable the guard. That is the same trust already required of the logic: it can also ignore the calldata the ruler just checked.

The ruler's own transient guard (`srpe.ruler.guard`) covers reentry from `SendraStorage` during the check.

### What remains outside the ruler

These are the useful next steps that V2 does not implement, because each one either needs a write API Sendra Storage does not expose here or would weaken the frozen-policy guarantee:

- The enclave does not update Sendra accumulators. Rules read the book; some other Sendra transaction has to write it. A standard post-trade accounting hook would close that loop.
- Frozen rules are the safe default. A timelocked rotation, opted in at deploy and unable to touch an already-frozen enclave, is the way to add rotation later without giving the deployer a hot admin key.
- Lists are capped at 16. A Merkle allowlist is the way to admit a large token universe without raising the per-call gas cap.
- There is no OR between rules. Adding OR groups makes misconfiguration easy (one loose branch disables the rest). Lists and pairs are the OR that LP needs.
