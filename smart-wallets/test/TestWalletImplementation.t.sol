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

    // forge test  --ir-minimum
    address constant EMPTY_ADDRESS = 0x992F86ED5bb3A3587E8A9AE8CbbfEBFDeCC56e6b;
    address constant WALLET_FACTORY_ADDRESS = 0xcc26f2c04AfDcF9424dF51747A3DbaA94A34Edf9;
    address constant WALLET_PROXY_ADDRESS = 0x27Bd7B3E4EB459ccec21d3123a08bf1e5F589B7A;

    /* forge test
    address constant EMPTY_ADDRESS = 0x14E90063Fb9d5F9a2b0AB941679F105C1A597C7C;
    address constant WALLET_FACTORY_ADDRESS = 0xB8d58677E8A51C84a42a3F98971bA577d4ed1b88;
    address constant WALLET_PROXY_ADDRESS = 0x97C345048Fa4D59eCB03c3C67c9De1916Cbb0857;
    */

    TestWalletImplementation testWalletImplementation;

    // small hack to be excluded from coverage report
    function test() public { }

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
