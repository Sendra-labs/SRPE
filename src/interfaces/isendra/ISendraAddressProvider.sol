// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ISendraAddressProvider {
    /**
     * @notice Gets the address of a contract by name.
     * @param contractName Protocol/contract name (e.g., "GMX", "Uniswap", "Aave").
     * @return Address of the target contract.
     */
    function getAddress(string calldata contractName) external view returns (address);

    /**
     * @notice Sets the address of a contract by name.
     * @dev Requires admin permissions on the Sendra AddressProvider.
     */
    function setAddress(string calldata contractName, address _address) external;

    event ContractAddressUpdated(string indexed contractName, address indexed _address);

    error AddressNotFound(string contractName);
}

