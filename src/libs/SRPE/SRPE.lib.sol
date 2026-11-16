// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title SRPELib
/// @notice Types, limits, and rule identifiers for the Sendra Rule-Programmable Environment.
/// @dev Rule payloads are ABI-encoded. Comparison ops are shared by every threshold rule:
///      - 0 `OP_GT`: observed > threshold
///      - 1 `OP_LT`: observed < threshold
///      - 2 `OP_GE`: observed >= threshold
///      - 3 `OP_LE`: observed <= threshold
///      - 4 `OP_EQ`: observed == threshold
///      Ops 0 and 1 preserve the V1 `uint256[2]` encoding `(threshold, op)`.
///      Input rules read a static ABI word at `4 + 32 * paramIndex`. Dynamic arguments are not
///      followed: a `bytes` or array parameter contributes its offset word, not its contents.
library SRPELib {
    uint256 internal constant MAX_RULES = 16;
    uint256 internal constant MAX_FUNCTION_SELECTORS = 32;
    uint256 internal constant MAX_LIST = 16;
    /// @notice Highest accepted static-parameter index, inclusive.
    uint256 internal constant MAX_PARAM_INDEX = 15;
    uint256 internal constant BPS = 10_000;

    uint256 internal constant OP_GT = 0;
    uint256 internal constant OP_LT = 1;
    uint256 internal constant OP_GE = 2;
    uint256 internal constant OP_LE = 3;
    uint256 internal constant OP_EQ = 4;

    uint8 internal constant ACCOUNT_SENDER = 0;
    uint8 internal constant ACCOUNT_EXECUTOR = 1;
    uint8 internal constant METRIC_UINT = 0;
    uint8 internal constant METRIC_INT = 1;

    uint8 internal constant DERIVED_PROFIT_FACTOR_BPS = 0;
    uint8 internal constant DERIVED_WIN_RATE_BPS = 1;
    uint8 internal constant DERIVED_ROI_BPS = 2;
    uint8 internal constant DERIVED_DRAWDOWN = 3;
    uint8 internal constant DERIVED_AVG_HOLD = 4;
    uint8 internal constant DERIVED_NET_PNL = 5;
    uint8 internal constant DERIVED_SENIORITY = 6;
    uint8 internal constant DERIVED_OPEN_POSITIONS = 7;

    uint16 internal constant RULE_NONE = 0;
    uint16 internal constant RULE_SENDER_ALLOWLIST = 1;
    uint16 internal constant RULE_SENDER_DENYLIST = 2;
    uint16 internal constant RULE_TIMESTAMP = 3;
    uint16 internal constant RULE_COOLDOWN = 4;
    uint16 internal constant RULE_SENDER_SELECTOR = 5;
    uint16 internal constant RULE_SENDER_SELECTOR_WORD = 6;
    uint16 internal constant RULE_SELECTOR_WORD = 7;
    uint16 internal constant RULE_UINT_RANGE = 8;
    uint16 internal constant RULE_NONE_LEGACY = 9;
    uint16 internal constant RULE_CAPITAL_IN = 10;
    uint16 internal constant RULE_CAPITAL_OUT = 11;
    uint16 internal constant RULE_PEAK_EXPOSURE = 12;
    uint16 internal constant RULE_CURRENT_EXPOSURE = 13;
    uint16 internal constant RULE_REALIZED_PNL = 14;
    uint16 internal constant RULE_GROSS_PROFIT = 15;
    uint16 internal constant RULE_GROSS_LOSS = 16;
    uint16 internal constant RULE_HIGH_WATER_MARK = 17;
    uint16 internal constant RULE_MAX_DRAWDOWN = 18;
    uint16 internal constant RULE_POSITIONS_OPENED = 19;
    uint16 internal constant RULE_POSITIONS_CLOSED = 20;
    uint16 internal constant RULE_WIN_COUNT = 21;
    uint16 internal constant RULE_LOSS_COUNT = 22;
    uint16 internal constant RULE_DURATION = 23;
    uint16 internal constant RULE_FIRST_ACTIVITY = 24;
    uint16 internal constant RULE_LAST_ACTIVITY = 25;
    uint16 internal constant RULE_LIQUIDATIONS = 26;
    uint16 internal constant RULE_CONSECUTIVE_LOSSES = 27;
    uint16 internal constant RULE_MAX_CONSECUTIVE_LOSSES = 28;
    uint16 internal constant RULE_SPECIFIC_PNL = 30;
    uint16 internal constant RULE_SPECIFIC_CAPITAL_IN = 31;
    uint16 internal constant RULE_SPECIFIC_CAPITAL_OUT = 32;
    uint16 internal constant RULE_SPECIFIC_WINS = 33;
    uint16 internal constant RULE_SPECIFIC_LOSSES = 34;
    uint16 internal constant RULE_SPECIFIC_POSITIONS = 35;
    uint16 internal constant RULE_SPECIFIC_METRIC = 36;
    uint16 internal constant RULE_PARAM_WORD = 37;
    uint16 internal constant RULE_PARAM_ALLOWLIST = 38;
    uint16 internal constant RULE_PARAM_DENYLIST = 39;
    uint16 internal constant RULE_PARAM_UINT_RANGE = 40;
    uint16 internal constant RULE_PARAM_UINT_BOUND = 41;
    uint16 internal constant RULE_PARAM_ACCOUNT = 42;
    uint16 internal constant RULE_CALL_VALUE = 43;
    uint16 internal constant RULE_DERIVED = 44;
    uint16 internal constant RULE_PARAM_PAIR = 45;

    /// @notice Deployment payload for one enclave (RPFP).
    /// @dev `rules` are global and are AND-ed with the selector rules at execution.
    ///      `ruler` must be the canonical `UniversalRuler` or zero (filled by the deployer).
    ///      Custom rulers are rejected: an arbitrary ruler could allow every action.
    struct NewRPFPInputs {
        uint16 _type;
        address implementation;
        address ruler;
        address[] owners;
        string description;
        bytes extraData;
        Rules rules;
        Instructions instructions;
        bytes4[] functionSelectors;
        Rules[] functionSelectorRules;
    }

    /// @notice Stored enclave record. `functionRules` is not ABI-returnable.
    struct RPFP {
        uint16 _type;
        uint256 id;
        address executor;
        address implementation;
        address ruler;
        address[] owners;
        /// @notice `msg.sender` of `deployRPFP`. Metadata only; not an admin key.
        address creator;
        string description;
        bytes extraData;
        uint256 createdAt;
        Rules rules;
        Instructions instructions;
        mapping(bytes4 => Rules) functionRules;
    }

    /// @notice ABI-returnable view of an enclave, without rules or instructions.
    struct RPFPForRead {
        uint16 _type;
        uint256 id;
        address executor;
        address implementation;
        address ruler;
        address[] owners;
        address creator;
        string description;
        bytes extraData;
        uint256 createdAt;
    }

    /// @notice Off-chain catalog of callable actions. Not enforced at runtime.
    struct Instructions {
        Instruction[] instructions;
    }

    /// @notice Human-readable description of one action. Enforcement uses `functionRules`.
    struct Instruction {
        bytes4 functionSelector;
        bytes functionSignature;
        uint8[] rulesIndexes;
        uint8[] parameterTypes;
    }

    /// @notice Calldata for `UniversalExecutor.execute`.
    /// @dev `targetFunction` is reserved for clients. The ruler reads the selector from `actionData`.
    struct ExecutionParams {
        uint256 targetFunction;
        uint256 rpfpId;
        bytes actionData;
    }

    /// @notice One constraint.
    /// @dev `extraData` is used only by rule 8 (parameter index). Every other rule must leave it empty.
    ///
    /// Encodings (`ruleData`):
    /// - 0, 9: empty. Explicit no-op. A selector still needs at least one rule.
    /// - 1, 2: `abi.encode(address[] list)`. List length is 1..16. 1 allows, 2 denies.
    /// - 3: `abi.encode(uint256 threshold, uint256 op)` compared with `block.timestamp`.
    /// - 4: `abi.encode(uint256 minInterval)`. Per sender, per selector. The first call is allowed.
    /// - 5: `abi.encode(bytes4 selector, address sender)`.
    /// - 6: `abi.encode(bytes4 selector, address sender, uint256 paramIndex, bytes32 expected)`.
    /// - 7: `abi.encode(bytes4 selector, uint256 paramIndex, bytes32 expected)`.
    /// - 8: `ruleData = abi.encode(uint256 min, uint256 max)`, `extraData = abi.encode(uint256 paramIndex)`.
    ///      Inclusive. V1 compared with a strict open interval.
    /// - 10..28: `abi.encode(uint256 threshold, uint256 op)` against one global accumulator.
    ///      Field order matches `SendraLib.GlobalAccumulators`. Types 14 and 17 are signed.
    /// - 30: `abi.encode(uint64 specificKey, int256 threshold, uint256 op)` realized PnL.
    /// - 31..35: `abi.encode(uint64 specificKey, int256 threshold, uint256 op)` unsigned specific fields.
    ///      A negative threshold fails closed.
    /// - 36: `abi.encode(uint64 key, uint256 metricIndex, uint8 kind, int256 threshold, uint256 op)`.
    ///      `kind` 0 decodes 32 bytes as `uint256`, kind 1 as `int256`. Any other blob fails closed.
    /// - 37: `abi.encode(uint256 paramIndex, bytes32 expected)`.
    /// - 38, 39: `abi.encode(uint256 paramIndex, address[] list)` allow / deny a static address argument.
    /// - 40: `abi.encode(uint256 paramIndex, uint256 min, uint256 max)` inclusive.
    /// - 41: `abi.encode(uint256 paramIndex, uint256 threshold, uint256 op)`.
    /// - 42: `abi.encode(uint256 paramIndex, uint8 account)` where 0 is `msg.sender` and 1 is the executor.
    /// - 43: `abi.encode(uint256 threshold, uint256 op)` compared with `msg.value`.
    ///      Non-zero value is rejected unless a rule 43 is present on the global set or the selector.
    /// - 44: `abi.encode(uint8 metricId, int256 threshold, uint256 op)` derived from global accumulators.
    ///      0 profit factor bps, 1 win rate bps, 2 ROI bps (signed), 3 current drawdown,
    ///      4 average hold seconds, 5 net realized PnL (signed), 6 seniority seconds, 7 open positions.
    ///      Undefined samples (for example ROI with no capital in, or win rate with wins but no closes)
    ///      fail closed. Zero closes and zero wins is a 0 win rate. Zero losses and positive profit is
    ///      the maximum profit factor.
    /// - 45: `abi.encode(uint256 indexA, uint256 indexB, bool unordered, address[] a, address[] b)`.
    ///      Parallel arrays, length 1..16. Used to pin an LP pair, in either order when `unordered` is set.
    ///
    /// Unknown ids fail closed. Rules on one selector are AND. OR exists only inside a list or a pair.
    /// Global rules may not depend on calldata layout (types 5..8 and 37..42 and 45 are selector-only).
    struct Rule {
        uint16 ruleType;
        bytes ruleData;
        bytes extraData;
    }

    struct Rules {
        uint256 ruleCount;
        Rule[] rules;
    }
}
