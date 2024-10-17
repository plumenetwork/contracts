// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Test } from "forge-std/Test.sol";

import { SmartWallet } from "../src/SmartWallet.sol";
import { IAssetVault } from "../src/interfaces/IAssetVault.sol";
import { ISmartWallet } from "../src/interfaces/ISmartWallet.sol";
import { AssetToken } from "../src/token/AssetToken.sol";

contract AssetVaultTest is Test {

    IAssetVault public assetVault;
    AssetToken public assetToken;

    uint256 initialSupply = 1_000_000;

    address OWNER;
    address USER1;
    address USER2;
    address constant USER3 = address(0xDEAD);

    function setUp() public {
        OWNER = address(new SmartWallet());
        USER1 = address(new SmartWallet());
        USER2 = address(new SmartWallet());

        vm.startPrank(OWNER);

        ISmartWallet(OWNER).deployAssetVault();
        assetVault = ISmartWallet(OWNER).getAssetVault();
        assertNotEq(address(assetVault), address(0));

        // Setup mock AssetToken
        assetToken = new AssetToken(
            OWNER, // Address of the owner
            "AssetToken", // Name of the token
            "AT", // Symbol of the token
            ERC20(address(0)), // ERC20 currency token
            18, // Decimals for the asset token
            "uri://asset", // Token URI
            initialSupply, // Initial supply of AssetToken
            1_000_000, // Total value of all AssetTokens
            false // Disable whitelist
        );

        vm.stopPrank();
    }
    /*
    /// @dev This test fails if getBalanceAvailable uses high-level calls
    function test_noSmartWallets() public view {
        assertEq(assetToken.getBalanceAvailable(USER3), 0);
    }
    */
    // /// @dev Test accepting yield allowance

    function test_acceptYieldAllowance() public {
        // OWNER updates allowance for USER1
        vm.startPrank(OWNER);
        assetVault.updateYieldAllowance(assetToken, USER1, 300_000, block.timestamp + 30 days);

        assertEq(assetVault.getBalanceLocked(assetToken), 0);
        assertEq(assetToken.getBalanceAvailable(OWNER), 1_000_000);
        assertEq(assetToken.balanceOf(OWNER), 1_000_000);
        vm.stopPrank();

        // USER1 accepts the yield allowance
        vm.startPrank(USER1);
        assetVault.acceptYieldAllowance(assetToken, 300_000, block.timestamp + 30 days);

        assertEq(assetVault.getBalanceLocked(assetToken), 300_000);
        assertEq(assetToken.getBalanceAvailable(OWNER), 700_000);
        assertEq(assetToken.balanceOf(OWNER), 1_000_000);
        vm.stopPrank();
    }

    /// @dev Test accepting yield allowance with multiple holders
    function test_acceptYieldAllowanceMultiple() public {
        // OWNER updates allowance for USER1
        vm.prank(OWNER);
        assetVault.updateYieldAllowance(assetToken, USER1, 500_000, block.timestamp + 30 days);

        // OWNER updates allowance for USER2
        vm.prank(OWNER);
        assetVault.updateYieldAllowance(assetToken, USER2, 300_000, block.timestamp + 30 days);

        // USER1 accepts the yield allowance
        vm.prank(USER1);
        assetVault.acceptYieldAllowance(assetToken, 500_000, block.timestamp + 30 days);

        // USER2 accepts the yield allowance
        vm.prank(USER2);
        assetVault.acceptYieldAllowance(assetToken, 300_000, block.timestamp + 30 days);

        // Check locked balance after both allowances are accepted
        uint256 lockedBalance = assetVault.getBalanceLocked(assetToken);
        assertEq(lockedBalance, 800_000);
    }

}
