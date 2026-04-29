// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;


contract MockedAddressProvider {

    address public MockedSendra;
    address public UniversalExecutorFactory;
    address public RPFPStorage;
    address public UniversalRuler;

    error AddressNotFound(string contractName);

    function getAddress(string memory _name) external view returns (address) {
        bytes32 n = keccak256(abi.encodePacked(_name));

        if (n == keccak256("SendraStorage")) return MockedSendra;
        if (n == keccak256("UniversalExecutorFactory")) return UniversalExecutorFactory;
        if (n == keccak256("RPFPStorage")) return RPFPStorage;
        if (n == keccak256("UniversalRuler")) return UniversalRuler;

        revert AddressNotFound(_name);
    }

    function setMockedSendra(address _mockedSendra) external {
        MockedSendra = _mockedSendra;
    }

    function setUniversalExecutorFactory(address _universalExecutorFactory) external {
        UniversalExecutorFactory = _universalExecutorFactory;
    }

    function setRPFPStorage(address _rpfpStorage) external {
        RPFPStorage = _rpfpStorage;
    }

    function setUniversalRuler(address _universalRuler) external {
        UniversalRuler = _universalRuler;
    }

}