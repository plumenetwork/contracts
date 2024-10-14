// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import { SignedOperations } from "../src/extensions/SignedOperations.sol";
import { SmartWallet } from "../src/SmartWallet.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AssetVault } from "../src/extensions/AssetVault.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IAssetToken} from '../src/interfaces/IAssetToken.sol';
contract SmartWalletTest is Test {
    SmartWallet smartWallet;
    ERC20Mock currencyToken;
    address owner;
    address beneficiary;

    function setUp() public {
        owner = address(this);
        beneficiary = address(0x123);

        smartWallet = new SmartWallet();

        // Deploy a mock ERC20 token
        currencyToken = new ERC20Mock();
    }

    function testDeployAssetVault() public {
        // Deploy the AssetVault
        smartWallet.deployAssetVault();

        // Check that the vault is deployed
        assertTrue(address(smartWallet.getAssetVault()) != address(0));
    }

    function testRevertAssetVaultAlreadyExists() public {
        // Deploy the AssetVault first
        smartWallet.deployAssetVault();

        // Try deploying again, expect revert
        vm.expectRevert(abi.encodeWithSelector(SmartWallet.AssetVaultAlreadyExists.selector, smartWallet.getAssetVault()));
        smartWallet.deployAssetVault();
    }

    function testTransferYieldRevertUnauthorized() public {
        // Deploy an AssetVault
        smartWallet.deployAssetVault();

        vm.expectRevert(abi.encodeWithSelector(SmartWallet.UnauthorizedAssetVault.selector, address(this)));
        smartWallet.transferYield(IAssetToken(address(0)), beneficiary, currencyToken, 100);
    }

/*
    function testReceiveYieldSuccess() public {
        // Transfer currencyToken from beneficiary to wallet
        currencyToken.mint(beneficiary, 100 ether);
        vm.prank(beneficiary);
        currencyToken.approve(address(smartWallet), 100 ether);

        smartWallet.receiveYield(IAssetToken(address(0)), currencyToken, 100 ether);
        assertEq(currencyToken.balanceOf(address(smartWallet)), 100 ether);
    }

    function testUpgradeUserWallet() public {
        address newWallet = address(0x456);

        // Upgrade to a new user wallet
        smartWallet.upgrade(newWallet);

        // Ensure the upgrade event was emitted
        vm.expectEmit(true, true, true, true);
        emit SmartWallet.UserWalletUpgraded(newWallet);

        //assertEq(smartWallet._implementation(), newWallet);
    }
    */
}
