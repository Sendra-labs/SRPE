// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SRPELib} from "../../libs/SRPE/SRPE.lib.sol";
import {UniversalRuler} from "../UniversalRuler.sol";
import {ISendraAddressProvider} from "../../interfaces/isendra/ISendraAddressProvider.sol";
import {RPFPStorage} from "../storage/RPFPStorage.sol";

contract UniversalExecutor {

    ISendraAddressProvider public immutable addressProvider;

    constructor(address _addressProvider) {
        addressProvider = ISendraAddressProvider(_addressProvider);
    }

    function execute(SRPELib.ExecutionParams memory _executionParams) public payable returns (bytes memory) {
        SRPELib.RPFPForRead memory rpfp = RPFPStorage(addressProvider.getAddress("RPFPStorage")).readRPFPById(_executionParams.rpfpId);
        address target = rpfp.implementation;
        // check rules
        UniversalRuler(addressProvider.getAddress("UniversalRuler")).checkExecution(_executionParams.actionData, msg.sender, _executionParams.rpfpId);

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