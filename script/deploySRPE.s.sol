// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

import {ISendraAddressProvider} from "../src/interfaces/isendra/ISendraAddressProvider.sol";
import {RPFPStorage} from "../src/core/storage/RPFPStorage.sol";
import {UniversalRuler} from "../src/core/UniversalRuler.sol";
import {UniversalExecutorFactory} from "../src/core/UniversalExecutorFactory.sol";
import {RPFPDeployer} from "../src/core/RPFPDeployer.sol";

/**
 * @title DeploySRPE
 * @notice Deploys the SRPE core contracts and registers them in the Sendra AddressProvider.
 *
 * Prerequisites:
 * - The broadcaster must be an admin on the Sendra AddressProvider.
 * - SendraStorage is already deployed and its address is known.
 *
 * Usage:
 *   forge script script/deploySRPE.s.sol:DeploySRPE --rpc-url arbitrum --broadcast
 */
contract DeploySRPE is Script {
    address public constant ADDRESS_PROVIDER = 0xf57eA29702f75e43761C0398e8e06d0DF1223070;
    address public constant SENDRA_STORAGE = 0x023c59881eeCa9Fad30455ca4A6AE13608Cf0276;

    function run() public {
        ISendraAddressProvider provider = ISendraAddressProvider(ADDRESS_PROVIDER);

        vm.startBroadcast();

        RPFPStorage rpfpStorage = new RPFPStorage();
        UniversalRuler universalRuler = new UniversalRuler(ADDRESS_PROVIDER);
        UniversalExecutorFactory universalExecutorFactory = new UniversalExecutorFactory();
        RPFPDeployer rpfpDeployer = new RPFPDeployer(ADDRESS_PROVIDER);

        provider.setAddress("SendraStorage", SENDRA_STORAGE);
        provider.setAddress("RPFPStorage", address(rpfpStorage));
        provider.setAddress("UniversalRuler", address(universalRuler));
        provider.setAddress("UniversalExecutorFactory", address(universalExecutorFactory));
        provider.setAddress("RPFPDeployer", address(rpfpDeployer));

        vm.stopBroadcast();

        _logDeployment(provider, rpfpStorage, universalRuler, universalExecutorFactory, rpfpDeployer);
    }

    function _logDeployment(
        ISendraAddressProvider provider,
        RPFPStorage rpfpStorage,
        UniversalRuler universalRuler,
        UniversalExecutorFactory universalExecutorFactory,
        RPFPDeployer rpfpDeployer
    ) internal view {
        console.log("=== SRPE deployment complete ===");
        console.log("addressProvider:", ADDRESS_PROVIDER);
        console.log("");
        console.log("--- deployed ---");
        console.log("rpfpStorage:", address(rpfpStorage));
        console.log("universalRuler:", address(universalRuler));
        console.log("universalExecutorFactory:", address(universalExecutorFactory));
        console.log("rpfpDeployer:", address(rpfpDeployer));
        console.log("");
        console.log("--- registered in AddressProvider ---");
        console.log("SendraStorage:", provider.getAddress("SendraStorage"));
        console.log("RPFPStorage:", provider.getAddress("RPFPStorage"));
        console.log("UniversalRuler:", provider.getAddress("UniversalRuler"));
        console.log("UniversalExecutorFactory:", provider.getAddress("UniversalExecutorFactory"));
        console.log("RPFPDeployer:", provider.getAddress("RPFPDeployer"));
    }
}
