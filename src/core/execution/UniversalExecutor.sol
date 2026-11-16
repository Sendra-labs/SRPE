// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SRPELib} from "../../libs/SRPE/SRPE.lib.sol";
import {UniversalRuler} from "../UniversalRuler.sol";
import {ISendraAddressProvider} from "../../interfaces/isendra/ISendraAddressProvider.sol";
import {RPFPStorage} from "../storage/RPFPStorage.sol";

/// @title UniversalExecutor
/// @notice Per-enclave entrypoint. Checks the pinned ruler, then `delegatecall`s into the product.
/// @dev Storage and ruler addresses are fixed at deployment. The AddressProvider cannot point an
///      existing enclave at a different policy or a different implementation.
///      The reentrancy guard uses namespaced transient slots so it does not share the compiler's
///      transient layout with the product. Product code may use the executor's persistent storage.
///      It must not write these two transient slots. A product that ignores the checked inputs can
///      still mis-execute them: SRPE constrains the call, not a malicious implementation.
contract UniversalExecutor {
    ISendraAddressProvider public immutable addressProvider;
    RPFPStorage public immutable rpfpStorage;
    UniversalRuler public immutable ruler;

    bytes32 private constant _DEPTH_SLOT = keccak256("srpe.executor.depth");
    bytes32 private constant _LOGIC_SLOT = keccak256("srpe.executor.logic");

    constructor(address _addressProvider, address _rpfpStorage, address _ruler) {
        if (_addressProvider == address(0) || _rpfpStorage == address(0) || _ruler == address(0)) {
            revert InvalidDeployment();
        }
        if (_rpfpStorage.code.length == 0 || _ruler.code.length == 0) revert InvalidDeployment();
        if (address(UniversalRuler(_ruler).rpfpStorage()) != _rpfpStorage) revert InvalidDeployment();
        addressProvider = ISendraAddressProvider(_addressProvider);
        rpfpStorage = RPFPStorage(_rpfpStorage);
        ruler = UniversalRuler(_ruler);
    }

    /// @notice True while product code is running inside this executor. The ruler rejects
    ///         `checkExecution` for the whole window, including callbacks from the product.
    function isInsideLogic() external view returns (bool) {
        return _tload(_LOGIC_SLOT) == 1;
    }

    /// @notice Runs `actionData` on the enclave implementation after policy succeeds.
    /// @dev `msg.value` is preserved by `delegatecall`, so the product function must be `payable`
    ///      when a call-value rule allows ETH. Value is rejected unless that rule is present.
    function execute(SRPELib.ExecutionParams calldata _executionParams) public payable returns (bytes memory) {
        if (_tload(_DEPTH_SLOT) == 1) revert Reentrancy();
        _tstore(_DEPTH_SLOT, 1);

        (address boundExecutor, address implementation) = rpfpStorage.getExecutionTarget(_executionParams.rpfpId);
        if (boundExecutor != address(this)) revert InvalidExecutor();
        if (implementation.code.length == 0) revert InvalidImplementation();

        bytes4 selector = ruler.checkExecution(
            _executionParams.actionData, msg.sender, _executionParams.rpfpId, msg.value
        );

        _tstore(_LOGIC_SLOT, 1);
        (bool success, bytes memory result) = implementation.delegatecall(_executionParams.actionData);
        _tstore(_LOGIC_SLOT, 0);

        if (!success) {
            assembly {
                revert(add(result, 0x20), mload(result))
            }
        }

        _tstore(_DEPTH_SLOT, 0);
        emit Executed(_executionParams.rpfpId, msg.sender, selector, msg.value);
        return result;
    }

    function _tload(bytes32 slot) private view returns (uint256 value) {
        assembly {
            value := tload(slot)
        }
    }

    function _tstore(bytes32 slot, uint256 value) private {
        assembly {
            tstore(slot, value)
        }
    }

    event Executed(uint256 indexed rpfpId, address indexed sender, bytes4 indexed selector, uint256 callValue);

    error Reentrancy();
    error InvalidExecutor();
    error InvalidImplementation();
    error InvalidDeployment();
}
