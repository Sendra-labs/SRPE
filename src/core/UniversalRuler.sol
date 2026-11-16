// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SRPELib} from "../libs/SRPE/SRPE.lib.sol";
import {SendraLib} from "../libs/core/Sendra.lib.sol";
import {ISendraStorage} from "../interfaces/isendra/ISendraStorage.sol";
import {ISendraAddressProvider} from "../interfaces/isendra/ISendraAddressProvider.sol";
import {RPFPStorage} from "./storage/RPFPStorage.sol";
import {RulesHelper} from "./RulesHelper.sol";

/// @dev Implemented by `UniversalExecutor`. True only during the product `delegatecall`.
interface IEnclaveGuard {
    function isInsideLogic() external view returns (bool);
}

/// @title UniversalRuler
/// @notice Enforces an enclave's global rules and its per-selector rules before any product code runs.
/// @dev Rules are AND. A list or a token pair is the only OR. Unknown rule ids, unknown selectors,
///      malformed accumulator samples, and non-zero `msg.value` without rule 43 all revert.
///      Signed global fields (`cumulativeRealizedPnl`, `highWaterMark`) are compared as `int256`.
///      V1 cast those fields to `uint256`, so a negative PnL passed a "greater than" check.
///      The product implementation is still trusted to use the inputs these rules constrain.
///      `RPFPStorage` and `SendraStorage` are pinned at construction; a later AddressProvider
///      change cannot retarget policy or reputation for enclaves that use this ruler.
contract UniversalRuler is RulesHelper {
    ISendraAddressProvider public immutable addressProvider;
    RPFPStorage public immutable rpfpStorage;
    ISendraStorage public immutable sendraStorage;

    /// @notice Last successful gated call, keyed by enclave, selector, and sender.
    mapping(bytes32 => uint256) public lastExecutedAt;

    bytes32 private constant _GUARD_SLOT = keccak256("srpe.ruler.guard");

    constructor(address _addressProvider, address _rpfpStorage, address _sendraStorage) {
        if (_addressProvider == address(0) || _rpfpStorage == address(0) || _sendraStorage == address(0)) {
            revert InvalidDeployment();
        }
        if (_rpfpStorage.code.length == 0 || _sendraStorage.code.length == 0) revert InvalidDeployment();
        addressProvider = ISendraAddressProvider(_addressProvider);
        rpfpStorage = RPFPStorage(_rpfpStorage);
        sendraStorage = ISendraStorage(_sendraStorage);
    }

    /// @notice Simulates enforcement, including cooldown, without recording a new execution.
    function previewExecution(bytes calldata actionData, address sender, uint256 rpfpId, uint256 callValue)
        external
        view
        returns (bytes4 selector)
    {
        (selector,) = _evaluate(actionData, sender, rpfpId, callValue, false);
    }

    /// @notice Enforces policy and records cooldown. Callable only by the enclave's executor,
    ///         and only before that executor enters the product `delegatecall`.
    function checkExecution(bytes calldata actionData, address sender, uint256 rpfpId, uint256 callValue)
        external
        returns (bytes4 selector)
    {
        if (_tload(_GUARD_SLOT) == 1) revert Reentrancy();
        _tstore(_GUARD_SLOT, 1);

        uint256 minInterval;
        (selector, minInterval) = _evaluate(actionData, sender, rpfpId, callValue, true);
        if (minInterval != 0) {
            lastExecutedAt[_cooldownKey(rpfpId, selector, sender)] = block.timestamp;
        }

        _tstore(_GUARD_SLOT, 0);
    }

    function _evaluate(
        bytes calldata actionData,
        address sender,
        uint256 rpfpId,
        uint256 callValue,
        bool enforceCaller
    ) internal view returns (bytes4 selector, uint256 minInterval) {
        selector = selectorOf(actionData);
        (address boundExecutor, SRPELib.Rules memory globalRules, SRPELib.Rules memory functionRules) =
            rpfpStorage.getEnforcedRules(rpfpId, selector);

        if (boundExecutor == address(0)) revert UnknownEnclave(rpfpId);
        if (enforceCaller) {
            if (msg.sender != boundExecutor) revert OnlyExecutor(msg.sender);
            if (IEnclaveGuard(boundExecutor).isInsideLogic()) revert Reentrancy();
        }
        if (functionRules.rules.length == 0) revert SelectorNotAllowed(selector);

        EvalState memory state;
        state.sender = sender;
        state.executor = boundExecutor;
        state.callValue = callValue;
        state.selector = selector;

        _applySet(globalRules, actionData, state, true);
        _applySet(functionRules, actionData, state, false);

        if (callValue > 0 && !state.sawValueRule) revert UnexpectedCallValue();
        if (state.minInterval != 0) {
            uint256 last = lastExecutedAt[_cooldownKey(rpfpId, selector, sender)];
            if (last != 0 && (block.timestamp < last || block.timestamp - last < state.minInterval)) {
                uint256 readyAt =
                    last > type(uint256).max - state.minInterval ? type(uint256).max : last + state.minInterval;
                revert CooldownActive(selector, readyAt);
            }
        }
        minInterval = state.minInterval;
    }

    function _applySet(SRPELib.Rules memory rules, bytes calldata actionData, EvalState memory state, bool global)
        internal
        view
    {
        uint256 n = rules.rules.length;
        if (rules.ruleCount != n) revert RuleCountMismatch(rules.ruleCount, n);
        if (n > SRPELib.MAX_RULES) revert InvalidRules(n, SRPELib.MAX_RULES);
        for (uint256 i = 0; i < n;) {
            if (!_pass(rules.rules[i], actionData, state)) {
                if (global) revert InvalidGlobalRule(i, state.selector);
                revert InvalidAction(i, state.selector);
            }
            unchecked {
                ++i;
            }
        }
    }

    function _pass(SRPELib.Rule memory rule, bytes calldata actionData, EvalState memory state)
        internal
        view
        returns (bool)
    {
        uint16 t = rule.ruleType;
        if (t == SRPELib.RULE_NONE || t == SRPELib.RULE_NONE_LEGACY) return true;
        if (t == SRPELib.RULE_SENDER_ALLOWLIST) {
            return listed(abi.decode(rule.ruleData, (address[])), state.sender, true);
        }
        if (t == SRPELib.RULE_SENDER_DENYLIST) {
            return listed(abi.decode(rule.ruleData, (address[])), state.sender, false);
        }
        if (t == SRPELib.RULE_TIMESTAMP) {
            (uint256 threshold, uint256 op) = abi.decode(rule.ruleData, (uint256, uint256));
            return compareUint(block.timestamp, threshold, op);
        }
        if (t == SRPELib.RULE_COOLDOWN) {
            uint256 interval = abi.decode(rule.ruleData, (uint256));
            if (interval == 0) return false;
            if (interval > state.minInterval) state.minInterval = interval;
            return true;
        }
        if (t == SRPELib.RULE_SENDER_SELECTOR) {
            (bytes4 allowedSelector, address allowedSender) = abi.decode(rule.ruleData, (bytes4, address));
            return state.selector == allowedSelector && state.sender == allowedSender;
        }
        if (t == SRPELib.RULE_SENDER_SELECTOR_WORD) {
            (bytes4 allowedSelector, address allowedSender, uint256 paramIndex, bytes32 expected) =
                abi.decode(rule.ruleData, (bytes4, address, uint256, bytes32));
            return state.selector == allowedSelector && state.sender == allowedSender
                && readWord(actionData, paramIndex) == expected;
        }
        if (t == SRPELib.RULE_SELECTOR_WORD) {
            (bytes4 allowedSelector, uint256 paramIndex, bytes32 expected) =
                abi.decode(rule.ruleData, (bytes4, uint256, bytes32));
            return state.selector == allowedSelector && readWord(actionData, paramIndex) == expected;
        }
        if (t == SRPELib.RULE_UINT_RANGE) {
            uint256 paramIndex = abi.decode(rule.extraData, (uint256));
            (uint256 min, uint256 max) = abi.decode(rule.ruleData, (uint256, uint256));
            return inRange(min, max, uint256(readWord(actionData, paramIndex)));
        }
        if (t >= SRPELib.RULE_CAPITAL_IN && t <= SRPELib.RULE_MAX_CONSECUTIVE_LOSSES) {
            return _passGlobal(t, rule.ruleData, state);
        }
        if (t >= SRPELib.RULE_SPECIFIC_PNL && t <= SRPELib.RULE_SPECIFIC_METRIC) {
            return _passSpecific(rule, state);
        }
        if (t == SRPELib.RULE_PARAM_WORD) {
            (uint256 paramIndex, bytes32 expected) = abi.decode(rule.ruleData, (uint256, bytes32));
            return readWord(actionData, paramIndex) == expected;
        }
        if (t == SRPELib.RULE_PARAM_ALLOWLIST || t == SRPELib.RULE_PARAM_DENYLIST) {
            (uint256 paramIndex, address[] memory list) = abi.decode(rule.ruleData, (uint256, address[]));
            address account = address(uint160(uint256(readWord(actionData, paramIndex))));
            return listed(list, account, t == SRPELib.RULE_PARAM_ALLOWLIST);
        }
        if (t == SRPELib.RULE_PARAM_UINT_RANGE) {
            (uint256 paramIndex, uint256 min, uint256 max) = abi.decode(rule.ruleData, (uint256, uint256, uint256));
            return inRange(min, max, uint256(readWord(actionData, paramIndex)));
        }
        if (t == SRPELib.RULE_PARAM_UINT_BOUND) {
            (uint256 paramIndex, uint256 threshold, uint256 op) = abi.decode(rule.ruleData, (uint256, uint256, uint256));
            return compareUint(uint256(readWord(actionData, paramIndex)), threshold, op);
        }
        if (t == SRPELib.RULE_PARAM_ACCOUNT) {
            (uint256 paramIndex, uint8 account) = abi.decode(rule.ruleData, (uint256, uint8));
            address got = address(uint160(uint256(readWord(actionData, paramIndex))));
            if (account == SRPELib.ACCOUNT_SENDER) return got == state.sender;
            if (account == SRPELib.ACCOUNT_EXECUTOR) return got == state.executor;
            return false;
        }
        if (t == SRPELib.RULE_CALL_VALUE) {
            state.sawValueRule = true;
            (uint256 threshold, uint256 op) = abi.decode(rule.ruleData, (uint256, uint256));
            return compareUint(state.callValue, threshold, op);
        }
        if (t == SRPELib.RULE_DERIVED) return _passDerived(rule.ruleData, state);
        if (t == SRPELib.RULE_PARAM_PAIR) return matchesPair(actionData, rule.ruleData);
        revert UnsupportedRule(t);
    }

    function _passGlobal(uint16 ruleType, bytes memory ruleData, EvalState memory state) internal view returns (bool) {
        _loadGlobal(state);
        (uint256 threshold, uint256 op) = abi.decode(ruleData, (uint256, uint256));
        uint256 field = uint256(ruleType) - SRPELib.RULE_CAPITAL_IN;
        if (field == 4) return compareInt(state.global.cumulativeRealizedPnl, asInt(threshold), op);
        if (field == 7) return compareInt(state.global.highWaterMark, asInt(threshold), op);
        return compareUint(_globalUint(state.global, field), threshold, op);
    }

    function _passSpecific(SRPELib.Rule memory rule, EvalState memory state) internal view returns (bool) {
        if (rule.ruleType == SRPELib.RULE_SPECIFIC_METRIC) {
            (uint64 metricKey, uint256 metricIndex, uint8 kind, int256 metricThreshold, uint256 metricOp) =
                abi.decode(rule.ruleData, (uint64, uint256, uint8, int256, uint256));
            _loadSpecific(state, metricKey);
            if (metricIndex >= state.specific.specificMetrics.length) return false;
            bytes memory blob = state.specific.specificMetrics[metricIndex];
            if (blob.length != 32) return false;
            if (kind == SRPELib.METRIC_UINT) {
                if (metricThreshold < 0) return false;
                // Non-negative int fits uint256.
                return compareUint(abi.decode(blob, (uint256)), uint256(metricThreshold), metricOp);
            }
            if (kind == SRPELib.METRIC_INT) return compareInt(abi.decode(blob, (int256)), metricThreshold, metricOp);
            return false;
        }

        (uint64 key, int256 threshold, uint256 op) = abi.decode(rule.ruleData, (uint64, int256, uint256));
        _loadSpecific(state, key);
        if (rule.ruleType == SRPELib.RULE_SPECIFIC_PNL) return compareInt(state.specific.realizedPnl, threshold, op);
        if (threshold < 0) return false;
        uint256 observed;
        uint16 t = rule.ruleType;
        if (t == SRPELib.RULE_SPECIFIC_CAPITAL_IN) observed = state.specific.totalCapitalIn;
        else if (t == SRPELib.RULE_SPECIFIC_CAPITAL_OUT) observed = state.specific.totalCapitalOut;
        else if (t == SRPELib.RULE_SPECIFIC_WINS) observed = state.specific.winCount;
        else if (t == SRPELib.RULE_SPECIFIC_LOSSES) observed = state.specific.lossCount;
        else if (t == SRPELib.RULE_SPECIFIC_POSITIONS) observed = state.specific.totalPositions;
        else return false;
        // Rejected above when negative, so the magnitude fits uint256.
        return compareUint(observed, uint256(threshold), op);
    }

    function _passDerived(bytes memory ruleData, EvalState memory state) internal view returns (bool) {
        (uint8 metricId, int256 threshold, uint256 op) = abi.decode(ruleData, (uint8, int256, uint256));
        _loadGlobal(state);
        (uint256 unsignedValue, int256 signedValue, bool isSigned, bool ok) = _derived(state.global, metricId);
        if (!ok) return false;
        if (isSigned) return compareInt(signedValue, threshold, op);
        if (threshold < 0) return false;
        // Rejected above when negative, so the magnitude fits uint256.
        return compareUint(unsignedValue, uint256(threshold), op);
    }

    function _loadGlobal(EvalState memory state) internal view {
        if (state.globalReady) return;
        state.global = sendraStorage.getUserGlobalAccumulators(state.sender);
        state.globalReady = true;
    }

    function _loadSpecific(EvalState memory state, uint64 key) internal view {
        if (state.specificReady && state.specificKey == key) return;
        state.specific = sendraStorage.getUserSpecificAccumulators(state.sender, key);
        state.specificKey = key;
        state.specificReady = true;
    }

    function _globalUint(SendraLib.GlobalAccumulators memory g, uint256 field) internal pure returns (uint256) {
        if (field == 0) return g.totalCapitalIn;
        if (field == 1) return g.totalCapitalOut;
        if (field == 2) return g.peakSimultaneousExposure;
        if (field == 3) return g.currentExposure;
        if (field == 5) return g.grossProfit;
        if (field == 6) return g.grossLoss;
        if (field == 8) return g.maxDrawdown;
        if (field == 9) return g.totalPositionsOpened;
        if (field == 10) return g.totalPositionsClosed;
        if (field == 11) return g.winCount;
        if (field == 12) return g.lossCount;
        if (field == 13) return g.totalDurationSeconds;
        if (field == 14) return g.firstActivityTimestamp;
        if (field == 15) return g.lastActivityTimestamp;
        if (field == 16) return g.totalLiquidationEvents;
        if (field == 17) return g.consecutiveLosses;
        if (field == 18) return g.maxConsecutiveLosses;
        return 0;
    }

    /// @dev Undefined samples return `ok = false` and the rule fails closed.
    function _derived(SendraLib.GlobalAccumulators memory g, uint8 metricId)
        internal
        pure
        returns (uint256 unsignedValue, int256 signedValue, bool isSigned, bool ok)
    {
        if (metricId == SRPELib.DERIVED_PROFIT_FACTOR_BPS) {
            if (g.grossLoss == 0) {
                return (g.grossProfit == 0 ? 0 : type(uint256).max, 0, false, true);
            }
            return (_bps(g.grossProfit, g.grossLoss), 0, false, true);
        }
        if (metricId == SRPELib.DERIVED_WIN_RATE_BPS) {
            if (g.totalPositionsClosed == 0) return (0, 0, false, g.winCount == 0);
            return (_bps(g.winCount, g.totalPositionsClosed), 0, false, true);
        }
        if (metricId == SRPELib.DERIVED_ROI_BPS) {
            if (
                g.totalCapitalIn == 0 || g.totalCapitalIn > uint256(type(int256).max)
                    || g.totalCapitalOut > uint256(type(int256).max)
            ) return (0, 0, true, false);
            int256 delta = int256(g.totalCapitalOut) - int256(g.totalCapitalIn);
            if (delta > type(int256).max / int256(SRPELib.BPS) || delta < type(int256).min / int256(SRPELib.BPS)) {
                return (0, 0, true, false);
            }
            return (0, (delta * int256(SRPELib.BPS)) / int256(g.totalCapitalIn), true, true);
        }
        if (metricId == SRPELib.DERIVED_DRAWDOWN) {
            if (g.highWaterMark <= g.cumulativeRealizedPnl) return (0, 0, false, true);
            unchecked {
                return (uint256(g.highWaterMark) - uint256(g.cumulativeRealizedPnl), 0, false, true);
            }
        }
        if (metricId == SRPELib.DERIVED_AVG_HOLD) {
            if (g.totalPositionsClosed == 0) return (0, 0, false, true);
            return (g.totalDurationSeconds / g.totalPositionsClosed, 0, false, true);
        }
        if (metricId == SRPELib.DERIVED_NET_PNL) return (0, g.cumulativeRealizedPnl, true, true);
        if (metricId == SRPELib.DERIVED_SENIORITY) {
            if (g.firstActivityTimestamp == 0) return (0, 0, false, true);
            if (g.lastActivityTimestamp < g.firstActivityTimestamp) return (0, 0, false, false);
            return (g.lastActivityTimestamp - g.firstActivityTimestamp, 0, false, true);
        }
        if (metricId == SRPELib.DERIVED_OPEN_POSITIONS) {
            if (g.totalPositionsOpened < g.totalPositionsClosed) return (0, 0, false, false);
            return (g.totalPositionsOpened - g.totalPositionsClosed, 0, false, true);
        }
        return (0, 0, false, false);
    }

    function _bps(uint256 num, uint256 den) internal pure returns (uint256) {
        if (den == 0) return 0;
        if (num > type(uint256).max / SRPELib.BPS) return type(uint256).max;
        return (num * SRPELib.BPS) / den;
    }

    function _cooldownKey(uint256 rpfpId, bytes4 selector, address sender) internal pure returns (bytes32) {
        return keccak256(abi.encode(rpfpId, selector, sender));
    }

    function _tload(bytes32 slot) private view returns (uint256 value) {
        assembly {
            value := tload(slot)
        }
    }

    function _tstore(bytes32 slot, uint256 value) private {
        assembly {
            tstore(slot, value)
        }
    }

    struct EvalState {
        address sender;
        address executor;
        uint256 callValue;
        bytes4 selector;
        uint256 minInterval;
        bool sawValueRule;
        bool globalReady;
        SendraLib.GlobalAccumulators global;
        bool specificReady;
        uint64 specificKey;
        SendraLib.SpecificAccumulators specific;
    }

    error InvalidAction(uint256 ruleIndex, bytes4 functionSelector);
    error InvalidGlobalRule(uint256 ruleIndex, bytes4 functionSelector);
    error SelectorNotAllowed(bytes4 functionSelector);
    error OnlyExecutor(address caller);
    error Reentrancy();
    error CooldownActive(bytes4 functionSelector, uint256 readyAt);
    error UnexpectedCallValue();
    error UnknownEnclave(uint256 rpfpId);
    error InvalidDeployment();
}
