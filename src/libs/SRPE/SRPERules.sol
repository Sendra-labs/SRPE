// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SRPELib} from "./SRPE.lib.sol";

/// @title SRPERules
/// @notice Off-chain and on-chain helpers to encode rule payloads. Anyone deploying an RPFP
///         can use these instead of hand-rolling `abi.encode`.
library SRPERules {
    function pack(SRPELib.Rule[] memory rules) internal pure returns (SRPELib.Rules memory packed) {
        packed.rules = rules;
        packed.ruleCount = rules.length;
    }

    function none() internal pure returns (SRPELib.Rule memory rule) {
        rule.ruleType = SRPELib.RULE_NONE;
    }

    function senderAllowlist(address[] memory allowed) internal pure returns (SRPELib.Rule memory rule) {
        rule.ruleType = SRPELib.RULE_SENDER_ALLOWLIST;
        rule.ruleData = abi.encode(allowed);
    }

    function senderDenylist(address[] memory denied) internal pure returns (SRPELib.Rule memory rule) {
        rule.ruleType = SRPELib.RULE_SENDER_DENYLIST;
        rule.ruleData = abi.encode(denied);
    }

    function timestamp(uint256 threshold, uint256 op) internal pure returns (SRPELib.Rule memory rule) {
        rule.ruleType = SRPELib.RULE_TIMESTAMP;
        rule.ruleData = abi.encode(threshold, op);
    }

    function cooldown(uint256 minInterval) internal pure returns (SRPELib.Rule memory rule) {
        rule.ruleType = SRPELib.RULE_COOLDOWN;
        rule.ruleData = abi.encode(minInterval);
    }

    function paramWord(uint256 index, bytes32 expected) internal pure returns (SRPELib.Rule memory rule) {
        rule.ruleType = SRPELib.RULE_PARAM_WORD;
        rule.ruleData = abi.encode(index, expected);
    }

    function paramAddress(uint256 index, address expected) internal pure returns (SRPELib.Rule memory rule) {
        return paramWord(index, bytes32(uint256(uint160(expected))));
    }

    function paramAllowlist(uint256 index, address[] memory allowed) internal pure returns (SRPELib.Rule memory rule) {
        rule.ruleType = SRPELib.RULE_PARAM_ALLOWLIST;
        rule.ruleData = abi.encode(index, allowed);
    }

    function paramDenylist(uint256 index, address[] memory denied) internal pure returns (SRPELib.Rule memory rule) {
        rule.ruleType = SRPELib.RULE_PARAM_DENYLIST;
        rule.ruleData = abi.encode(index, denied);
    }

    function paramUintRange(uint256 index, uint256 min, uint256 max) internal pure returns (SRPELib.Rule memory rule) {
        rule.ruleType = SRPELib.RULE_PARAM_UINT_RANGE;
        rule.ruleData = abi.encode(index, min, max);
    }

    function paramUintBound(uint256 index, uint256 threshold, uint256 op)
        internal
        pure
        returns (SRPELib.Rule memory rule)
    {
        rule.ruleType = SRPELib.RULE_PARAM_UINT_BOUND;
        rule.ruleData = abi.encode(index, threshold, op);
    }

    /// @param account 0 = `msg.sender`, 1 = the enclave executor.
    function paramAccount(uint256 index, uint8 account) internal pure returns (SRPELib.Rule memory rule) {
        rule.ruleType = SRPELib.RULE_PARAM_ACCOUNT;
        rule.ruleData = abi.encode(index, account);
    }

    function paramPair(uint256 indexA, uint256 indexB, bool unordered, address[] memory a, address[] memory b)
        internal
        pure
        returns (SRPELib.Rule memory rule)
    {
        rule.ruleType = SRPELib.RULE_PARAM_PAIR;
        rule.ruleData = abi.encode(indexA, indexB, unordered, a, b);
    }

    function callValue(uint256 threshold, uint256 op) internal pure returns (SRPELib.Rule memory rule) {
        rule.ruleType = SRPELib.RULE_CALL_VALUE;
        rule.ruleData = abi.encode(threshold, op);
    }

    function globalUint(uint16 ruleType, uint256 threshold, uint256 op)
        internal
        pure
        returns (SRPELib.Rule memory rule)
    {
        rule.ruleType = ruleType;
        rule.ruleData = abi.encode(threshold, op);
    }

    function globalInt(uint16 ruleType, int256 threshold, uint256 op) internal pure returns (SRPELib.Rule memory rule) {
        rule.ruleType = ruleType;
        rule.ruleData = abi.encode(threshold, op);
    }

    function specific(uint16 ruleType, uint64 key, int256 threshold, uint256 op)
        internal
        pure
        returns (SRPELib.Rule memory rule)
    {
        rule.ruleType = ruleType;
        rule.ruleData = abi.encode(key, threshold, op);
    }

    function specificMetric(uint64 key, uint256 metricIndex, uint8 kind, int256 threshold, uint256 op)
        internal
        pure
        returns (SRPELib.Rule memory rule)
    {
        rule.ruleType = SRPELib.RULE_SPECIFIC_METRIC;
        rule.ruleData = abi.encode(key, metricIndex, kind, threshold, op);
    }

    function derived(uint8 metricId, int256 threshold, uint256 op) internal pure returns (SRPELib.Rule memory rule) {
        rule.ruleType = SRPELib.RULE_DERIVED;
        rule.ruleData = abi.encode(metricId, threshold, op);
    }

    /// @notice Minimal payload: one selector, one no-op. The action is public. Anyone may call it.
    function publicAction(address implementation, bytes4 selector, string memory description)
        internal
        pure
        returns (SRPELib.NewRPFPInputs memory inputs)
    {
        inputs.implementation = implementation;
        inputs.description = description;
        inputs.owners = new address[](0);
        inputs.functionSelectors = new bytes4[](1);
        inputs.functionSelectors[0] = selector;
        inputs.functionSelectorRules = new SRPELib.Rules[](1);
        inputs.functionSelectorRules[0] = pack(_one(none()));
        inputs.instructions = SRPELib.Instructions({instructions: new SRPELib.Instruction[](0)});
    }

    function _one(SRPELib.Rule memory rule) private pure returns (SRPELib.Rule[] memory rules) {
        rules = new SRPELib.Rule[](1);
        rules[0] = rule;
    }
}
