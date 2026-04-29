// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

import {MockedSendra} from "../../src/core/demo/MockedSendra.sol";
import {MockedAddressProvider} from "../../src/core/demo/MockedAddressProv.sol";

contract DeployMockedSendra is Script {
    function run() public {
        address providerAddr = 0x249D74fc2D712B9d6B97bC5bbC9982F1Cbb490E7;

        vm.startBroadcast();
        MockedSendra mockedSendra = new MockedSendra();
        MockedAddressProvider(providerAddr).setMockedSendra(address(mockedSendra));
        vm.stopBroadcast();

        console.log("addressProvider:", providerAddr);
        console.log("new MockedSendra (SendraStorage):", address(mockedSendra));
    }
}

