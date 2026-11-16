// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script, console } from "forge-std/Script.sol";
import { RPFPStorage } from "../src/core/storage/RPFPStorage.sol";
import { UniversalRuler } from "../src/core/UniversalRuler.sol";
import { UniversalExecutorFactory } from "../src/core/UniversalExecutorFactory.sol";
import { RPFPDeployer } from "../src/core/RPFPDeployer.sol";

interface IProvider {
    function getAddress(string calldata name) external view returns (address);
    function proposeAddress(string calldata name, address addr) external;
}

interface IRoles {
    function allowContract(address account, string calldata name) external;
    function isProtocolContract(address account) external view returns (bool);
}

/**
 * @notice Deploys SRPE onto the AddressProvider in ADDRESS_PROVIDER.
 *         Three hot admins vote. SendraStorage stays as already registered.
 *         RPFPDeployer is allowlisted because it writes RPFPStorage.
 *
 *         The deploy to run is LPCreditEnclaves/script/DeploySRPE.s.sol.
 *         This file is the same flow for this repo.
 */
contract DeploySRPE is Script {
    function run() public {
        if (block.chainid != 42161) revert WrongChain();
        IProvider provider = IProvider(vm.envAddress("ADDRESS_PROVIDER"));
        IRoles roles = IRoles(provider.getAddress("Roles"));
        address sendraStorage = provider.getAddress("SendraStorage");

        uint256[3] memory keys = _keys();
        vm.startBroadcast(keys[0]);
        RPFPStorage rpfpStorage = new RPFPStorage(address(provider));
        UniversalRuler ruler = new UniversalRuler(address(provider), address(rpfpStorage), sendraStorage);
        UniversalExecutorFactory factory = new UniversalExecutorFactory();
        RPFPDeployer deployer = new RPFPDeployer(address(provider));
        vm.stopBroadcast();

        _propose(provider, keys, "RPFPStorage", address(rpfpStorage));
        _propose(provider, keys, "UniversalRuler", address(ruler));
        _propose(provider, keys, "UniversalExecutorFactory", address(factory));
        _propose(provider, keys, "RPFPDeployer", address(deployer));
        if (!roles.isProtocolContract(address(deployer))) {
            for (uint256 i = 0; i < 3; i++) {
                vm.startBroadcast(keys[i]);
                roles.allowContract(address(deployer), "RPFPDeployer");
                vm.stopBroadcast();
            }
        }

        console.log("RPFPStorage", address(rpfpStorage));
        console.log("UniversalRuler", address(ruler));
        console.log("UniversalExecutorFactory", address(factory));
        console.log("RPFPDeployer", address(deployer));
    }

    function _keys() internal view returns (uint256[3] memory keys) {
        keys[0] = vm.envUint("HOT_ADMIN1_PRIVATE_KEY");
        keys[1] = vm.envUint("HOT_ADMIN2_PRIVATE_KEY");
        keys[2] = vm.envUint("HOT_ADMIN3_PRIVATE_KEY");
    }

    function _propose(IProvider provider, uint256[3] memory keys, string memory name, address addr) internal {
        for (uint256 i = 0; i < 3; i++) {
            vm.startBroadcast(keys[i]);
            provider.proposeAddress(name, addr);
            vm.stopBroadcast();
        }
    }

    error WrongChain();
}
