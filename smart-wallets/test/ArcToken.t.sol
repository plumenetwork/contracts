// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {ArcToken} from "../src/token/ArcToken.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract ArcTokenTest is Test {
    ArcToken public token;
    ERC20Mock public yieldToken;
    
    address public owner;
    address public alice;
    address public bob;
    address public charlie;
    
    uint256 public constant INITIAL_SUPPLY = 1000e18;
    uint256 public constant ASSET_VALUATION = 1000000e18;
    uint256 public constant TOKEN_ISSUE_PRICE = 100e18;
    uint256 public constant ACCRUAL_RATE_PER_SECOND = 6342013888889; // ~0.054795% daily
    uint256 public constant TOTAL_TOKEN_OFFERING = 10000e18;
    uint256 public constant YIELD_AMOUNT = 1000e18;

    event YieldDistributed(uint256 amount, bool direct);
    event YieldClaimed(address indexed account, uint256 amount);
    event TokenPurchased(address indexed buyer, uint256 amount, uint256 timestamp);

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");

        // Deploy mock yield token
        yieldToken = new ERC20Mock();
        yieldToken.mint(owner, 1000000e18);

        // Deploy ArcToken
        token = new ArcToken();
        token.initialize(
            "Arc Token",
            "ARC",
            "Test Asset",
            ASSET_VALUATION,
            INITIAL_SUPPLY,
            address(yieldToken),
            TOKEN_ISSUE_PRICE,
            ACCRUAL_RATE_PER_SECOND,
            TOTAL_TOKEN_OFFERING
        );

        // Setup initial state - whitelist addresses BEFORE any transfers
        token.addToWhitelist(address(this));  // Whitelist owner first
        token.addToWhitelist(alice);
        token.addToWhitelist(bob);
        token.addToWhitelist(charlie);
        
        // Now mint tokens after whitelisting
        token.mint(address(this), INITIAL_SUPPLY);  // Mint to owner first
        token.transfer(alice, 100e18);  // Then transfer to alice
    }

    // ============ Initialization Tests ============

    function test_Initialization() public {
        assertEq(token.name(), "Arc Token");
        assertEq(token.symbol(), "ARC");
        assertEq(token.decimals(), 18);
        assertEq(token.balanceOf(alice), 100e18);
        assertTrue(token.isWhitelisted(alice));
    }

    // ============ Whitelist Tests ============

    function test_AddToWhitelist() public {
        address newUser = makeAddr("newUser");
        token.addToWhitelist(newUser);
        assertTrue(token.isWhitelisted(newUser));
    }

    function test_RemoveFromWhitelist() public {
        token.removeFromWhitelist(alice);
        assertFalse(token.isWhitelisted(alice));
    }

    function testFail_AddToWhitelistNonOwner() public {
        vm.prank(alice);
        token.addToWhitelist(bob);
    }

    // ============ Transfer Tests ============

    function test_TransferBetweenWhitelisted() public {
        vm.prank(alice);
        token.transfer(bob, 50e18);
        assertEq(token.balanceOf(alice), 50e18);
        assertEq(token.balanceOf(bob), 50e18);
    }

    function testFail_TransferToNonWhitelisted() public {
        address nonWhitelisted = makeAddr("nonWhitelisted");
        vm.prank(alice);
        token.transfer(nonWhitelisted, 50e18);
    }

    // ============ Yield Distribution Tests ============

    function test_DirectYieldDistribution() public {
        // Setup direct distribution
        token.setYieldDistributionMethod(true);
        
        // Approve and distribute yield
        yieldToken.approve(address(token), YIELD_AMOUNT);
        
        vm.expectEmit(true, true, true, true);
        emit YieldDistributed(YIELD_AMOUNT, true);
        
        token.distributeYield(YIELD_AMOUNT);
        
        // Alice should receive all yield (as only holder)
        assertEq(yieldToken.balanceOf(alice), YIELD_AMOUNT);
    }

    function test_ClaimableYieldDistribution() public {
        // Keep default claimable distribution
        yieldToken.approve(address(token), YIELD_AMOUNT);
        
        vm.expectEmit(true, true, true, true);
        emit YieldDistributed(YIELD_AMOUNT, false);
        
        token.distributeYield(YIELD_AMOUNT);
        
        // Check unclaimed yield
        assertEq(token.getUnclaimedYield(alice), YIELD_AMOUNT);
        
        // Claim yield
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit YieldClaimed(alice, YIELD_AMOUNT);
        
        token.claimYield();
        
        assertEq(yieldToken.balanceOf(alice), YIELD_AMOUNT);
        assertEq(token.getUnclaimedYield(alice), 0);
    }

    // ============ Financial Metrics Tests ============

    function test_RedemptionPriceCalculation() public {
        // Fast forward 1 day
        vm.warp(block.timestamp + 1 days);
        
        (
            uint256 tokenIssuePrice,
            uint256 accrualRatePerSecond,
            uint256 totalTokenOffering,
            uint256 currentRedemptionPrice,
            uint256 secondsHeld
        ) = token.getTokenMetrics(alice);
        
        assertEq(tokenIssuePrice, TOKEN_ISSUE_PRICE);
        assertEq(accrualRatePerSecond, ACCRUAL_RATE_PER_SECOND);
        assertEq(totalTokenOffering, TOTAL_TOKEN_OFFERING);
        assertEq(secondsHeld, 1 days);
        
        // Verify redemption price includes accrual
        uint256 expectedAccrual = (TOKEN_ISSUE_PRICE * ACCRUAL_RATE_PER_SECOND * 1 days) / 1e18;
        assertEq(currentRedemptionPrice, TOKEN_ISSUE_PRICE + expectedAccrual);
    }

    // ============ Yield History Tests ============

    function test_YieldHistory() public {
        yieldToken.approve(address(token), YIELD_AMOUNT * 2);
        
        // First distribution
        token.distributeYield(YIELD_AMOUNT);
        
        // Second distribution after some time
        vm.warp(block.timestamp + 1 days);
        token.distributeYield(YIELD_AMOUNT);
        
        (uint256[] memory dates, uint256[] memory amounts) = token.getYieldHistory();
        
        assertEq(dates.length, 2);
        assertEq(amounts.length, 2);
        assertEq(amounts[0], YIELD_AMOUNT);
        assertEq(amounts[1], YIELD_AMOUNT);
        assertEq(dates[1] - dates[0], 1 days);
    }

    // ============ Error Cases Tests ============

    function test_RevertWhen_DistributeYieldWithoutAllowance() public {
        vm.expectRevert("ERC20: insufficient allowance");
        token.distributeYield(YIELD_AMOUNT);
    }

    function test_RevertWhen_ClaimYieldWithoutDistribution() public {
        vm.prank(alice);
        vm.expectRevert("NoYieldToClaim()");
        token.claimYield();
    }

    function test_RevertWhen_SetInvalidYieldToken() public {
        vm.expectRevert("InvalidYieldTokenAddress()");
        token.setYieldToken(address(0));
    }

    function test_RevertWhen_SetZeroIssuePrice() public {
        vm.expectRevert("IssuePriceMustBePositive()");
        token.updateTokenPrice(0);
    }
} 