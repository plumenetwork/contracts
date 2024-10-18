// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";

import { Empty } from "../src/Empty.sol";

contract EmptyTest is Test {

    function test_constructor() public {
        Empty empty = new Empty();
        assertNotEq(address(empty), address(0));
    }

}
