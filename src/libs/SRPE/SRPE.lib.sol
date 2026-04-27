// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library SRPELib {

    struct NewRPFPInputs {
        uint16 _type;
        address implementation;
        address ruler;
        address[] owners;
        string description;
        bytes extraData;
        Rules rules;
        Instructions instructions;

        // Per-function selector rules (parallel arrays).
        // Each entry defines the Rules blob applied to that selector.
        bytes4[] functionSelectors;
        Rules[] functionSelectorRules;
    }

    struct RPFP {
        uint16 _type;
        uint256 id;
        address executor;
        address implementation;
        address ruler;
        address[] owners;
        string description;
        bytes extraData;
        uint256 createdAt;
        Rules rules; // global rules catalog for this RPFP
        Instructions instructions; // global instructions catalog

        // Function-specific rules mapped by selector.
        // NOTE: This mapping lives in storage and is not ABI-returnable.
        mapping(bytes4 => Rules) functionRules;
    }

    struct RPFPForRead {
        uint16 _type;
        uint256 id;
        address executor;
        address implementation;
        address ruler;
        address[] owners;
        string description;
        bytes extraData;
        uint256 createdAt;
    }

    struct Instructions {
        Instruction[] instructions;
    }

    struct Instruction { // ¿? con  paramIndex de extraData lo solucionamos...
        bytes4 functionSelector;
        bytes functionSignature;
        uint8[] rulesIndexes;
        uint8[] parameterTypes;
    }


    // Instruction example:
    // function provideLiquidity(uint256 amount, address token) --> function selector == bytes4(keccak256("provideLiquidity(uint256,address)"))
    // functionSignature == bytes("provideLiquidity(uint256,address)")
    // parameterTypes: [0 uint256, 1 address]

    struct ExecutionParams {
        uint256 targetFunction;  // index at instructions array
        uint256 rpfpId;
        bytes actionData; // function signature and parameters
    }

    struct Rule {
        uint16 ruleType;
        bytes ruleData;
        bytes extraData; // for example tu add the index of the parameter in executionParams.actionData to check. 
    }

    struct Rules {
        uint256 ruleCount;
        Rule[] rules;
    }

    /*
    * examples:
    ** Only address(0xA) and address(0xB) are allowed to call the function provideLiquidity()
    ** Rules {
        [5, 5]; // ruleTypes
        [bytes([address(0xA), bytes(provideLiquidity())])), bytes([address(0xB), bytes(provideLiquidity())])]; // ruleData
    }

    for provide liquidity (uint usdcAmount) we need to check the usdcAmount is between the min and max amounts.


    * Rules Docu:
    ruleTypes:
      - 0: No rule
      - 1: whitelist
      - 2: blacklist
      - 3: timeLimit [uint256(value), uint256(type)] type: 0 means greater than, 1 means less than. So to limit txs to be executed in the future type must be 1 and value must be the future timestamp.
      - 4: frequencyLimit
      - 5: allow specific sender ej: [bytes(functionSelector), bytes(address(sender))]  !!! abi.encode(bytes4 selector, address sender)
      - 6: allow specific sender, function and input_value + inputIndex ej: [bytes(functionSelector), bytes(address(sender)), uint256(inputIndex), bytes(input_value)] !!! abi.encode(bytes4 selector, address sender, uint256 paramIndex, bytes32 expectedWord)
      - 7: allow specific function and input_value + inputIndex ej: [bytes(functionSelector), uint256(inputIndex), bytes(input_value)]
      - 8: usdc amounts limits [uint256(min), uint256(max)]
      - 9: 
      - 10: reputationLimit0: totalCapitalIn [value, type] type 0 means greater than, 1 means less than. so to limit the capitalIn to 10k we need to use [10000, 0] so checkUint() wil return true if for example the gAccumulators.totalCapitalIn is 15000
      - 11: reputationLimit1: totalCapitalOut 
      - 12: reputationLimit2: peakSimultaneousExposure
      - 13: reputationLimit3: currentExposure
      - 14: reputationLimit4: cumulativeRealizedPnl
      - 15: reputationLimit5: grossProfit
      - 16: reputationLimit6: grossLoss
      - 17: reputationLimit7: highWaterMark
      - 18: reputationLimit8: maxDrawdown
      - 19: reputationLimit9: totalPositionsOpened
      - 20: reputationLimit10: totalPositionsClosed
      - 21: reputationLimit11: winCount
      - 22: reputationLimit12: lossCount
      - 23: reputationLimit13: totalDurationSeconds
      - 24: reputationLimit14: firstActivityTimestamp
      - 25: reputationLimit15: lastActivityTimestamp
      - 26: reputationLimit16: liquidationEvents
      - 27: reputationLimit17: consecutiveLosses
      - 28: reputationLimit18: maxConsecutiveLosses
      - 29:
      - 30: specificAccumularorLimit20: realizedPnl
      - 31: specificAccumularorLimit21: totalCapitalIn
      - 32: specificAccumularorLimit22: totalCapitalOut
      - 33: specificAccumularorLimit23: winCount
      - 34: specificAccumularorLimit24: lossCount
      - 35: specificAccumularorLimit25: totalPositions
      - 36: specificAccumularorLimit26: bytes[] specificMetrics (e.g. [specificMetricIndex, value, max/min])

    */

}