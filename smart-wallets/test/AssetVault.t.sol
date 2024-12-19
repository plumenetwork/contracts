// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { SmartWallet } from "../src/SmartWallet.sol";

import { WalletUtils } from "../src/WalletUtils.sol";
import { AssetVault } from "../src/extensions/AssetVault.sol";
import { IAssetToken } from "../src/interfaces/IAssetToken.sol";
import { IAssetVault } from "../src/interfaces/IAssetVault.sol";
import { ISmartWallet } from "../src/interfaces/ISmartWallet.sol";
import { AssetToken } from "../src/token/AssetToken.sol";

import { MockERC20 } from "../src/mocks/MockERC20.sol";

contract AssetVaultTest is Test {

    IAssetVault public assetVault;
    AssetToken public assetToken;
    MockERC20 public yieldCurrency;

    uint256 initialSupply = 1_000_000;

    address OWNER;
    address USER1;
    address USER2;
    address constant USER3 = address(0xF62849F9A0B5Bf2913b396098F7c7019b51A820a);

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

    function testUpdateYieldAllowanceZeroAddress() public {
        vm.startPrank(OWNER);

        // Test zero asset token
        vm.expectRevert(AssetVault.ZeroAddress.selector);
        assetVault.updateYieldAllowance(IAssetToken(address(0)), USER1, 100, block.timestamp + 1 days);

        // Test zero beneficiary
        vm.expectRevert(AssetVault.ZeroAddress.selector);
        assetVault.updateYieldAllowance(assetToken, address(0), 100, block.timestamp + 1 days);

        vm.stopPrank();
    }

    function testUpdateYieldAllowanceZeroAmount() public {
        vm.startPrank(OWNER);
        vm.expectRevert(AssetVault.ZeroAmount.selector);
        assetVault.updateYieldAllowance(assetToken, USER1, 0, block.timestamp + 1 days);
        vm.stopPrank();
    }

    function testUpdateYieldAllowanceInvalidExpiration() public {
        vm.startPrank(OWNER);
        uint256 expiration = block.timestamp; // Same as current time
        vm.expectRevert(abi.encodeWithSelector(AssetVault.InvalidExpiration.selector, expiration, block.timestamp));
        assetVault.updateYieldAllowance(assetToken, USER1, 100, expiration);
        vm.stopPrank();
    }

    function testRedistributeYieldExpired() public {
        // Setup yield distribution
        vm.startPrank(OWNER);
        assetVault.updateYieldAllowance(assetToken, USER1, 100, block.timestamp + 1 days);
        vm.stopPrank();

        vm.prank(USER1);
        assetVault.acceptYieldAllowance(assetToken, 100, block.timestamp + 1 days);

        // Warp past expiration
        vm.warp(block.timestamp + 2 days);

        // Mock yield generation
        yieldCurrency.mint(address(assetToken), 1000);

        vm.prank(OWNER);
        assetVault.redistributeYield(assetToken, yieldCurrency, 1000);
        // Should skip distribution as it's expired
        // Could verify with an event check
    }

    function testAcceptYieldAllowanceZeroAmount() public {
        vm.startPrank(OWNER);
        assetVault.updateYieldAllowance(assetToken, USER1, 100, block.timestamp + 1 days);
        vm.stopPrank();

        vm.startPrank(USER1);
        vm.expectRevert(AssetVault.ZeroAmount.selector);
        assetVault.acceptYieldAllowance(assetToken, 0, block.timestamp + 1 days);
        vm.stopPrank();
    }

    function testAcceptYieldAllowanceMismatchedExpiration() public {
        uint256 correctExpiration = block.timestamp + 1 days;
        uint256 wrongExpiration = block.timestamp + 2 days;

        vm.startPrank(OWNER);
        assetVault.updateYieldAllowance(assetToken, USER1, 100, correctExpiration);
        vm.stopPrank();

        vm.startPrank(USER1);
        vm.expectRevert(
            abi.encodeWithSelector(AssetVault.MismatchedExpiration.selector, wrongExpiration, correctExpiration)
        );
        assetVault.acceptYieldAllowance(assetToken, 100, wrongExpiration);
        vm.stopPrank();
    }

    function testAcceptYieldAllowanceInsufficientBalance() public {
        vm.startPrank(OWNER);
        // Transfer all tokens away from owner
        assetToken.transfer(USER2, assetToken.balanceOf(OWNER));
        assetVault.updateYieldAllowance(assetToken, USER1, 100, block.timestamp + 1 days);
        vm.stopPrank();

        vm.startPrank(USER1);
        vm.expectRevert(abi.encodeWithSelector(AssetVault.InsufficientBalance.selector, assetToken, 100));
        assetVault.acceptYieldAllowance(assetToken, 100, block.timestamp + 1 days);
        vm.stopPrank();
    }

    function testClearYieldDistributionsEmpty() public {
        vm.prank(OWNER);
        assetVault.clearYieldDistributions(assetToken);
        // Should not revert
    }

    // Add these test functions to AssetVaultTest contract
    /*
    function test_redistributeYieldFailedTransfer() public {
    // Setup initial allowance and acceptance
    vm.startPrank(OWNER);
    assetVault.updateYieldAllowance(assetToken, USER1, 300_000, block.timestamp + 30 days);
    vm.stopPrank();

    vm.prank(USER1);
    assetVault.acceptYieldAllowance(assetToken, 300_000, block.timestamp + 30 days);

    // Mock a failed transfer by using a malicious smart wallet
    address maliciousWallet = address(new MockFailingSmartWallet());
    vm.prank(OWNER);
    assetVault.updateYieldAllowance(assetToken, maliciousWallet, 200_000, block.timestamp + 30 days);
    
    vm.prank(maliciousWallet);
    assetVault.acceptYieldAllowance(assetToken, 200_000, block.timestamp + 30 days);

    yieldCurrency.mint(address(assetToken), 1000);

    vm.prank(OWNER);
    vm.expectRevert(abi.encodeWithSelector(WalletUtils.SmartWalletCallFailed.selector, OWNER));
    assetVault.redistributeYield(assetToken, yieldCurrency, 1000);
    }
    */
    function test_acceptYieldAllowanceExistingDistribution() public {
        // Setup initial distribution
        vm.startPrank(OWNER);
        assetVault.updateYieldAllowance(assetToken, USER1, 500_000, block.timestamp + 30 days);
        vm.stopPrank();

        vm.startPrank(USER1);
        // Accept first part
        assetVault.acceptYieldAllowance(assetToken, 300_000, block.timestamp + 30 days);

        // Accept second part with same expiration - should add to existing distribution
        assetVault.acceptYieldAllowance(assetToken, 200_000, block.timestamp + 30 days);
        vm.stopPrank();

        assertEq(assetVault.getBalanceLocked(assetToken), 500_000);
    }

    function debugYieldDistributionState(IAssetToken token, address beneficiary, uint256 expiration) public view {
        console.log("=== Debug Yield Distribution State ===");
        console.log("Token:", address(token));
        console.log("Beneficiary:", beneficiary);
        console.log("Expiration:", expiration);
        console.log("Total Balance Locked:", assetVault.getBalanceLocked(token));
        console.log("Block Timestamp:", block.timestamp);

        (uint256 allowanceAmount, uint256 allowanceExpiration) = assetVault.getYieldAllowance(token, beneficiary);
        console.log("Current Allowance Amount:", allowanceAmount);
        console.log("Current Allowance Expiration:", allowanceExpiration);

        (uint256 distributionAmount, bool found) = assetVault.getYieldDistribution(token, beneficiary, expiration);
        console.log("Distribution Amount:", distributionAmount);
        console.log("Distribution Found:", found);

        console.log("=== End Debug ===");
    }

    function test_renounceYieldDistributionPartial() public {
        uint256 allowanceAmount = 300_000;
        uint256 renounceAmount = 100_000;
        uint256 expirationTime = block.timestamp + 30 days;

        console.log("Initial setup:");
        console.log("OWNER:", OWNER);
        console.log("USER3:", USER3);
        console.log("AssetToken:", address(assetToken));
        console.log("AssetVault:", address(assetVault));

        // Setup: OWNER mints tokens and approves AssetVault
        vm.startPrank(OWNER);
        assetToken.mint(OWNER, allowanceAmount);
        assetToken.approve(address(assetVault), allowanceAmount);

        console.log("\nBefore updateYieldAllowance:");
        debugYieldDistributionState(assetToken, USER3, expirationTime);

        // Create allowance for USER3
        assetVault.updateYieldAllowance(assetToken, USER3, allowanceAmount, expirationTime);

        console.log("\nAfter updateYieldAllowance:");
        debugYieldDistributionState(assetToken, USER3, expirationTime);
        vm.stopPrank();

        // USER3 accepts the allowance
        vm.startPrank(USER3);

        assetVault.acceptYieldAllowance(assetToken, allowanceAmount, expirationTime);

        console.log("\nAfter acceptYieldAllowance:");
        debugYieldDistributionState(assetToken, USER3, expirationTime);

        // Verify initial state
        uint256 initialLocked = assetVault.getBalanceLocked(assetToken);
        assertEq(initialLocked, allowanceAmount, "Initial locked amount incorrect");

        console.log("\nBefore renounceYieldDistribution:");
        debugYieldDistributionState(assetToken, USER3, expirationTime);

        // Try to renounce part of it
        assetVault.renounceYieldDistribution(assetToken, renounceAmount, expirationTime);

        console.log("\nAfter renounceYieldDistribution:");
        debugYieldDistributionState(assetToken, USER3, expirationTime);

        // Verify final state
        uint256 finalLocked = assetVault.getBalanceLocked(assetToken);
        assertEq(finalLocked, allowanceAmount - renounceAmount, "Final locked amount incorrect");
        vm.stopPrank();
    }

    function test_clearYieldDistributionsMultiple() public {
        // Setup multiple distributions with different expirations
        vm.startPrank(OWNER);
        assetVault.updateYieldAllowance(assetToken, USER1, 300_000, block.timestamp + 30 days);
        assetVault.updateYieldAllowance(assetToken, USER2, 200_000, block.timestamp + 15 days);
        vm.stopPrank();

        vm.startPrank(USER1);
        assetVault.acceptYieldAllowance(assetToken, 300_000, block.timestamp + 30 days);
        vm.stopPrank();

        vm.startPrank(USER2);
        assetVault.acceptYieldAllowance(assetToken, 200_000, block.timestamp + 15 days);
        vm.stopPrank();

        // Warp time to expire USER2's distribution but not USER1's
        vm.warp(block.timestamp + 20 days);

        vm.prank(OWNER);
        assetVault.clearYieldDistributions(assetToken);

        // Should only have USER1's distribution remaining
        assertEq(assetVault.getBalanceLocked(assetToken), 300_000);
    }

}
