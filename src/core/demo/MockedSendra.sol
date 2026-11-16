// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SendraLib} from "../../libs/core/Sendra.lib.sol";

/// @notice SendraStorage stand-in. The reputed sender has the stronger book; everyone else is weaker.
///         Tests can override either book per address.
contract MockedSendra {
    address public constant REPUTED = 0x7F4C831de10684f85867899708cB49FfbF4983B9;

    mapping(address => bool) internal globalSet;
    mapping(address => SendraLib.GlobalAccumulators) internal globalOverride;
    mapping(address => mapping(uint64 => SendraLib.SpecificAccumulators)) internal specificData;

    function setGlobalAccumulators(address user, SendraLib.GlobalAccumulators calldata g) external {
        globalSet[user] = true;
        globalOverride[user] = g;
    }

    function setSpecificAccumulators(address user, uint64 key, SendraLib.SpecificAccumulators calldata s) external {
        specificData[user][key] = s;
    }

    function getUserGlobalAccumulators(address _user) external view returns (SendraLib.GlobalAccumulators memory) {
        if (globalSet[_user]) return globalOverride[_user];
        if (_user == REPUTED) {
            return SendraLib.GlobalAccumulators({
                totalCapitalIn: 10000,
                totalCapitalOut: 12000,
                peakSimultaneousExposure: 8000,
                currentExposure: 3200,
                cumulativeRealizedPnl: 2000,
                grossProfit: 3000,
                grossLoss: 1000,
                highWaterMark: 12000,
                maxDrawdown: 2000,
                totalPositionsOpened: 10,
                totalPositionsClosed: 5,
                winCount: 30,
                lossCount: 13,
                totalDurationSeconds: 10000,
                firstActivityTimestamp: block.timestamp - 10000,
                lastActivityTimestamp: block.timestamp,
                totalLiquidationEvents: 0,
                consecutiveLosses: 0,
                maxConsecutiveLosses: 0
            });
        }
        return SendraLib.GlobalAccumulators({
            totalCapitalIn: 1000,
            totalCapitalOut: 900,
            peakSimultaneousExposure: 700,
            currentExposure: 100,
            cumulativeRealizedPnl: 100,
            grossProfit: 10,
            grossLoss: 210,
            highWaterMark: 10,
            maxDrawdown: 210,
            totalPositionsOpened: 5,
            totalPositionsClosed: 3,
            winCount: 2,
            lossCount: 1,
            totalDurationSeconds: 5000,
            firstActivityTimestamp: block.timestamp - 5000,
            lastActivityTimestamp: block.timestamp,
            totalLiquidationEvents: 0,
            consecutiveLosses: 0,
            maxConsecutiveLosses: 0
        });
    }

    function getUserSpecificAccumulators(address _user, uint64 _specificKey)
        external
        view
        returns (SendraLib.SpecificAccumulators memory)
    {
        return specificData[_user][_specificKey];
    }
}
