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

    address constant ADMIN_ADDRESS = 0xDE1509CC56D740997c70E1661BA687e950B4a241;
    bytes32 constant DEPLOY_SALT = keccak256("PlumeSmartWallets");

    /* forge coverage --ir-minimum
    address constant EMPTY_ADDRESS = 0x0Ab1C3d2cCB7c314666185b317900a614e516feB;
    address constant WALLET_FACTORY_ADDRESS = 0xf0533fC1183cf6006b0dCF943AB011c8aD58459D;
    address constant WALLET_PROXY_ADDRESS = 0xaefD16513881Ad9Ad869bf2Bd028F4D441FF2B40;
    */

    /* forge test */
    address constant EMPTY_ADDRESS = 0x14E90063Fb9d5F9a2b0AB941679F105C1A597C7C;
    address constant WALLET_FACTORY_ADDRESS = 0x5F26233a11D5148aeEa71d54D9D102992F8d73E2;
    address constant WALLET_PROXY_ADDRESS = 0xCd49AC437b7e0b73D403e2fF339429330166feE0;

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

        assertEq(address(empty), EMPTY_ADDRESS);
        assertEq(address(walletFactory), WALLET_FACTORY_ADDRESS);
        assertEq(address(walletProxy), WALLET_PROXY_ADDRESS);

        SmartWallet smartWallet = new SmartWallet();
        vm.expectEmit(false, false, false, true, address(walletFactory));
        emit WalletFactory.Upgraded(smartWallet);
        walletFactory.upgrade(smartWallet);
        assertEq(address(walletFactory.smartWallet()), address(smartWallet));

        // Must use low-level calls for smart wallets
        (bool success,) =
            ADMIN_ADDRESS.call(abi.encodeWithSelector(ISmartWallet.upgrade.selector, address(testWalletImplementation)));
        assertEq(success, true);

        vm.stopPrank();
    }

}
