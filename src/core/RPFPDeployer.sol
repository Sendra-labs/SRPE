//SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UniversalExecutorFactory} from "./UniversalExecutorFactory.sol";
import {SRPELib} from "../libs/SRPE/SRPE.lib.sol";
import {RPFPStorage} from "./storage/RPFPStorage.sol";

contract RPFPDeployer {

    uint256 public constant MAX_RULES = 12;

    function deployRPFP(SRPELib.NewRPFPInputs memory _newRPFPInputs) public {
        address executor = UniversalExecutorFactory.deploySendraExecutor(_newRPFPInputs.implementation);
        _newRPFPInputs.rules.ruleCount = _newRPFPInputs.rules.rules.length;

        if(_newRPFPInputs.rules.ruleCount == 0 || _newRPFPInputs.rules.ruleCount > MAX_RULES) 
        revert InvalidRules(_newRPFPInputs.rules.ruleCount, MAX_RULES);

        if (_newRPFPInputs.functionSelectors.length != _newRPFPInputs.functionSelectorRules.length) {
            revert FunctionRulesLengthMismatch(_newRPFPInputs.functionSelectors.length, _newRPFPInputs.functionSelectorRules.length);
        }
        
        uint256 rpfpId = RPFPStorage.createRPFP(
            _newRPFPInputs._type,
            executor,
            _newRPFPInputs.implementation,
            _newRPFPInputs.ruler,
            _newRPFPInputs.owners,
            _newRPFPInputs.description,
            _newRPFPInputs.extraData,
            _newRPFPInputs.rules,
            _newRPFPInputs.instructions
        );

        // Store per-function rules blobs (selector => Rules)
        for (uint256 i = 0; i < _newRPFPInputs.functionSelectors.length; i++) {
            SRPELib.Rules memory fr = _newRPFPInputs.functionSelectorRules[i];
            fr.ruleCount = fr.rules.length;
            if (fr.ruleCount == 0 || fr.ruleCount > MAX_RULES) {
                revert InvalidRules(fr.ruleCount, MAX_RULES);
            }
            RPFPStorage.setFunctionRules(rpfpId, _newRPFPInputs.functionSelectors[i], fr);
        }

        emit RPFPDeployed(executor, rpfpId);
    }

    event RPFPDeployed(address indexed executor, uint256 indexed rpfpId);

    error InvalidRules(uint256 ruleCount, uint256 maxRules);
    error FunctionRulesLengthMismatch(uint256 selectorsLength, uint256 rulesLength);

}