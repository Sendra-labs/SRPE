// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Minimal Roles mock for local tests/demos.
contract MockedRoles {
    mapping(address => bool) internal protocolContracts;

    function allowContract(address _contract) external {
        protocolContracts[_contract] = true;
    }

    function deleteContract(address _contract) external {
        protocolContracts[_contract] = false;
    }

    function isProtocolContract(address _contract) external view returns (bool) {
        return protocolContracts[_contract];
    }
}
