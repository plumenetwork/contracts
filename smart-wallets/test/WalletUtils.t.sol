// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";

import { WalletUtils } from "../src/WalletUtils.sol";
import { WalletUtilsHarness } from "./harness/WalletUtilsHarness.sol";

contract WalletUtilsTest is Test {

    WalletUtilsHarness walletUtils;

    address private constant OWNER = address(0x1234);

    // small hack to be excluded from coverage report
    function test() public { }

    function setUp() public {
        walletUtils = new WalletUtilsHarness();
    }

    function test_onlyWalletFail() public {
        vm.expectRevert(abi.encodeWithSelector(WalletUtils.UnauthorizedCall.selector, OWNER));
        vm.startPrank(OWNER);
        walletUtils.onlyWalletFunction();
        vm.stopPrank();
    }

    function test_onlyWallet() public {
        walletUtils.callOnlyWalletFunction();
    }

}
