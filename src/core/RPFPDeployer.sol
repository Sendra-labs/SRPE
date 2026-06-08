//SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UniversalExecutorFactory} from "./UniversalExecutorFactory.sol";
import {SRPELib} from "../libs/SRPE/SRPE.lib.sol";
import {RPFPStorage} from "./storage/RPFPStorage.sol";
import {ISendraAddressProvider} from "../interfaces/isendra/ISendraAddressProvider.sol";

contract RPFPDeployer {

    ISendraAddressProvider public immutable addressProvider;

    constructor(address _addressProvider) {
        addressProvider = ISendraAddressProvider(_addressProvider);
    }

    uint256 public constant MAX_RULES = 12;
    uint256 public constant MAX_FUNCTION_SELECTORS = 12;

    function deployRPFP(SRPELib.NewRPFPInputs memory _newRPFPInputs) public returns (address, uint256) {
        // Deploy an executor instance wired to the AddressProvider.
        address executor = UniversalExecutorFactory(addressProvider.getAddress("UniversalExecutorFactory"))
            .deploySendraExecutor(address(addressProvider));
        _newRPFPInputs.rules.ruleCount = _newRPFPInputs.rules.rules.length;

        if(_newRPFPInputs.functionSelectors.length == 0 || _newRPFPInputs.functionSelectors.length > MAX_FUNCTION_SELECTORS) 
        revert InvalidFunctionSelectors(_newRPFPInputs.functionSelectors.length, MAX_FUNCTION_SELECTORS);

        if (_newRPFPInputs.functionSelectors.length != _newRPFPInputs.functionSelectorRules.length) {
            revert FunctionRulesLengthMismatch(_newRPFPInputs.functionSelectors.length, _newRPFPInputs.functionSelectorRules.length);
        }
        
        uint256 rpfpId = RPFPStorage(addressProvider.getAddress("RPFPStorage")).createRPFP(
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
            RPFPStorage(addressProvider.getAddress("RPFPStorage")).setFunctionRules(rpfpId, _newRPFPInputs.functionSelectors[i], fr);
        }

        emit RPFPDeployed(executor, rpfpId);
        return (executor, rpfpId);
    }

    event RPFPDeployed(address indexed executor, uint256 indexed rpfpId);

    error InvalidRules(uint256 ruleCount, uint256 maxRules);
    error InvalidFunctionSelectors(uint256 selectorsLength, uint256 maxSelectors);
    error FunctionRulesLengthMismatch(uint256 selectorsLength, uint256 rulesLength);

}