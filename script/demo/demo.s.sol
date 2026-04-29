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

contract DemoScript is Script {

    address public constant ALLOWED_SENDER = 0x7F4C831de10684f85867899708cB49FfbF4983B9;
    address public constant ALLOWED_TOKEN = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

    address public constant SIMPLE_STORAGE_ADDR = 0xD8338c83bAcc6b986De3eB4E552e8E5DCbFC05D6;
    address public constant SIMPLE_LOGIC_ADDR = 0xa89Bf912A54b67eA848982Cc94EE06B49221E1bd;
    address public constant RPFP_STORAGE_ADDR = 0x13aCC5Cb590a8c1BB08Da3b6f6af5A1700c503bf;
    address public constant UNIVERSAL_RULER_ADDR = 0x932701235cbe72509df5783fF4866cC34EF17ee7;

    SimpleStorage public simpleStorage;
    SimpleLogic public simpleLogic;

    MockedAddressProvider public mockedAddressProvider;
    RPFPStorage public rpFPStorage;
    UniversalRuler public universalRuler;
    UniversalExecutorFactory public universalExecutorFactory;
    RPFPDeployer public rpfpDeployer;

    UniversalExecutor public universalExecutor;
    uint256 public rpfpId;

    SRPELib.NewRPFPInputs public _newRPFPInputs;

    function setUp() public {
        simpleStorage = SimpleStorage(SIMPLE_STORAGE_ADDR);
        simpleLogic = SimpleLogic(SIMPLE_LOGIC_ADDR);
        rpFPStorage = RPFPStorage(RPFP_STORAGE_ADDR);
        universalRuler = UniversalRuler(UNIVERSAL_RULER_ADDR);

        console.log("simpleStorage address:", address(simpleStorage));
        console.log("simpleLogic address:", address(simpleLogic));
        console.log("rpFPStorage address:", address(rpFPStorage));
        console.log("universalRuler address:", address(universalRuler));

        mockedAddressProvider = MockedAddressProvider(address(universalRuler.addressProvider()));
        console.log("mockedAddressProvider address:", address(mockedAddressProvider));

        universalExecutorFactory = UniversalExecutorFactory(mockedAddressProvider.getAddress("UniversalExecutorFactory"));
        console.log("universalExecutorFactory address:", address(universalExecutorFactory));

        vm.startBroadcast();
        rpfpDeployer = new RPFPDeployer(address(mockedAddressProvider));
        vm.stopBroadcast();
        console.log("rpfpDeployer address:", address(rpfpDeployer));

        _newRPFPInputs._type = 0;
        _newRPFPInputs.implementation = address(simpleLogic);
        _newRPFPInputs.ruler = address(universalRuler);
        _newRPFPInputs.extraData = new bytes(0);
        _newRPFPInputs.description = "Simple RPFP";

        _newRPFPInputs.owners = new address[](1);
        _newRPFPInputs.owners[0] = address(0);

        SRPELib.Rule[] memory globalRules = new SRPELib.Rule[](1);
        globalRules[0] = SRPELib.Rule({ruleType: 0, ruleData: new bytes(0), extraData: new bytes(0)});
        _newRPFPInputs.rules = SRPELib.Rules({ruleCount: 1, rules: globalRules});

        SRPELib.Instruction[] memory emptyInstructions = new SRPELib.Instruction[](0);
        _newRPFPInputs.instructions = SRPELib.Instructions({instructions: emptyInstructions});

        bytes4 firstSel = bytes4(keccak256("firstFunction(address)"));
        bytes4 secondSel = bytes4(keccak256("secondFunction(uint256)"));
        bytes4 thirdSel = bytes4(keccak256("thirdFunction(uint256)"));

        _newRPFPInputs.functionSelectors = new bytes4[](3);
        _newRPFPInputs.functionSelectors[0] = firstSel;
        _newRPFPInputs.functionSelectors[1] = secondSel;
        _newRPFPInputs.functionSelectors[2] = thirdSel;

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

        _newRPFPInputs.functionSelectorRules = new SRPELib.Rules[](3);
        _newRPFPInputs.functionSelectorRules[0] = firstFunctionRules;
        _newRPFPInputs.functionSelectorRules[1] = secondFunctionRules;
        _newRPFPInputs.functionSelectorRules[2] = thirdFunctionRules;
    }

    function run() public {
        vm.startBroadcast();
        rpfpId = rpFPStorage.nextRPFPId();
        rpfpDeployer.deployRPFP(_newRPFPInputs);

        SRPELib.RPFPForRead memory rpfp = rpFPStorage.readRPFPById(rpfpId);
        universalExecutor = UniversalExecutor(rpfp.executor);

        SRPELib.ExecutionParams memory execParams;
        execParams.targetFunction = 1;
        execParams.rpfpId = rpfpId;
        execParams.actionData = abi.encodeWithSelector(_newRPFPInputs.functionSelectors[1], uint256(42));

        universalExecutor.execute(execParams);
        vm.stopBroadcast();
    }
} 