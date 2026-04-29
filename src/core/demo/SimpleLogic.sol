// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SimpleStorage} from "./SimpleStorage.sol";

contract SimpleLogic {

    address immutable simpleStorage;

    constructor(address _simpleStorage) {
        simpleStorage = _simpleStorage;
    }

    function firstFunction(address _address) public {
        SimpleStorage(simpleStorage).setAccount1(address(_address));
    }

    function secondFunction(uint256 _value) public {
        SimpleStorage(simpleStorage).setCount1(_value);
    }

    function thirdFunction(uint256 _value) public {
        SimpleStorage(simpleStorage).setCount2(_value);
    }

}