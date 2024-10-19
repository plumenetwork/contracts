// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { SmartWallet } from "../src/SmartWallet.sol";
import { IAssetVault } from "../src/interfaces/IAssetVault.sol";
import { ISmartWallet } from "../src/interfaces/ISmartWallet.sol";
import { AssetToken } from "../src/token/AssetToken.sol";

contract MockERC20 is ERC20 {

    constructor(string memory name, string memory symbol) ERC20(name, symbol) { }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

}

contract AssetVaultTest is Test {

    IAssetVault public assetVault;
    AssetToken public assetToken;
    MockERC20 public yieldCurrency;

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

        // Setup mock YieldCurrency
        yieldCurrency = new MockERC20("YieldCurrency", "YC");

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

    /// @dev This test fails if getBalanceAvailable uses high-level calls
    function test_noSmartWallets() public view {
        assertEq(assetToken.getBalanceAvailable(USER3), 0);
    }

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

    function test_updateYieldAllowance() public {
        vm.startPrank(OWNER);
        assetVault.updateYieldAllowance(assetToken, USER1, 300_000, block.timestamp + 30 days);
        vm.stopPrank();

        vm.startPrank(USER1);
        assetVault.acceptYieldAllowance(assetToken, 300_000, block.timestamp + 30 days);
        vm.stopPrank();

        vm.startPrank(OWNER);
        assetVault.updateYieldAllowance(assetToken, USER1, 500_000, block.timestamp + 60 days);
        vm.stopPrank();

        vm.startPrank(USER1);
        assetVault.acceptYieldAllowance(assetToken, 200_000, block.timestamp + 60 days);
        vm.stopPrank();

        assertEq(assetVault.getBalanceLocked(assetToken), 500_000);
    }

    function test_updateYieldAllowanceUnauthorized() public {
        vm.expectRevert();
        vm.prank(USER1);
        assetVault.updateYieldAllowance(assetToken, USER2, 300_000, block.timestamp + 30 days);
    }

    function test_acceptYieldAllowanceInsufficientAllowance() public {
        vm.prank(OWNER);
        assetVault.updateYieldAllowance(assetToken, USER1, 300_000, block.timestamp + 30 days);

        vm.expectRevert();
        vm.prank(USER1);
        assetVault.acceptYieldAllowance(assetToken, 400_000, block.timestamp + 30 days);
    }

    function test_acceptYieldAllowanceExpired() public {
        vm.prank(OWNER);
        assetVault.updateYieldAllowance(assetToken, USER1, 300_000, block.timestamp + 30 days);

        vm.warp(block.timestamp + 31 days);

        vm.expectRevert();
        vm.prank(USER1);
        assetVault.acceptYieldAllowance(assetToken, 300_000, block.timestamp - 1 days);
    }
    /*
    function test_renounceYieldDistribution() public {
    uint256 startTime = block.timestamp;
    uint256 duration = 30 days;
    uint256 expirationTime = startTime + duration;

    vm.startPrank(OWNER);
    assetVault.updateYieldAllowance(assetToken, USER1, 300_000, expirationTime);
    vm.stopPrank();

    vm.startPrank(USER1);
    assetVault.acceptYieldAllowance(assetToken, 300_000, expirationTime);

    // Advance time by half the duration
    vm.warp(startTime + duration / 2);

    // Check the locked balance before renouncing
    uint256 balanceLockedBefore = assetVault.getBalanceLocked(assetToken);
    console.log("Balance locked before:", balanceLockedBefore);

    // Try to renounce part of the yield distribution
    uint256 amountToRenounce = 100_000;
    uint256 amountRenounced = assetVault.renounceYieldDistribution(assetToken, amountToRenounce, expirationTime);

    // Check the locked balance after renouncing
    uint256 balanceLockedAfter = assetVault.getBalanceLocked(assetToken);
    console.log("Balance locked after:", balanceLockedAfter);

    assertEq(amountRenounced, amountToRenounce, "Incorrect amount renounced");
    assertEq(balanceLockedAfter, balanceLockedBefore - amountToRenounce, "Incorrect balance locked after renouncing");

    vm.stopPrank();
    }
    */

    function test_renounceYieldDistributionInsufficientDistribution() public {
        vm.startPrank(OWNER);
        assetVault.updateYieldAllowance(assetToken, USER1, 300_000, block.timestamp + 30 days);
        vm.stopPrank();

        vm.startPrank(USER1);
        assetVault.acceptYieldAllowance(assetToken, 300_000, block.timestamp + 30 days);
        vm.expectRevert();
        assetVault.renounceYieldDistribution(assetToken, 400_000, block.timestamp + 30 days);
        vm.stopPrank();
    }

    function test_clearYieldDistributions() public {
        vm.startPrank(OWNER);
        assetVault.updateYieldAllowance(assetToken, USER1, 300_000, block.timestamp + 30 days);
        vm.stopPrank();

        vm.startPrank(USER1);
        assetVault.acceptYieldAllowance(assetToken, 300_000, block.timestamp + 30 days);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);

        vm.prank(OWNER);
        assetVault.clearYieldDistributions(assetToken);

        assertEq(assetVault.getBalanceLocked(assetToken), 0);
    }

    function test_redistributeYield() public {
        vm.startPrank(OWNER);
        assetVault.updateYieldAllowance(assetToken, USER1, 300_000, block.timestamp + 30 days);
        assetVault.updateYieldAllowance(assetToken, USER2, 200_000, block.timestamp + 30 days);
        vm.stopPrank();

        vm.prank(USER1);
        assetVault.acceptYieldAllowance(assetToken, 300_000, block.timestamp + 30 days);

        vm.prank(USER2);
        assetVault.acceptYieldAllowance(assetToken, 200_000, block.timestamp + 30 days);

        // Mock yield generation
        yieldCurrency.mint(address(assetToken), 1000);

        vm.prank(OWNER);
        assetVault.redistributeYield(assetToken, yieldCurrency, 1000);

        // Check yield distribution (this will depend on your implementation)
        // You might need to add getter functions to check the distributed yield
    }

    function test_redistributeYieldUnauthorized() public {
        vm.expectRevert();
        vm.prank(USER1);
        assetVault.redistributeYield(assetToken, yieldCurrency, 1000);
    }

}
