// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Test } from "forge-std/Test.sol";

import { SmartWallet } from "../src/SmartWallet.sol";
import { WalletFactory } from "../src/WalletFactory.sol";
import { ISmartWallet } from "../src/interfaces/ISmartWallet.sol";

contract WalletFactoryTest is Test {

    SmartWallet smartWallet;
    WalletFactory walletFactory;

    address constant OWNER = address(0x1234);
    address constant USER1 = address(0xBEEF);

    function setUp() public {
        smartWallet = new SmartWallet();
        walletFactory = new WalletFactory(OWNER, smartWallet);
    }

    function test_constructor() public {
        WalletFactory newWalletFactory = new WalletFactory(OWNER, smartWallet);
        assertEq(newWalletFactory.OWNER(), OWNER);
        assertEq(address(newWalletFactory.smartWallet()), address(smartWallet));
    }

    function test_upgradeFail() public {
        ISmartWallet newImplementation = new SmartWallet();
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER1));
        vm.startPrank(USER1);
        walletFactory.upgrade(newImplementation);
        vm.stopPrank();
    }

    function test_upgrade() public {
        ISmartWallet newImplementation = new SmartWallet();
        vm.startPrank(OWNER);
        walletFactory.upgrade(newImplementation);
        vm.stopPrank();

        assertEq(walletFactory.OWNER(), OWNER);
        assertEq(address(walletFactory.smartWallet()), address(newImplementation));
    }

}
