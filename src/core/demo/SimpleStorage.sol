// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract SimpleStorage {

    uint256 public count1;
    uint256 public count2;

    address public account1;
    address public account2;

    function setAccount1(address _account1) public {
        account1 = _account1;
    }

    function setAccount2(address _account2) public {
        account2 = _account2;
    }

    function setCount1(uint256 _count1) public {
        count1 = _count1;
    }

    function setCount2(uint256 _count2) public {
        count2 = _count2;
    }
    
}