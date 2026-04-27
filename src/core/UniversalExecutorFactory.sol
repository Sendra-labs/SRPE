//SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UniversalExecutor} from "./execution/UniversalExecutor.sol";

contract UniversalExecutorFactory {

    function deploySendraExecutor(address _implementation) public {
        address executor = address(new SendraExecutor(_implementation));
    }

}