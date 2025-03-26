// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";

import { Empty } from "../src/Empty.sol";

contract EmptyTest is Test {

    // small hack to be excluded from coverage report
    function test() public { }

    function test_constructor() public {
        Empty empty = new Empty();
        assertNotEq(address(empty), address(0));
    }

}
