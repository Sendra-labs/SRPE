// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SRPELib} from "../libs/SRPE/SRPE.lib.sol";
import {ISendraStorage} from "../interfaces/isendra/ISendraStorage.sol";
import {RPFPStorage} from "./storage/RPFPStorage.sol";
import {SendraLib} from "../libs/core/Sendra.lib.sol";

contract UniversalRuler {

    function getFunctionsRules(uint256 _rpfpId, bytes4 _functionSelector) internal view returns(SRPELib.Rules memory) {
        SRPELib.Rules memory rules = RPFPStorage.getFunctionRules(_rpfpId, _functionSelector);
        return rules;
    }

    function checkExecution(address _executor, bytes memory _actionData, address _sender, uint256 _rpfpId) public view returns (bool) {
        
        bytes4 functionSelector = bytes4(_actionData[0:4]);
        SRPELib.Rules memory rules = getFunctionsRules(_rpfpId, functionSelector);
        SendraLib.GlobalAccumulators memory gAccumulators;
        bool isGlobalAccumulatorsInitialized = false;
        for (uint256 i = 0; i < rules.ruleCount; i++) {
            if(
                !isGlobalAccumulatorsInitialized &&
                (rules.rules[i].ruleType == 10
                || rules.rules[i].ruleType == 11
                || rules.rules[i].ruleType == 12
                || rules.rules[i].ruleType == 13
                || rules.rules[i].ruleType == 14
                || rules.rules[i].ruleType == 15
                || rules.rules[i].ruleType == 16
                || rules.rules[i].ruleType == 17
                || rules.rules[i].ruleType == 18
                || rules.rules[i].ruleType == 19
                || rules.rules[i].ruleType == 20)
            ) {
                ISendraStorage sendraStorage = ISendraStorage(0x0000000000000000000000000000000000000000);
                gAccumulators = sendraStorage.getUserGlobalAccumulators(_sender);
                isGlobalAccumulatorsInitialized = true;
            }
            if (rules.rules[i].ruleType == 0) {
                // no rule
            } else if (rules.rules[i].ruleType == 1) {
                // whitelist
                if(!checkAddressList(rules.rules[i].ruleData, true, _sender)) revert InvalidAction(i, functionSelector);
            } else if (rules.rules[i].ruleType == 2) {
                // blacklist
                if(!checkAddressList(rules.rules[i].ruleData, false, _sender)) revert InvalidAction(i, functionSelector);
            } else if (rules.rules[i].ruleType == 3) {
                // timeLimit checkUint()
                if(!checkUint(rules.rules[i].ruleData, block.timestamp)) revert InvalidAction(i, functionSelector);
            } else if (rules.rules[i].ruleType == 4) {
                // frequencyLimit
                // create system to deploy a executor storage contract to store data
            } else if (rules.rules[i].ruleType == 5) {
                // allow specific sender to call a specific function
                if(!checkSenderAndFunc(
                    rules.rules[i].ruleData,
                    _actionData,
                    _sender
                )) revert InvalidAction(i, functionSelector);
            } else if (rules.rules[i].ruleType == 6) {
                // allow specific sender, function and input_value + inputIndex
                if(!checkSenderAndFuncAndInput(
                    rules.rules[i].ruleData,
                    _actionData,
                    _sender
                )) revert InvalidAction(i, functionSelector);

            } else if (rules.rules[i].ruleType == 7) {

            } else if (rules.rules[i].ruleType == 8) {
                // usdc amounts limits
                uint256 paramIndex = abi.decode(rules.rules[i].extraData, (uint256));
                uint256 offset = 4 + 32 * paramIndex;
                require(_actionData.length >= offset + 32, "actionData too short");
                uint256 usdcValue;
                assembly {
                    usdcValue := mload(add(add(_actionData, 0x20), offset))
                }
                if(!checkUintRange(rules.rules[i].ruleData, usdcValue)) revert InvalidAction(i, functionSelector);
            } else if (rules.rules[i].ruleType == 9) {

            } else if (rules.rules[i].ruleType == 10) {
                // totalCapitalIn
                if(!checkUint(rules.rules[i].ruleData, gAccumulators.totalCapitalIn)) revert InvalidAction(i, functionSelector);
            } else if (rules.rules[i].ruleType == 11) {
                // totalCapitalOut
                if(!checkUint(rules.rules[i].ruleData, gAccumulators.totalCapitalOut)) revert InvalidAction(i, functionSelector);
            } else if (rules.rules[i].ruleType == 12) {

            } else if (rules.rules[i].ruleType == 13) {

            } else if (rules.rules[i].ruleType == 14) {

            } else if (rules.rules[i].ruleType == 15) {

            } else if (rules.rules[i].ruleType == 16) {
                
            } else if (rules.rules[i].ruleType == 17) {

            } else if (rules.rules[i].ruleType == 18) {

            } else if (rules.rules[i].ruleType == 19) {

            } else if (rules.rules[i].ruleType == 20) {
                
            }
        }

        return true;
    }

    error InvalidAction(uint256 ruleIndex, bytes4 functionSelector);

    function checkSenderAndFunc(bytes memory ruleData, bytes memory actionData, address sender)public pure returns (bool){
        (bytes4 allowedSelector, address allowedSender) = abi.decode(ruleData, (bytes4, address));
        bytes4 sel = bytes4(actionData[0:4]);
        return (sel == allowedSelector && sender == allowedSender);
    }

    function checkSenderAndFuncAndInput(bytes memory ruleData, bytes memory actionData, address sender)public pure returns (bool){
        (
            bytes4 allowedSelector, 
            address allowedSender, 
            uint256 paramIndex, 
            bytes32 expectedValue
        ) 
        = abi.decode(ruleData, (bytes4, address, uint256, bytes32));
        
        bytes4 sel = bytes4(actionData[0:4]);
        
        uint256 offset = 4 + 32 * paramIndex;

        require(actionData.length >= offset + 32, "actionData too short");
       
        bytes32 paramValue;
       
        assembly {
            paramValue := mload(add(add(actionData, 0x20), offset))
        }

        if(sel == allowedSelector && sender == allowedSender ) {
            return paramValue == expectedValue;
        } else {
            return false;
        }
    }



    function checkAddressList(bytes memory _ruleData, bool _isWhitelist, address _sender) public pure returns (bool) {
        address[] memory addresses = abi.decode(_ruleData, (address[]));
        bool found = false;
        for (uint256 i = 0; i < addresses.length; i++) {
            if (addresses[i] == _sender) {
                found = true;
                break;
            }
        }
        return _isWhitelist ? found : !found;
    }

    function checkUint(bytes memory _ruleData, uint256 _value) public view returns (bool) {
        uint256[] memory values = abi.decode(_ruleData, (uint256[2]));
        uint256 _type = values[1];
        if (_type == 0) { // means rule value must be less than the value
            return values[0] < _value;
        } else if (_type == 1) { // means rule value must be greater than the value
            return values[0] > _value;
        } else {
            return false;
        }
    }

    function checkUintRange(bytes memory _ruleData, uint256 _value) public view returns (bool) {
        uint256[] memory range = abi.decode(_ruleData, (uint256[2]));
        return range[0] < _value && _value < range[1];
    }

}