// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SRPELib} from "../../libs/SRPE/SRPE.lib.sol";

contract UniversalExecutor {

    function execute(SRPELib.ExecutionParams memory _executionParams) public payable returns (bytes memory) {
        SRPELib.RPFP memory rpfp = RPFPStorage.getRPFPById(_executionParams.rpfpId);
        address target = rpfp.implementation;
        // check rules
        if (!checkExecution(target, _executionParams.actionData, msg.sender, _executionParams.rpfpId)) revert InvalidAction();

        (bool success, bytes memory result) = target.delegatecall(_executionParams.actionData);
        
        if (!success) {
            assembly {
                revert(add(result, 0x20), mload(result))
            }
        }

        return result;
    }

    error InvalidAction();

}