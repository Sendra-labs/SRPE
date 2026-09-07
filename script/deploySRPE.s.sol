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
 *
 * Requires ADMIN1_PRIVATE_KEY in .env (admin on the Sendra AddressProvider).
 */
contract DeploySRPE is Script {
    address public constant ADDRESS_PROVIDER = 0xaF7A2feFBA6Acc09e62011d0359dC06e0e1245f5;
    address public constant SENDRA_STORAGE = 0x898258E70C2b3626EF65B5B4c39bb6F37ebcD4Fd;

    function run() public {
        ISendraAddressProvider provider = ISendraAddressProvider(ADDRESS_PROVIDER);

        uint256 adminKey = vm.envUint("ADMIN1_PRIVATE_KEY");
        vm.startBroadcast(adminKey);

        RPFPStorage rpfpStorage = new RPFPStorage(ADDRESS_PROVIDER);
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
