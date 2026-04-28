// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

abstract contract RulesHelper {

    function checkSenderAndFunc(bytes memory ruleData, bytes memory actionData, address sender) internal pure returns (bool){
        (bytes4 allowedSelector, address allowedSender) = abi.decode(ruleData, (bytes4, address));
        bytes4 sel = _getSelector(actionData);
        return (sel == allowedSelector && sender == allowedSender);
    }

    function checkSenderAndFuncAndInput(bytes memory ruleData, bytes memory actionData, address sender) internal pure returns (bool){
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

    function checkFuncAndInput(bytes memory ruleData, bytes memory actionData) internal pure returns (bool){
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

    function checkAddressList(bytes memory _ruleData, bool _isWhitelist, address _sender) internal pure returns (bool) {
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

    function checkUint(bytes memory _ruleData, uint256 _value) internal pure returns (bool) {
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

    function checkUintRange(bytes memory _ruleData, uint256 _value) internal pure returns (bool) {
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