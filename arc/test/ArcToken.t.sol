// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ArcToken } from "../src/ArcToken.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

// Import necessary restriction contracts and interfaces

import { IRestrictionsRouter } from "../src/restrictions/IRestrictionsRouter.sol";

import { ITransferRestrictions } from "../src/restrictions/ITransferRestrictions.sol";
import { IYieldRestrictions } from "../src/restrictions/IYieldRestrictions.sol";
import { RestrictionsRouter } from "../src/restrictions/RestrictionsRouter.sol";
import { WhitelistRestrictions } from "../src/restrictions/WhitelistRestrictions.sol";
import { YieldBlacklistRestrictions } from "../src/restrictions/YieldBlacklistRestrictions.sol";

contract ArcTokenTest is Test {

    ArcToken public token;
    ERC20Mock public yieldToken;
    RestrictionsRouter public router;
    WhitelistRestrictions public whitelistModule;
    YieldBlacklistRestrictions public yieldBlacklistModule;

    address public owner;
    address public alice;
    address public bob;
    address public charlie;

    uint256 public constant INITIAL_SUPPLY = 1000e18;
    uint256 public constant ASSET_VALUATION = 1_000_000e18;
    uint256 public constant TOKEN_ISSUE_PRICE = 100e18;
    uint256 public constant ACCRUAL_RATE_PER_SECOND = 6_342_013_888_889; // ~0.054795% daily
    uint256 public constant TOTAL_TOKEN_OFFERING = 10_000e18;
    uint256 public constant YIELD_AMOUNT = 1000e18;

    event YieldDistributed(uint256 amount, address indexed token);

    // Define module type constants matching ArcToken
    bytes32 public constant TRANSFER_RESTRICTION_TYPE = keccak256("TRANSFER_RESTRICTION");
    bytes32 public constant YIELD_RESTRICTION_TYPE = keccak256("YIELD_RESTRICTION");

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");

        // Deploy mock yield token
        yieldToken = new ERC20Mock();
        yieldToken.mint(owner, 1_000_000e18);

        // --- Deploy Infrastructure ---
        // 1. Deploy Router
        router = new RestrictionsRouter();
        router.initialize(owner); // Initialize router with owner as admin

        // 2. Deploy Per-Token Restriction Modules
        whitelistModule = new WhitelistRestrictions();
        whitelistModule.initialize(owner); // Owner manages whitelist

        yieldBlacklistModule = new YieldBlacklistRestrictions();
        yieldBlacklistModule.initialize(owner); // Owner manages yield blacklist

        // 3. Register Module Types in Router (optional for this test, but good practice)
        // router.registerModuleType(TRANSFER_RESTRICTION_TYPE, false, address(0));
        // router.registerModuleType(YIELD_RESTRICTION_TYPE, false, address(0));

        // --- Deploy ArcToken ---
        token = new ArcToken();
        token.initialize(
            "Arc Token",
            "ARC",
            INITIAL_SUPPLY,
            address(yieldToken),
            owner, // initial holder
            18, // decimals
            address(router) // router address
        );

        // --- Link Modules to Token ---
        token.setSpecificRestrictionModule(TRANSFER_RESTRICTION_TYPE, address(whitelistModule));
        token.setSpecificRestrictionModule(YIELD_RESTRICTION_TYPE, address(yieldBlacklistModule));

        // --- Setup Initial State ---
        // Whitelist addresses using the Whitelist Module
        whitelistModule.addToWhitelist(owner);
        whitelistModule.addToWhitelist(alice);
        whitelistModule.addToWhitelist(bob);
        whitelistModule.addToWhitelist(charlie);

        // Now mint tokens after linking modules and whitelisting
        // Note: Initial supply is already minted to owner in initialize
        // vm.prank(owner); // Not needed as owner deploys
        token.transfer(alice, 100e18);
    }

    // ============ Initialization Tests ============

    function test_Initialization() public {
        assertEq(token.name(), "Arc Token");
        assertEq(token.symbol(), "ARC");
        assertEq(token.decimals(), 18);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - 100e18);
        assertEq(token.balanceOf(alice), 100e18);
        assertTrue(whitelistModule.isWhitelisted(alice)); // Check via module
    }

    // ============ Whitelist Tests (Now target WhitelistRestrictions module) ============

    function test_AddToWhitelist() public {
        address newUser = makeAddr("newUser");
        // Assuming 'owner' has MANAGER_ROLE in WhitelistRestrictions (granted in initialize)
        whitelistModule.addToWhitelist(newUser);
        assertTrue(whitelistModule.isWhitelisted(newUser));
    }

    function test_RemoveFromWhitelist() public {
        whitelistModule.removeFromWhitelist(alice);
        assertFalse(whitelistModule.isWhitelisted(alice));
    }

    function testFail_AddToWhitelistNonOwner() public {
        vm.prank(alice); // Alice doesn't have MANAGER_ROLE on whitelistModule
        vm.expectRevert(); // Expect AccessControl revert
        whitelistModule.addToWhitelist(bob);
    }

    // ============ Transfer Tests (Token level, checks restrictions) ============

    function test_TransferBetweenWhitelisted() public {
        vm.prank(alice);
        token.transfer(bob, 50e18);
        assertEq(token.balanceOf(alice), 50e18);
        assertEq(token.balanceOf(bob), 50e18);
    }

    function testFail_TransferToNonWhitelisted() public {
        address nonWhitelisted = makeAddr("nonWhitelisted");
        vm.prank(alice);
        vm.expectRevert(ArcToken.TransferRestricted.selector);
        token.transfer(nonWhitelisted, 50e18);
    }

    // ============ Yield Distribution Tests ============

    function test_YieldDistribution() public {
        // Approve and distribute yield
        yieldToken.approve(address(token), YIELD_AMOUNT);

        vm.expectEmit(true, true, true, true); // Check event from ArcToken
        emit YieldDistributed(YIELD_AMOUNT, address(yieldToken));

        token.distributeYield(YIELD_AMOUNT);

        // Calculate expected distribution (owner and alice are holders)
        uint256 totalEffectiveSupply = token.balanceOf(owner) + token.balanceOf(alice);
        uint256 ownerExpected = (YIELD_AMOUNT * token.balanceOf(owner)) / totalEffectiveSupply;
        uint256 aliceExpected = YIELD_AMOUNT - ownerExpected; // Alice gets remainder

        assertEq(yieldToken.balanceOf(owner), ownerExpected);
        assertEq(yieldToken.balanceOf(alice), aliceExpected);
    }

    function test_YieldDistribution_WithBlacklist() public {
        // Blacklist alice using the yield blacklist module
        yieldBlacklistModule.addToBlacklist(alice);
        assertFalse(yieldBlacklistModule.isYieldAllowed(alice));
        assertTrue(yieldBlacklistModule.isYieldAllowed(owner));

        yieldToken.approve(address(token), YIELD_AMOUNT);
        vm.expectEmit(true, true, true, true);
        // Only owner should receive yield, so distributed amount is YIELD_AMOUNT
        emit YieldDistributed(YIELD_AMOUNT, address(yieldToken));
        token.distributeYield(YIELD_AMOUNT);

        // Owner should receive all yield
        assertEq(yieldToken.balanceOf(owner), YIELD_AMOUNT);
        assertEq(yieldToken.balanceOf(alice), 0); // Alice is blacklisted

        // Un-blacklist alice
        yieldBlacklistModule.removeFromBlacklist(alice);
        assertTrue(yieldBlacklistModule.isYieldAllowed(alice));
    }

    /*
    // ============ Tests for Removed Features ============

    // Tests removed as features moved out of ArcToken or changed significantly:
    // - test_ClaimableYieldDistribution (Claiming logic removed)
    // - test_RedemptionPriceCalculation (Financial metrics removed)
    // - test_YieldHistory (Yield history removed)
    // - test_RevertWhen_ClaimYieldWithoutDistribution (Claiming logic removed)
    // - test_RevertWhen_SetZeroIssuePrice (Token pricing removed)

    */

    // ============ Error Cases Tests ============

    function test_RevertWhen_DistributeYieldWithoutAllowance() public {
        vm.expectRevert("ERC20: insufficient allowance");
        token.distributeYield(YIELD_AMOUNT);
    }

    function test_RevertWhen_SetInvalidYieldToken() public {
        vm.expectRevert("InvalidYieldTokenAddress()");
        token.setYieldToken(address(0));
    }

}
