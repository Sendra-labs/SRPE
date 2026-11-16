// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UniversalExecutorFactory} from "./UniversalExecutorFactory.sol";
import {UniversalRuler} from "./UniversalRuler.sol";
import {SRPELib} from "../libs/SRPE/SRPE.lib.sol";
import {RPFPStorage} from "./storage/RPFPStorage.sol";
import {ISendraAddressProvider} from "../interfaces/isendra/ISendraAddressProvider.sol";
import {RulesHelper} from "./RulesHelper.sol";

/// @title RPFPDeployer
/// @notice Deploys an executor, stores its policy, and freezes that policy in the same transaction.
contract RPFPDeployer is RulesHelper {
    ISendraAddressProvider public immutable addressProvider;

    uint256 public constant MAX_RULES = SRPELib.MAX_RULES;
    /// @notice One selector per product action. The cap leaves room for LP, spot, and lending flows.
    uint256 public constant MAX_FUNCTION_SELECTORS = SRPELib.MAX_FUNCTION_SELECTORS;

    constructor(address _addressProvider) {
        addressProvider = ISendraAddressProvider(_addressProvider);
    }

    /// @notice Creates an enclave and freezes its rules before returning.
    /// @dev Permissionless. Any address may call this. Writes go through this contract, which is
    ///      the only writer `RPFPStorage` accepts. A clone of this deployer cannot register enclaves.
    ///      Validation runs before the executor is created. Storage validates again on write.
    ///      `inputs.ruler` must be zero or the canonical ruler. The stored ruler is always canonical.
    ///      Empty `owners` is filled with `msg.sender`. That list is metadata, not an admin key.
    function deployRPFP(SRPELib.NewRPFPInputs memory _newRPFPInputs) public returns (address executor, uint256 rpfpId) {
        address implementation = _newRPFPInputs.implementation;
        if (implementation.code.length == 0) revert InvalidImplementation();

        RPFPStorage rpfpStorageContract = RPFPStorage(addressProvider.getAddress("RPFPStorage"));
        UniversalRuler canonicalRuler = UniversalRuler(addressProvider.getAddress("UniversalRuler"));
        address factory = addressProvider.getAddress("UniversalExecutorFactory");
        if (address(canonicalRuler.rpfpStorage()) != address(rpfpStorageContract)) revert InvalidRuler();
        if (_newRPFPInputs.ruler != address(0) && _newRPFPInputs.ruler != address(canonicalRuler)) {
            revert InvalidRuler();
        }
        _newRPFPInputs.ruler = address(canonicalRuler);

        if (
            implementation == address(rpfpStorageContract) || implementation == address(canonicalRuler)
                || implementation == factory || implementation == address(addressProvider) || implementation == address(this)
        ) revert InvalidImplementation();

        uint256 selectorCount = _newRPFPInputs.functionSelectors.length;
        if (selectorCount == 0 || selectorCount > MAX_FUNCTION_SELECTORS) {
            revert InvalidFunctionSelectors(selectorCount, MAX_FUNCTION_SELECTORS);
        }
        if (selectorCount != _newRPFPInputs.functionSelectorRules.length) {
            revert FunctionRulesLengthMismatch(selectorCount, _newRPFPInputs.functionSelectorRules.length);
        }

        SRPELib.Rules memory globalRules = _newRPFPInputs.rules;
        _prepareRules(bytes4(0), globalRules, false, true);
        _newRPFPInputs.rules = globalRules;
        for (uint256 i = 0; i < selectorCount;) {
            bytes4 selector = _newRPFPInputs.functionSelectors[i];
            for (uint256 j = 0; j < i;) {
                if (_newRPFPInputs.functionSelectors[j] == selector) revert DuplicateSelector(selector);
                unchecked {
                    ++j;
                }
            }
            SRPELib.Rules memory prepared = _newRPFPInputs.functionSelectorRules[i];
            _prepareRules(selector, prepared, true, false);
            _newRPFPInputs.functionSelectorRules[i] = prepared;
            unchecked {
                ++i;
            }
        }

        if (_newRPFPInputs.owners.length == 0) {
            _newRPFPInputs.owners = new address[](1);
            _newRPFPInputs.owners[0] = msg.sender;
        }

        executor = UniversalExecutorFactory(factory).deploySendraExecutor(
            address(addressProvider), address(rpfpStorageContract), address(canonicalRuler)
        );

        rpfpId = rpfpStorageContract.createRPFP(
            _newRPFPInputs._type,
            executor,
            implementation,
            _newRPFPInputs.ruler,
            _newRPFPInputs.owners,
            msg.sender,
            _newRPFPInputs.description,
            _newRPFPInputs.extraData,
            _newRPFPInputs.rules,
            _newRPFPInputs.instructions
        );

        for (uint256 i = 0; i < selectorCount;) {
            rpfpStorageContract.setFunctionRules(rpfpId, _newRPFPInputs.functionSelectors[i], _newRPFPInputs.functionSelectorRules[i]);
            unchecked {
                ++i;
            }
        }
        rpfpStorageContract.lockRules(rpfpId);
        emit RPFPDeployed(executor, rpfpId, msg.sender, implementation);
    }

    /// @dev `rules` is a memory reference. `ruleCount` is normalized to the array length.
    function _prepareRules(bytes4 selector, SRPELib.Rules memory rules, bool selectorBound, bool allowEmpty)
        internal
        pure
    {
        uint256 n = rules.rules.length;
        if (n > MAX_RULES || (!allowEmpty && n == 0)) revert InvalidRules(n, MAX_RULES);
        rules.ruleCount = n;
        for (uint256 i = 0; i < n;) {
            _validateRule(selector, rules.rules[i], selectorBound);
            unchecked {
                ++i;
            }
        }
    }

    event RPFPDeployed(address indexed executor, uint256 indexed rpfpId, address indexed creator, address implementation);

    error InvalidFunctionSelectors(uint256 selectorsLength, uint256 maxSelectors);
    error FunctionRulesLengthMismatch(uint256 selectorsLength, uint256 rulesLength);
    error DuplicateSelector(bytes4 selector);
    error InvalidImplementation();
    error InvalidRuler();
}
