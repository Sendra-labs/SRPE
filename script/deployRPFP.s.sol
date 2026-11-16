// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {SRPELib} from "../src/libs/SRPE/SRPE.lib.sol";
import {SRPERules} from "../src/libs/SRPE/SRPERules.sol";
import {RPFPDeployer} from "../src/core/RPFPDeployer.sol";
import {RPFPStorage} from "../src/core/storage/RPFPStorage.sol";
import {ISendraAddressProvider} from "../src/interfaces/isendra/ISendraAddressProvider.sol";

/// @notice Permissionless RPFP deploy. Any EOA or contract can run this against the live SRPE.
///
/// Env:
///   ADDRESS_PROVIDER  Sendra AddressProvider
///   IMPLEMENTATION    Logic contract with code. Must expose the selector you register.
///   DESCRIPTION       Optional. Defaults to "RPFP".
///
/// The template registers `touch()` as a public action (rule 0). Replace the payload with
/// `SRPERules` helpers for pool, token, amount, and reputation constraints.
///
///   forge script script/deployRPFP.s.sol:DeployRPFP --rpc-url $ARBITRUM_RPC_URL --broadcast
contract DeployRPFP is Script {
    using SRPERules for *;

    function run() public {
        ISendraAddressProvider provider = ISendraAddressProvider(vm.envAddress("ADDRESS_PROVIDER"));
        RPFPDeployer deployer = RPFPDeployer(provider.getAddress("RPFPDeployer"));
        RPFPStorage store = RPFPStorage(provider.getAddress("RPFPStorage"));
        address implementation = vm.envAddress("IMPLEMENTATION");
        string memory description = vm.envOr("DESCRIPTION", string("RPFP"));

        bytes4 selector = bytes4(keccak256("touch()"));
        SRPELib.NewRPFPInputs memory inputs = SRPERules.publicAction(implementation, selector, description);

        vm.startBroadcast();
        (address executor, uint256 rpfpId) = deployer.deployRPFP(inputs);
        vm.stopBroadcast();

        SRPELib.RPFPForRead memory rpfp = store.readRPFPById(rpfpId);
        console.log("rpfpId", rpfpId);
        console.log("executor", executor);
        console.log("creator", rpfp.creator);
        console.log("implementation", rpfp.implementation);
    }
}
