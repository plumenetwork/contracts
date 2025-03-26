// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

contract MockUserWallet {

    // small hack to be excluded from coverage report
    function test() public { }

    function customFunction() external pure returns (bool) {
        return true;
    }

}
