// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UniversalExecutor} from "./execution/UniversalExecutor.sol";

/// @title UniversalExecutorFactory
/// @notice Deploys one executor per enclave, bound to a storage contract and a ruler.
contract UniversalExecutorFactory {
    /// @notice Deploys an executor. The ruler must already pin `_rpfpStorage`.
    function deploySendraExecutor(address _addressProvider, address _rpfpStorage, address _ruler)
        public
        returns (address executor)
    {
        executor = address(new UniversalExecutor(_addressProvider, _rpfpStorage, _ruler));
    }
}
