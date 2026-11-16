// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SRPELib} from "../../libs/SRPE/SRPE.lib.sol";
import {ISendraAddressProvider} from "../../interfaces/isendra/ISendraAddressProvider.sol";
import {ISendraRoles} from "../../interfaces/isendra/ISendraRoles.sol";
import {RulesHelper} from "../RulesHelper.sol";

/// @title RPFPStorage
/// @notice Stores enclave configuration. Function rules can be written only by the registered
///         deployer and only until `lockRules`. Global rules are written once, inside `createRPFP`.
contract RPFPStorage is RulesHelper {
    ISendraAddressProvider public immutable addressProvider;

    constructor(address _addressProvider) {
        addressProvider = ISendraAddressProvider(_addressProvider);
    }

    /// @dev The deployer must also be a protocol contract, so a provider key alone is not enough.
    modifier onlyDeployer() {
        if (!ISendraRoles(addressProvider.getAddress("Roles")).isProtocolContract(msg.sender)) {
            revert SenderNotAllowed();
        }
        if (msg.sender != addressProvider.getAddress("RPFPDeployer")) revert SenderNotAllowed();
        _;
    }

    uint256 public nextRPFPId;

    mapping(uint256 => SRPELib.RPFP) internal rpfps;
    mapping(uint256 => bool) public rulesLocked;

    function createRPFP(
        uint16 _type,
        address executor,
        address implementation,
        address ruler,
        address[] calldata owners,
        address creator, // caller of RPFPDeployer.deployRPFP; metadata only
        string calldata description,
        bytes calldata extraData,
        SRPELib.Rules calldata rules,
        SRPELib.Instructions calldata instructions
    ) public onlyDeployer returns (uint256) {
        _validateSet(bytes4(0), rules, false, true);

        uint256 id = nextRPFPId;
        SRPELib.RPFP storage r = rpfps[id];
        r._type = _type;
        r.id = id;
        r.executor = executor;
        r.implementation = implementation;
        r.ruler = ruler;
        r.owners = owners;
        r.creator = creator;
        r.description = description;
        r.extraData = extraData;
        r.createdAt = block.timestamp;
        r.rules = rules;
        r.instructions = instructions;

        nextRPFPId = id + 1;
        emit RPFPCreated(id, executor, implementation, ruler, creator);
        return id;
    }

    function readRPFPById(uint256 _id) public view returns (SRPELib.RPFPForRead memory) {
        SRPELib.RPFP storage rpfp = rpfps[_id];
        return SRPELib.RPFPForRead({
            _type: rpfp._type,
            id: rpfp.id,
            executor: rpfp.executor,
            implementation: rpfp.implementation,
            ruler: rpfp.ruler,
            owners: rpfp.owners,
            creator: rpfp.creator,
            description: rpfp.description,
            extraData: rpfp.extraData,
            createdAt: rpfp.createdAt
        });
    }

    /// @notice Executor and implementation only. Avoids copying owners, description, and extra data.
    function getExecutionTarget(uint256 _id) public view returns (address executor, address implementation) {
        SRPELib.RPFP storage rpfp = rpfps[_id];
        return (rpfp.executor, rpfp.implementation);
    }

    /// @notice Policy loaded by the ruler in one call: bound executor, global rules, selector rules.
    function getEnforcedRules(uint256 _id, bytes4 _functionSelector)
        public
        view
        returns (address executor, SRPELib.Rules memory globalRules, SRPELib.Rules memory functionRules)
    {
        SRPELib.RPFP storage rpfp = rpfps[_id];
        return (rpfp.executor, rpfp.rules, rpfp.functionRules[_functionSelector]);
    }

    function getFunctionRules(uint256 _id, bytes4 _functionSelector) public view returns (SRPELib.Rules memory) {
        return rpfps[_id].functionRules[_functionSelector];
    }

    function setFunctionRules(uint256 _id, bytes4 _functionSelector, SRPELib.Rules calldata _rules) public onlyDeployer {
        if (rulesLocked[_id]) revert RulesLocked(_id);
        if (rpfps[_id].executor == address(0)) revert UnknownEnclave(_id);
        _validateSet(_functionSelector, _rules, true, false);
        rpfps[_id].functionRules[_functionSelector] = _rules;
    }

    /// @notice Freezes function-rule writes for an enclave. Idempotent.
    function lockRules(uint256 _id) public onlyDeployer {
        if (rpfps[_id].executor == address(0)) revert UnknownEnclave(_id);
        rulesLocked[_id] = true;
        emit RulesFrozen(_id);
    }

    function getRulesByRPFPId(uint256 _id) public view returns (SRPELib.Rules memory) {
        return rpfps[_id].rules;
    }

    function getInstructionsByRPFPId(uint256 _id) public view returns (SRPELib.Instructions memory) {
        return rpfps[_id].instructions;
    }

    function _validateSet(bytes4 selector, SRPELib.Rules calldata rules, bool selectorBound, bool allowEmpty)
        internal
        pure
    {
        uint256 n = rules.rules.length;
        if (rules.ruleCount != n) revert RuleCountMismatch(rules.ruleCount, n);
        if (n > SRPELib.MAX_RULES || (!allowEmpty && n == 0)) revert InvalidRules(n, SRPELib.MAX_RULES);
        for (uint256 i = 0; i < n;) {
            _validateRule(selector, rules.rules[i], selectorBound);
            unchecked {
                ++i;
            }
        }
    }

    event RPFPCreated(
        uint256 indexed id, address indexed executor, address indexed implementation, address ruler, address creator
    );
    event RulesFrozen(uint256 indexed id);

    error SenderNotAllowed();
    error RulesLocked(uint256 id);
    error UnknownEnclave(uint256 id);
}
