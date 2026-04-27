//SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UniversalExecutor} from "./execution/UniversalExecutor.sol";

contract UniversalExecutorFactory {

    function deploySendraExecutor(address _addressProvider) public returns (address executor) {
        executor = address(new UniversalExecutor(_addressProvider));
        return executor;
    }

}