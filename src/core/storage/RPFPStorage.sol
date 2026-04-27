// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SRPELib} from "../../libs/SRPE/SRPE.lib.sol";

contract RPFPStorage {

    modifier onlyProtocol() {
        //
        _;
    }

    uint256 public nextRPFPId;

    
    mapping(uint256 => SRPELib.RPFP) internal rpfps;

    function createRPFP(
        uint16 _type,
        address executor,
        address implementation,
        address ruler,
        address[] calldata owners,
        string calldata description,
        bytes calldata extraData,
        SRPELib.Rules calldata rules,
        SRPELib.Instructions calldata instructions
    ) public onlyProtocol returns (uint256) {
        uint256 id = nextRPFPId;
        SRPELib.RPFP storage r = rpfps[id];

        r._type = _type;
        r.id = id;
        r.executor = executor;
        r.implementation = implementation;
        r.ruler = ruler;
        r.owners = owners;
        r.description = description;
        r.extraData = extraData;
        r.createdAt = block.timestamp;
        r.rules = rules;
        r.instructions = instructions;

        nextRPFPId++;
        emit RPFPCreated(id, executor, implementation, ruler);
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
            description: rpfp.description,
            extraData: rpfp.extraData,
            createdAt: rpfp.createdAt
        });
    }

    function getFunctionRules(uint256 _id, bytes4 _functionSelector) public view returns (SRPELib.Rules memory) {
        return rpfps[_id].functionRules[_functionSelector];
    }

    function setFunctionRules(uint256 _id, bytes4 _functionSelector, SRPELib.Rules calldata _rules) public onlyProtocol {
        rpfps[_id].functionRules[_functionSelector] = _rules;
    }

    function getRulesByRPFPId(uint256 _id) public view returns (SRPELib.Rules memory) {
        return rpfps[_id].rules;
    }

    function getInstructionsByRPFPId(uint256 _id) public view returns (SRPELib.Instructions memory) {
        return rpfps[_id].instructions;
    }

    event RPFPCreated(uint256 indexed id, address indexed executor, address indexed implementation, address ruler);

}