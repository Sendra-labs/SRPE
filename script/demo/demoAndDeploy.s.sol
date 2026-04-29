// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

import {SimpleStorage} from "../../src/core/demo/SimpleStorage.sol";
import {SimpleLogic} from "../../src/core/demo/SimpleLogic.sol";
import {SRPELib} from "../../src/libs/SRPE/SRPE.lib.sol";
import {UniversalExecutor} from "../../src/core/execution/UniversalExecutor.sol";
import {RPFPDeployer} from "../../src/core/RPFPDeployer.sol";
import {MockedSendra} from "../../src/core/demo/MockedSendra.sol";
import {MockedAddressProvider} from "../../src/core/demo/MockedAddressProv.sol";
import {RPFPStorage} from "../../src/core/storage/RPFPStorage.sol";
import {UniversalRuler} from "../../src/core/UniversalRuler.sol";
import {UniversalExecutorFactory} from "../../src/core/UniversalExecutorFactory.sol";

contract DemoAndDeploy is Script {
    address public constant ALLOWED_TOKEN = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

    function run() public {
        vm.startBroadcast();

        SimpleStorage simpleStorage = new SimpleStorage();
        SimpleLogic simpleLogic = new SimpleLogic(address(simpleStorage));

        MockedAddressProvider addressProvider = new MockedAddressProvider();
        MockedSendra mockedSendra = new MockedSendra();
        RPFPStorage rpfpStorage = new RPFPStorage();
        UniversalRuler universalRuler = new UniversalRuler(address(addressProvider));
        UniversalExecutorFactory universalExecutorFactory = new UniversalExecutorFactory();
        RPFPDeployer rpfpDeployer = new RPFPDeployer(address(addressProvider));

        addressProvider.setMockedSendra(address(mockedSendra));
        addressProvider.setUniversalExecutorFactory(address(universalExecutorFactory));
        addressProvider.setRPFPStorage(address(rpfpStorage));
        addressProvider.setUniversalRuler(address(universalRuler));

        console.log("simpleStorage:", address(simpleStorage));
        console.log("simpleLogic:", address(simpleLogic));
        console.log("addressProvider:", address(addressProvider));
        console.log("mockedSendra (SendraStorage):", address(mockedSendra));
        console.log("rpfpStorage (RPFPStorage):", address(rpfpStorage));
        console.log("universalRuler (UniversalRuler):", address(universalRuler));
        console.log("universalExecutorFactory:", address(universalExecutorFactory));
        console.log("rpfpDeployer:", address(rpfpDeployer));

        SRPELib.NewRPFPInputs memory inputs;
        inputs._type = 0;
        inputs.implementation = address(simpleLogic);
        inputs.ruler = address(universalRuler);
        inputs.extraData = new bytes(0);
        inputs.description = "Simple RPFP (deployed by DemoAndDeploy)";

        inputs.owners = new address[](1);
        inputs.owners[0] = address(0);

        SRPELib.Rule[] memory globalRules = new SRPELib.Rule[](1);
        globalRules[0] = SRPELib.Rule({ruleType: 0, ruleData: new bytes(0), extraData: new bytes(0)});
        inputs.rules = SRPELib.Rules({ruleCount: 1, rules: globalRules});

        SRPELib.Instruction[] memory emptyInstructions = new SRPELib.Instruction[](0);
        inputs.instructions = SRPELib.Instructions({instructions: emptyInstructions});

        bytes4 firstSel = bytes4(keccak256("firstFunction(address)"));
        bytes4 secondSel = bytes4(keccak256("secondFunction(uint256)"));
        bytes4 thirdSel = bytes4(keccak256("thirdFunction(uint256)"));

        inputs.functionSelectors = new bytes4[](3);
        inputs.functionSelectors[0] = firstSel;
        inputs.functionSelectors[1] = secondSel;
        inputs.functionSelectors[2] = thirdSel;

        bytes32 expectedWord = bytes32(uint256(uint160(ALLOWED_TOKEN)));
        SRPELib.Rule[] memory firstRulesArr = new SRPELib.Rule[](2);
        firstRulesArr[0] = SRPELib.Rule({
            ruleType: 7,
            ruleData: abi.encode(firstSel, uint256(0), expectedWord),
            extraData: new bytes(0)
        });
        firstRulesArr[1] = SRPELib.Rule({
            ruleType: 3,
            ruleData: abi.encode(uint256[2]([block.timestamp + 120 seconds, 1])),
            extraData: new bytes(0)
        });
        SRPELib.Rules memory firstFunctionRules = SRPELib.Rules({ruleCount: 2, rules: firstRulesArr});

        SRPELib.Rule[] memory secondRulesArr = new SRPELib.Rule[](1);
        secondRulesArr[0] = SRPELib.Rule({
            ruleType: 21,
            ruleData: abi.encode(uint256[2]([uint256(20), uint256(0)])),
            extraData: new bytes(0)
        });
        SRPELib.Rules memory secondFunctionRules = SRPELib.Rules({ruleCount: 1, rules: secondRulesArr});

        SRPELib.Rule[] memory thirdRulesArr = new SRPELib.Rule[](1);
        thirdRulesArr[0] = SRPELib.Rule({ruleType: 0, ruleData: new bytes(0), extraData: new bytes(0)});
        SRPELib.Rules memory thirdFunctionRules = SRPELib.Rules({ruleCount: 1, rules: thirdRulesArr});

        inputs.functionSelectorRules = new SRPELib.Rules[](3);
        inputs.functionSelectorRules[0] = firstFunctionRules;
        inputs.functionSelectorRules[1] = secondFunctionRules;
        inputs.functionSelectorRules[2] = thirdFunctionRules;

        uint256 rpfpId = rpfpStorage.nextRPFPId();
        rpfpDeployer.deployRPFP(inputs);

        SRPELib.RPFPForRead memory rpfp = rpfpStorage.readRPFPById(rpfpId);
        UniversalExecutor executor = UniversalExecutor(rpfp.executor);

        console.log("rpfpId:", rpfpId);
        console.log("executor:", address(executor));
        console.log("implementation:", rpfp.implementation);

        vm.stopBroadcast();
    }
}

