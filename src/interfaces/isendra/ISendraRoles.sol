// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title ISendraRoles
 * @notice Minimal interface for the Sendra Roles contract access checks.
 * @dev Mirrors `Roles.isProtocolContract` from the Sendra protocol.
 */
interface ISendraRoles {
    /**
     * @notice Checks if an address is a whitelisted protocol contract.
     * @param _contract The address to check.
     * @return True if the address is a protocol contract, false otherwise.
     */
    function isProtocolContract(address _contract) external view returns (bool);
}
