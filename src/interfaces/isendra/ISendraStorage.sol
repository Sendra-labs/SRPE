// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SendraLib} from "../../libs/core/Sendra.lib.sol";

interface ISendraStorage {

    function getUser(address _user) external view returns (SendraLib.UserInfoRead memory userInfo);
    
    /**
     * @notice Returns the user's global pulse accumulators.
     * @dev This is a convenience getter for `users[_user].pulse.globalPulse`.
     *      If the user has not been created yet, all fields will be zeroed.
     * @param _user The user address.
     */
    function getUserGlobalAccumulators(address _user) external view returns (SendraLib.GlobalAccumulators memory);
    
    /**
     * @notice Returns a single global accumulator for a given user and field id.
     * @dev Reverts if `_fieldId` is out of bounds for `globalPulse`.
     * @param _user The user address.
     * @param _fieldId The field id.
     */
    function getUniqueGlobalAccumulator(uint8 _fieldId, address _user) external view returns (int256);

    /**
     * @notice Returns the user's specific pulse accumulators for a given key.
     * @dev Convenience getter for `users[_user].pulse.specificPulse[_specificKey]`.
     *      If the user/key has never been used, all fields will be zeroed and metrics length will be 0.
     * @param _user The user address.
     * @param _specificKey The specific accumulator key (e.g. position type or strategy id).
     */
    function getUserSpecificAccumulators(address _user, uint64 _specificKey) external view returns (SendraLib.SpecificAccumulators memory);

    /**
     * @notice Returns a single specific metric blob for a given user and key.
     * @dev Reverts if `_metricIndex` is out of bounds for `specificMetrics`.
     * @param _user The user address.
     * @param _specificKey The specific accumulator key.
     * @param _metricIndex The index within `specificMetrics`.
     */
    function getUserSpecificMetric(address _user, uint64 _specificKey, uint256 _metricIndex) external view returns (bytes memory);

    /**
     * @notice Returns the number of metric blobs stored for a given user and key.
     * @param _user The user address.
     * @param _specificKey The specific accumulator key.
     */
    function getUserSpecificMetricsLength(address _user, uint64 _specificKey) external view returns (uint256);
    
}