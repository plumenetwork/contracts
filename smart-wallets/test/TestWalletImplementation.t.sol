// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";

import { Empty } from "../src/Empty.sol";

import { SmartWallet } from "../src/SmartWallet.sol";
import { TestWalletImplementation } from "../src/TestWalletImplementation.sol";
import { WalletFactory } from "../src/WalletFactory.sol";
import { WalletProxy } from "../src/WalletProxy.sol";
import { ISmartWallet } from "../src/interfaces/ISmartWallet.sol";

contract TestWalletImplementationTest is Test {

    address private constant ADMIN_ADDRESS = 0xDE1509CC56D740997c70E1661BA687e950B4a241;
    bytes32 private constant DEPLOY_SALT = keccak256("PlumeSmartWallets");
    address private constant EMPTY_ADDRESS = 0x14E90063Fb9d5F9a2b0AB941679F105C1A597C7C;
    address private constant WALLET_FACTORY_ADDRESS = 0xB2eF86dCEeB95B4f11EB26c77a296fc40CB62062;
    address private constant WALLET_PROXY_ADDRESS = 0x19edC0A2cA9fC66F0e3922ac78bE5928E96B84bC;

    TestWalletImplementation testWalletImplementation;

    function setUp() public {
        testWalletImplementation = new TestWalletImplementation();
    }

    function test_setters() public {
        assertEq(testWalletImplementation.value(), 0);
        testWalletImplementation.setValue(123);
        assertEq(testWalletImplementation.value(), 123);
    }

    function test_upgrade() public {
        vm.startPrank(ADMIN_ADDRESS);

        Empty empty = new Empty{ salt: DEPLOY_SALT }();
        WalletFactory walletFactory =
            new WalletFactory{ salt: DEPLOY_SALT }(ADMIN_ADDRESS, ISmartWallet(address(empty)));
        WalletProxy walletProxy = new WalletProxy{ salt: DEPLOY_SALT }(walletFactory);
        SmartWallet smartWallet = new SmartWallet();

        assertEq(address(empty), EMPTY_ADDRESS);
        assertEq(address(walletFactory), WALLET_FACTORY_ADDRESS);
        assertEq(address(walletProxy), WALLET_PROXY_ADDRESS);

        walletFactory.upgrade(smartWallet);
        assertEq(address(walletFactory.smartWallet()), address(smartWallet));

        /* TODO: Reverts because Foundry can't simulate smart wallets
        SmartWallet(payable(ADMIN_ADDRESS)).upgrade(address(testWalletImplementation));
        */

        vm.stopPrank();
    }

}
