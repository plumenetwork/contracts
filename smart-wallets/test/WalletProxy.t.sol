// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";

import { SmartWallet } from "../src/SmartWallet.sol";
import { WalletFactory } from "../src/WalletFactory.sol";
import { WalletProxy } from "../src/WalletProxy.sol";
import { WalletProxyHarness } from "./harness/WalletProxyHarness.sol";

contract WalletProxyTest is Test {

    SmartWallet smartWallet;
    WalletFactory walletFactory;
    WalletProxy walletProxy;

    address constant OWNER = address(0x1234);

    function setUp() public {
        smartWallet = new SmartWallet();
        walletFactory = new WalletFactory(OWNER, smartWallet);
        walletProxy = new WalletProxy(walletFactory);
    }

    function test_constructor() public {
        WalletProxy newWalletProxy = new WalletProxy(walletFactory);
        assertEq(address(newWalletProxy.walletFactory()), address(walletFactory));
    }

    function test_implementation() public {
        WalletProxyHarness walletProxyHarness = new WalletProxyHarness(walletFactory);
        assertEq(address(walletProxyHarness.walletFactory()), address(walletFactory));
        assertEq(address(walletProxyHarness.exposed_implementation()), address(smartWallet));
    }

    function test_fallback() public {
        assertEq(address(walletProxy).balance, 0);
        payable(address(walletProxy)).transfer(1 ether);
        assertEq(address(walletProxy).balance, 1 ether);
    }

}
