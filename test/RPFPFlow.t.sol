// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {SRPELib} from "../src/libs/SRPE/SRPE.lib.sol";
import {SimpleStorage} from "../src/core/demo/SimpleStorage.sol";
import {SimpleLogic} from "../src/core/demo/SimpleLogic.sol";
import {MockedAddressProvider} from "../src/core/demo/MockedAddressProv.sol";
import {MockedSendra} from "../src/core/demo/MockedSendra.sol";
import {MockedRoles} from "../src/core/demo/MockedRoles.sol";
import {RPFPStorage} from "../src/core/storage/RPFPStorage.sol";
import {UniversalRuler} from "../src/core/UniversalRuler.sol";
import {UniversalExecutorFactory} from "../src/core/UniversalExecutorFactory.sol";
import {RPFPDeployer} from "../src/core/RPFPDeployer.sol";
import {UniversalExecutor} from "../src/core/execution/UniversalExecutor.sol";

contract RPFPFlowTest is Test {
    MockedAddressProvider internal addressProvider;
    MockedSendra internal mockedSendra;
    MockedRoles internal roles;
    RPFPStorage internal rpfpStorage;
    UniversalRuler internal ruler;
    UniversalExecutorFactory internal executorFactory;
    RPFPDeployer internal deployer;

    SimpleStorage internal simpleStorage;
    SimpleLogic internal simpleLogic;

    bytes4 internal constant FIRST_SEL = bytes4(keccak256("firstFunction(address)"));
    bytes4 internal constant SECOND_SEL = bytes4(keccak256("secondFunction(uint256)"));
    bytes4 internal constant THIRD_SEL = bytes4(keccak256("thirdFunction(uint256)"));

    address internal constant ALLOWED_ADDR = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address internal constant DISALLOWED_ADDR = 0xF30AdC373865D58446e945Ef855489E12Bd34Da6;

    uint256 internal rpfpId;
    UniversalExecutor internal executor;

    function setUp() public {
        vm.warp(20_000);

        simpleStorage = new SimpleStorage();
        simpleLogic = new SimpleLogic(address(simpleStorage));

        addressProvider = new MockedAddressProvider();
        mockedSendra = new MockedSendra();
        roles = new MockedRoles();
        addressProvider.setRoles(address(roles));

        rpfpStorage = new RPFPStorage(address(addressProvider));
        ruler = new UniversalRuler(address(addressProvider));
        executorFactory = new UniversalExecutorFactory();
        deployer = new RPFPDeployer(address(addressProvider));

        roles.allowContract(address(deployer));

        addressProvider.setMockedSendra(address(mockedSendra));
        addressProvider.setRPFPStorage(address(rpfpStorage));
        addressProvider.setUniversalRuler(address(ruler));
        addressProvider.setUniversalExecutorFactory(address(executorFactory));

        // Create RPFP with per-selector rules
        SRPELib.NewRPFPInputs memory inputs;
        inputs._type = 0;
        inputs.implementation = address(simpleLogic);
        inputs.ruler = address(ruler);
        inputs.description = "Simple RPFP";
        inputs.extraData = "";
        inputs.owners = new address[](1);
        inputs.owners[0] = address(0);

        SRPELib.Rule[] memory globalRules = new SRPELib.Rule[](1);
        globalRules[0] = SRPELib.Rule({ruleType: 0, ruleData: "", extraData: ""});
        inputs.rules = SRPELib.Rules({ruleCount: 1, rules: globalRules});

        SRPELib.Instruction[] memory emptyInstructions = new SRPELib.Instruction[](0);
        inputs.instructions = SRPELib.Instructions({instructions: emptyInstructions});

        inputs.functionSelectors = new bytes4[](3);
        inputs.functionSelectors[0] = FIRST_SEL;
        inputs.functionSelectors[1] = SECOND_SEL;
        inputs.functionSelectors[2] = THIRD_SEL;

        inputs.functionSelectorRules = new SRPELib.Rules[](3);
        inputs.functionSelectorRules[0] = _firstFunctionRules(ALLOWED_ADDR, block.timestamp + 120);
        inputs.functionSelectorRules[1] = _secondFunctionRulesWinCountGt(20);
        inputs.functionSelectorRules[2] = _noOpRules();

        rpfpId = rpfpStorage.nextRPFPId();
        deployer.deployRPFP(inputs);

        SRPELib.RPFPForRead memory rpfp = rpfpStorage.readRPFPById(rpfpId);
        executor = UniversalExecutor(rpfp.executor);
    }

    function test_rulesStoredForSelectors() public view {
        SRPELib.Rules memory r0 = rpfpStorage.getFunctionRules(rpfpId, FIRST_SEL);
        SRPELib.Rules memory r1 = rpfpStorage.getFunctionRules(rpfpId, SECOND_SEL);
        SRPELib.Rules memory r2 = rpfpStorage.getFunctionRules(rpfpId, THIRD_SEL);

        assertEq(r0.ruleCount, 2);
        assertEq(r0.rules.length, 2);
        assertEq(r0.rules[0].ruleType, 7);
        assertEq(r0.rules[1].ruleType, 3);

        assertEq(r1.ruleCount, 1);
        assertEq(r1.rules.length, 1);
        assertEq(r1.rules[0].ruleType, 21);

        assertEq(r2.ruleCount, 1);
        assertEq(r2.rules.length, 1);
        assertEq(r2.rules[0].ruleType, 0);
    }

    function test_firstFunction_revertsWhenParamDoesNotMatch() public {
        SRPELib.ExecutionParams memory p;
        p.rpfpId = rpfpId;
        p.actionData = abi.encodeWithSelector(FIRST_SEL, DISALLOWED_ADDR);

        vm.expectRevert(abi.encodeWithSelector(UniversalRuler.InvalidAction.selector, 0, FIRST_SEL));
        executor.execute(p);
    }

    function test_firstFunction_allowsWhenParamMatchesAndBeforeDeadline() public {
        SRPELib.ExecutionParams memory p;
        p.rpfpId = rpfpId;
        p.actionData = abi.encodeWithSelector(FIRST_SEL, ALLOWED_ADDR);

        executor.execute(p);
        assertEq(simpleStorage.account1(), ALLOWED_ADDR);
    }

    function test_firstFunction_revertsAfterDeadline() public {
        vm.warp(block.timestamp + 121);

        SRPELib.ExecutionParams memory p;
        p.rpfpId = rpfpId;
        p.actionData = abi.encodeWithSelector(FIRST_SEL, ALLOWED_ADDR);

        vm.expectRevert(abi.encodeWithSelector(UniversalRuler.InvalidAction.selector, 1, FIRST_SEL));
        executor.execute(p);
    }

    function test_secondFunction_winCountRule_passesForAddressZeroAndFailsForOthers() public {
        SRPELib.ExecutionParams memory p;
        p.rpfpId = rpfpId;
        p.actionData = abi.encodeWithSelector(SECOND_SEL, uint256(42));

        vm.prank(address(0));
        executor.execute(p);
        assertEq(simpleStorage.count1(), 42);

        vm.expectRevert(abi.encodeWithSelector(UniversalRuler.InvalidAction.selector, 0, SECOND_SEL));
        executor.execute(p);
    }

    function test_thirdFunction_noOpRulesAlwaysAllow() public {
        SRPELib.ExecutionParams memory p;
        p.rpfpId = rpfpId;
        p.actionData = abi.encodeWithSelector(THIRD_SEL, uint256(777));

        executor.execute(p);
        assertEq(simpleStorage.count2(), 777);
    }

    function _firstFunctionRules(address allowed, uint256 deadline) internal pure returns (SRPELib.Rules memory) {
        SRPELib.Rule[] memory arr = new SRPELib.Rule[](2);
        arr[0] = SRPELib.Rule({
            ruleType: 7,
            ruleData: abi.encode(FIRST_SEL, uint256(0), bytes32(uint256(uint160(allowed)))),
            extraData: ""
        });
        arr[1] = SRPELib.Rule({
            ruleType: 3,
            ruleData: abi.encode(uint256[2]([deadline, uint256(1)])), // type=1 => ruleValue > block.timestamp
            extraData: ""
        });
        return SRPELib.Rules({ruleCount: 2, rules: arr});
    }

    function _secondFunctionRulesWinCountGt(uint256 minExclusive) internal pure returns (SRPELib.Rules memory) {
        SRPELib.Rule[] memory arr = new SRPELib.Rule[](1);
        arr[0] = SRPELib.Rule({ruleType: 21, ruleData: abi.encode(uint256[2]([minExclusive, uint256(0)])), extraData: ""});
        return SRPELib.Rules({ruleCount: 1, rules: arr});
    }

    function _noOpRules() internal pure returns (SRPELib.Rules memory) {
        SRPELib.Rule[] memory arr = new SRPELib.Rule[](1);
        arr[0] = SRPELib.Rule({ruleType: 0, ruleData: "", extraData: ""});
        return SRPELib.Rules({ruleCount: 1, rules: arr});
    }
}

