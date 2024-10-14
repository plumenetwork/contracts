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

    /* forge coverage --ir-minimum */
    address constant EMPTY_ADDRESS = 0x4A8efF824790cB98cb65c8b62166965C128d49b6;
    address constant WALLET_FACTORY_ADDRESS = 0xc5499b361C2f5e69e924f7499f1F4A91e0874776;
    address constant WALLET_PROXY_ADDRESS = 0x829956583e233A4F969d358Ca0cA64661336a493;
   

    /* forge test
    address constant EMPTY_ADDRESS = 0x14E90063Fb9d5F9a2b0AB941679F105C1A597C7C;
    address constant WALLET_FACTORY_ADDRESS = 0xEebAC1B8e813FA641D8EFe967C8CD3DA68D2DF7a;
    address constant WALLET_PROXY_ADDRESS = 0x832C436692d2d0267Dd72e9577c82b5f2C96fb6f;
 */
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

        //assertEq(address(empty), EMPTY_ADDRESS);
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
