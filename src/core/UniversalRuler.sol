// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SRPELib} from "../libs/SRPE/SRPE.lib.sol";
import {ISendraStorage} from "../interfaces/isendra/ISendraStorage.sol";
import {RPFPStorage} from "./storage/RPFPStorage.sol";
import {SendraLib} from "../libs/core/Sendra.lib.sol";
import {ISendraAddressProvider} from "../interfaces/isendra/ISendraAddressProvider.sol";

contract UniversalRuler {

    ISendraAddressProvider public immutable addressProvider;

    constructor(address _addressProvider) {
        addressProvider = ISendraAddressProvider(_addressProvider);
    }

    function getFunctionsRules(uint256 _rpfpId, bytes4 _functionSelector) internal view returns(SRPELib.Rules memory) {
        SRPELib.Rules memory rules = RPFPStorage(addressProvider.getAddress("RPFPStorage")).getFunctionRules(_rpfpId, _functionSelector);
        return rules;
    }

    function checkExecution(bytes memory _actionData, address _sender, uint256 _rpfpId) public view {
        bytes4 functionSelector = _getSelector(_actionData);
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
                ISendraStorage sendraStorage = ISendraStorage(addressProvider.getAddress("SendraStorage"));
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
                // allow specific function and input_value + inputIndex

                if(!checkFuncAndInput(
                    rules.rules[i].ruleData,
                    _actionData
                )) revert InvalidAction(i, functionSelector);

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
                // empty rule

            } else if (rules.rules[i].ruleType == 10) {
                // totalCapitalIn
                if(!checkUint(rules.rules[i].ruleData, gAccumulators.totalCapitalIn)) revert InvalidAction(i, functionSelector);
            } else if (rules.rules[i].ruleType == 11) {
                // totalCapitalOut
                if(!checkUint(rules.rules[i].ruleData, gAccumulators.totalCapitalOut)) revert InvalidAction(i, functionSelector);
            } else if (rules.rules[i].ruleType == 12) {
                // peakSimultaneousExposure
                if(!checkUint(rules.rules[i].ruleData, gAccumulators.peakSimultaneousExposure)) revert InvalidAction(i, functionSelector);

            } else if (rules.rules[i].ruleType == 13) {
                // currentExposure
                if(!checkUint(rules.rules[i].ruleData, gAccumulators.currentExposure)) revert InvalidAction(i, functionSelector);
            } else if (rules.rules[i].ruleType == 14) {
                // cumulativeRealizedPnl
                if(!checkUint(rules.rules[i].ruleData, gAccumulators.cumulativeRealizedPnl)) revert InvalidAction(i, functionSelector);
            } else if (rules.rules[i].ruleType == 15) {
                // grossProfit
                if(!checkUint(rules.rules[i].ruleData, gAccumulators.grossProfit)) revert InvalidAction(i, functionSelector);
            } else if (rules.rules[i].ruleType == 16) {
                // grossLoss
                if(!checkUint(rules.rules[i].ruleData, gAccumulators.grossLoss)) revert InvalidAction(i, functionSelector);
            } else if (rules.rules[i].ruleType == 17) {
                // highWaterMark
                if(!checkUint(rules.rules[i].ruleData, gAccumulators.highWaterMark)) revert InvalidAction(i, functionSelector);
            } else if (rules.rules[i].ruleType == 18) {
                // maxDrawdown
                if(!checkUint(rules.rules[i].ruleData, gAccumulators.maxDrawdown)) revert InvalidAction(i, functionSelector);
            } else if (rules.rules[i].ruleType == 19) {
                // totalPositionsOpened
                if(!checkUint(rules.rules[i].ruleData, gAccumulators.totalPositionsOpened)) revert InvalidAction(i, functionSelector);
            } else if (rules.rules[i].ruleType == 20) {
                // totalPositionsClosed
                if(!checkUint(rules.rules[i].ruleData, gAccumulators.totalPositionsClosed)) revert InvalidAction(i, functionSelector);
            } else if (rules.rules[i].ruleType == 21) {
                // winCount
                if(!checkUint(rules.rules[i].ruleData, gAccumulators.winCount)) revert InvalidAction(i, functionSelector);
            } else if (rules.rules[i].ruleType == 22) {
                // lossCount
                if(!checkUint(rules.rules[i].ruleData, gAccumulators.lossCount)) revert InvalidAction(i, functionSelector);
            } else if (rules.rules[i].ruleType == 23) {
                // totalDurationSeconds
                if(!checkUint(rules.rules[i].ruleData, gAccumulators.totalDurationSeconds)) revert InvalidAction(i, functionSelector);
            } else if (rules.rules[i].ruleType == 24) {
                // firstActivityTimestamp
                if(!checkUint(rules.rules[i].ruleData, gAccumulators.firstActivityTimestamp)) revert InvalidAction(i, functionSelector);
            } else if (rules.rules[i].ruleType == 25) {
                // lastActivityTimestamp
                if(!checkUint(rules.rules[i].ruleData, gAccumulators.lastActivityTimestamp)) revert InvalidAction(i, functionSelector);
            } else if (rules.rules[i].ruleType == 26) {
                // liquidationEvents
                if(!checkUint(rules.rules[i].ruleData, gAccumulators.liquidationEvents)) revert InvalidAction(i, functionSelector);
            } else if (rules.rules[i].ruleType == 27) {
                // consecutiveLosses
                if(!checkUint(rules.rules[i].ruleData, gAccumulators.consecutiveLosses)) revert InvalidAction(i, functionSelector);
            } else if (rules.rules[i].ruleType == 28) {
                // maxConsecutiveLosses
            }
        }
    }

    error InvalidAction(uint256 ruleIndex, bytes4 functionSelector);

    function checkSenderAndFunc(bytes memory ruleData, bytes memory actionData, address sender)public pure returns (bool){
        (bytes4 allowedSelector, address allowedSender) = abi.decode(ruleData, (bytes4, address));
        bytes4 sel = _getSelector(actionData);
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
        
        bytes4 sel = _getSelector(actionData);
        
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

    function checkFuncAndInput(bytes memory ruleData, bytes memory actionData) public pure returns (bool){
        (bytes4 allowedSelector, uint256 paramIndex, bytes32 expectedValue) = abi.decode(ruleData, (bytes4, uint256, bytes32));
        bytes4 sel = _getSelector(actionData);

        uint256 offset = 4 + 32 * paramIndex;

        require(actionData.length >= offset + 32, "actionData too short");

        bytes32 paramValue;

        assembly {
            paramValue := mload(add(add(actionData, 0x20), offset))
        }

        return (sel == allowedSelector && paramValue == expectedValue);
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

    function checkUint(bytes memory _ruleData, uint256 _value) public pure returns (bool) {
        uint256[2] memory values = abi.decode(_ruleData, (uint256[2]));
        uint256 _type = values[1];
        if (_type == 0) { // means rule value must be less than the value
            return values[0] < _value;
        } else if (_type == 1) { // means rule value must be greater than the value
            return values[0] > _value;
        } else {
            return false;
        }
    }

    function checkUintRange(bytes memory _ruleData, uint256 _value) public pure returns (bool) {
        uint256[2] memory range = abi.decode(_ruleData, (uint256[2]));
        return range[0] < _value && _value < range[1];
    }

    function _getSelector(bytes memory _actionData) internal pure returns (bytes4 sel) {
        require(_actionData.length >= 4, "actionData too short");
        assembly {
            sel := shr(224, mload(add(_actionData, 0x20)))
        }
    }

}