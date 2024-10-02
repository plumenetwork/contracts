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

    address owner = address(0x1234);
    address user1 = address(0xBEEF);

    function setUp() public {
        smartWallet = new SmartWallet();
        walletFactory = new WalletFactory(owner, smartWallet);
    }

    function test_constructor() public {
        WalletFactory newWalletFactory = new WalletFactory(owner, smartWallet);
        assertEq(newWalletFactory.owner(), owner);
        assertEq(address(newWalletFactory.smartWallet()), address(smartWallet));
    }

    function test_upgradeFail() public {
        ISmartWallet newImplementation = new SmartWallet();
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vm.startPrank(user1);
        walletFactory.upgrade(newImplementation);
        vm.stopPrank();
    }

    function test_upgrade() public {
        ISmartWallet newImplementation = new SmartWallet();
        vm.startPrank(owner);
        walletFactory.upgrade(newImplementation);
        vm.stopPrank();

        assertEq(walletFactory.owner(), owner);
        assertEq(address(walletFactory.smartWallet()), address(newImplementation));
    }

}
