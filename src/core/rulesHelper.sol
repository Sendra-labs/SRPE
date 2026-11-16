// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SRPELib} from "../libs/SRPE/SRPE.lib.sol";

/// @title RulesHelper
/// @notice Pure checks and deploy-time validation for SRPE rule payloads.
/// @dev Input reads use the static ABI head only. A parameter index past the head, or a word that
///      is only the offset of a dynamic tail, cannot satisfy an equality or allowlist rule unless
///      the encoded word itself was the configured value.
abstract contract RulesHelper {
    error UnsupportedRule(uint16 ruleType);
    error InvalidRuleData(uint16 ruleType);
    error InvalidRules(uint256 ruleCount, uint256 maxRules);
    error RuleCountMismatch(uint256 declaredCount, uint256 storedLength);
    error ActionDataTooShort();
    error ParamIndexOutOfRange(uint256 paramIndex);

    /// @notice Rejects a rule that cannot be enforced exactly as encoded.
    /// @param selector Selector this rule is attached to. Ignored when `selectorBound` is false.
    /// @param selectorBound True for per-function rules, false for the global set.
    function _validateRule(bytes4 selector, SRPELib.Rule memory rule, bool selectorBound) internal pure {
        uint16 t = rule.ruleType;
        if (!_supported(t)) revert UnsupportedRule(t);
        if (!selectorBound && !_globalSafe(t)) revert InvalidRuleData(t);
        if (t != SRPELib.RULE_UINT_RANGE) {
            if (rule.extraData.length != 0) revert InvalidRuleData(t);
        } else if (rule.extraData.length != 32) {
            revert InvalidRuleData(t);
        }
        if (t == SRPELib.RULE_NONE || t == SRPELib.RULE_NONE_LEGACY) return;

        if (t == SRPELib.RULE_SENDER_ALLOWLIST || t == SRPELib.RULE_SENDER_DENYLIST) {
            _validateAddressList(abi.decode(rule.ruleData, (address[])), t);
            return;
        }
        if (t == SRPELib.RULE_TIMESTAMP || (t >= SRPELib.RULE_CAPITAL_IN && t <= SRPELib.RULE_MAX_CONSECUTIVE_LOSSES)) {
            _validateOp(_secondWord(rule.ruleData, t), t);
            return;
        }
        if (t == SRPELib.RULE_COOLDOWN) {
            if (rule.ruleData.length != 32 || abi.decode(rule.ruleData, (uint256)) == 0) revert InvalidRuleData(t);
            return;
        }
        if (t == SRPELib.RULE_SENDER_SELECTOR) {
            (bytes4 embedded,) = abi.decode(rule.ruleData, (bytes4, address));
            if (selectorBound && embedded != selector) revert InvalidRuleData(t);
            return;
        }
        if (t == SRPELib.RULE_SENDER_SELECTOR_WORD) {
            (bytes4 embedded,, uint256 paramIndex,) = abi.decode(rule.ruleData, (bytes4, address, uint256, bytes32));
            if (selectorBound && embedded != selector) revert InvalidRuleData(t);
            _validateIndex(paramIndex, t);
            return;
        }
        if (t == SRPELib.RULE_SELECTOR_WORD) {
            (bytes4 embedded, uint256 paramIndex,) = abi.decode(rule.ruleData, (bytes4, uint256, bytes32));
            if (selectorBound && embedded != selector) revert InvalidRuleData(t);
            _validateIndex(paramIndex, t);
            return;
        }
        if (t == SRPELib.RULE_UINT_RANGE) {
            _validateIndex(abi.decode(rule.extraData, (uint256)), t);
            (uint256 min, uint256 max) = abi.decode(rule.ruleData, (uint256, uint256));
            if (min > max) revert InvalidRuleData(t);
            return;
        }
        if (t >= SRPELib.RULE_SPECIFIC_PNL && t <= SRPELib.RULE_SPECIFIC_POSITIONS) {
            (, int256 threshold, uint256 op) = abi.decode(rule.ruleData, (uint64, int256, uint256));
            _validateOp(op, t);
            if (t != SRPELib.RULE_SPECIFIC_PNL && threshold < 0) revert InvalidRuleData(t);
            return;
        }
        if (t == SRPELib.RULE_SPECIFIC_METRIC) {
            (, , uint8 kind, int256 threshold, uint256 op) =
                abi.decode(rule.ruleData, (uint64, uint256, uint8, int256, uint256));
            if (kind > SRPELib.METRIC_INT) revert InvalidRuleData(t);
            if (kind == SRPELib.METRIC_UINT && threshold < 0) revert InvalidRuleData(t);
            _validateOp(op, t);
            return;
        }
        if (t == SRPELib.RULE_PARAM_WORD) {
            (uint256 paramIndex,) = abi.decode(rule.ruleData, (uint256, bytes32));
            _validateIndex(paramIndex, t);
            return;
        }
        if (t == SRPELib.RULE_PARAM_ALLOWLIST || t == SRPELib.RULE_PARAM_DENYLIST) {
            (uint256 paramIndex, address[] memory list) = abi.decode(rule.ruleData, (uint256, address[]));
            _validateIndex(paramIndex, t);
            _validateAddressList(list, t);
            return;
        }
        if (t == SRPELib.RULE_PARAM_UINT_RANGE) {
            (uint256 paramIndex, uint256 min, uint256 max) = abi.decode(rule.ruleData, (uint256, uint256, uint256));
            _validateIndex(paramIndex, t);
            if (min > max) revert InvalidRuleData(t);
            return;
        }
        if (t == SRPELib.RULE_PARAM_UINT_BOUND) {
            (,, uint256 op) = _boundShape(rule.ruleData, t);
            _validateOp(op, t);
            return;
        }
        if (t == SRPELib.RULE_CALL_VALUE) {
            (,, uint256 op) = _callValueShape(rule.ruleData);
            _validateOp(op, t);
            return;
        }
        if (t == SRPELib.RULE_PARAM_ACCOUNT) {
            (uint256 paramIndex, uint8 account) = abi.decode(rule.ruleData, (uint256, uint8));
            _validateIndex(paramIndex, t);
            if (account > SRPELib.ACCOUNT_EXECUTOR) revert InvalidRuleData(t);
            return;
        }
        if (t == SRPELib.RULE_DERIVED) {
            (uint8 metricId,, uint256 op) = abi.decode(rule.ruleData, (uint8, int256, uint256));
            if (metricId > SRPELib.DERIVED_OPEN_POSITIONS) revert InvalidRuleData(t);
            _validateOp(op, t);
            return;
        }
        if (t == SRPELib.RULE_PARAM_PAIR) {
            (uint256 indexA, uint256 indexB,, address[] memory a, address[] memory b) =
                abi.decode(rule.ruleData, (uint256, uint256, bool, address[], address[]));
            _validateIndex(indexA, t);
            _validateIndex(indexB, t);
            if (a.length == 0 || a.length != b.length || a.length > SRPELib.MAX_LIST) revert InvalidRuleData(t);
            return;
        }
        revert UnsupportedRule(t);
    }

    function selectorOf(bytes calldata actionData) internal pure returns (bytes4 selector) {
        if (actionData.length < 4) revert ActionDataTooShort();
        assembly {
            selector := calldataload(actionData.offset)
        }
    }

    /// @notice Reads one static ABI word. Reverts if the call is shorter than that word.
    function readWord(bytes calldata actionData, uint256 paramIndex) internal pure returns (bytes32 word) {
        if (paramIndex > SRPELib.MAX_PARAM_INDEX) revert ParamIndexOutOfRange(paramIndex);
        uint256 offset = 4 + (paramIndex << 5);
        if (actionData.length < offset + 32) revert ActionDataTooShort();
        assembly {
            word := calldataload(add(actionData.offset, offset))
        }
    }

    function compareUint(uint256 observed, uint256 threshold, uint256 op) internal pure returns (bool) {
        if (op == SRPELib.OP_GT) return observed > threshold;
        if (op == SRPELib.OP_LT) return observed < threshold;
        if (op == SRPELib.OP_GE) return observed >= threshold;
        if (op == SRPELib.OP_LE) return observed <= threshold;
        if (op == SRPELib.OP_EQ) return observed == threshold;
        return false;
    }

    function compareInt(int256 observed, int256 threshold, uint256 op) internal pure returns (bool) {
        if (op == SRPELib.OP_GT) return observed > threshold;
        if (op == SRPELib.OP_LT) return observed < threshold;
        if (op == SRPELib.OP_GE) return observed >= threshold;
        if (op == SRPELib.OP_LE) return observed <= threshold;
        if (op == SRPELib.OP_EQ) return observed == threshold;
        return false;
    }

    function listed(address[] memory list, address account, bool allowlist) internal pure returns (bool) {
        uint256 n = list.length;
        if (n == 0 || n > SRPELib.MAX_LIST) return false;
        for (uint256 i = 0; i < n;) {
            if (list[i] == account) return allowlist;
            unchecked {
                ++i;
            }
        }
        return !allowlist;
    }

    function inRange(uint256 min, uint256 max, uint256 value) internal pure returns (bool) {
        return min <= max && value >= min && value <= max;
    }

    function matchesPair(bytes calldata actionData, bytes memory ruleData) internal pure returns (bool) {
        (uint256 indexA, uint256 indexB, bool unordered, address[] memory a, address[] memory b) =
            abi.decode(ruleData, (uint256, uint256, bool, address[], address[]));
        uint256 n = a.length;
        if (n == 0 || n != b.length || n > SRPELib.MAX_LIST) return false;
        address left = address(uint160(uint256(readWord(actionData, indexA))));
        address right = address(uint160(uint256(readWord(actionData, indexB))));
        for (uint256 i = 0; i < n;) {
            if (left == a[i] && right == b[i]) return true;
            if (unordered && left == b[i] && right == a[i]) return true;
            unchecked {
                ++i;
            }
        }
        return false;
    }

    function asInt(uint256 raw) internal pure returns (int256 value) {
        assembly {
            value := raw
        }
    }

    function _supported(uint16 t) private pure returns (bool) {
        if (t <= SRPELib.RULE_MAX_CONSECUTIVE_LOSSES) return true;
        return t >= SRPELib.RULE_SPECIFIC_PNL && t <= SRPELib.RULE_PARAM_PAIR;
    }

    /// @dev Global rules run for every selector, so they cannot name a parameter index or a selector.
    function _globalSafe(uint16 t) private pure returns (bool) {
        if (t <= SRPELib.RULE_COOLDOWN || t == SRPELib.RULE_NONE_LEGACY) return true;
        if (t >= SRPELib.RULE_CAPITAL_IN && t <= SRPELib.RULE_MAX_CONSECUTIVE_LOSSES) return true;
        if (t >= SRPELib.RULE_SPECIFIC_PNL && t <= SRPELib.RULE_SPECIFIC_METRIC) return true;
        return t == SRPELib.RULE_CALL_VALUE || t == SRPELib.RULE_DERIVED;
    }

    function _validateAddressList(address[] memory list, uint16 t) private pure {
        if (list.length == 0 || list.length > SRPELib.MAX_LIST) revert InvalidRuleData(t);
    }

    function _validateIndex(uint256 paramIndex, uint16 t) private pure {
        if (paramIndex > SRPELib.MAX_PARAM_INDEX) revert InvalidRuleData(t);
    }

    function _validateOp(uint256 op, uint16 t) private pure {
        if (op > SRPELib.OP_EQ) revert InvalidRuleData(t);
    }

    function _secondWord(bytes memory data, uint16 t) private pure returns (uint256 op) {
        if (data.length != 64) revert InvalidRuleData(t);
        (, op) = abi.decode(data, (uint256, uint256));
    }

    function _boundShape(bytes memory data, uint16 t) private pure returns (uint256, uint256, uint256) {
        if (data.length != 96) revert InvalidRuleData(t);
        (uint256 paramIndex, uint256 threshold, uint256 op) = abi.decode(data, (uint256, uint256, uint256));
        _validateIndex(paramIndex, t);
        return (paramIndex, threshold, op);
    }

    function _callValueShape(bytes memory data) private pure returns (uint256, uint256, uint256) {
        if (data.length != 64) revert InvalidRuleData(SRPELib.RULE_CALL_VALUE);
        (uint256 threshold, uint256 op) = abi.decode(data, (uint256, uint256));
        return (0, threshold, op);
    }
}
