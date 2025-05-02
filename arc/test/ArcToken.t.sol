// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ArcToken } from "../src/ArcToken.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

// Import necessary restriction contracts and interfaces

import { IRestrictionsRouter } from "../src/restrictions/IRestrictionsRouter.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { ITransferRestrictions } from "../src/restrictions/ITransferRestrictions.sol";
import { IYieldRestrictions } from "../src/restrictions/IYieldRestrictions.sol";
import { RestrictionsRouter } from "../src/restrictions/RestrictionsRouter.sol";
import { WhitelistRestrictions } from "../src/restrictions/WhitelistRestrictions.sol";
import { YieldBlacklistRestrictions } from "../src/restrictions/YieldBlacklistRestrictions.sol";

contract ArcTokenTest is Test, IERC20Errors {

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
        yieldToken.mint(owner, 1_000_000e18); // Initial balance for owner is 1e24

        // --- Deploy Infrastructure ---
        // 1. Deploy Router
        router = new RestrictionsRouter();
        router.initialize(owner); // Initialize router with owner as admin

        // 2. Deploy Per-Token Restriction Modules
        whitelistModule = new WhitelistRestrictions();
        whitelistModule.initialize(owner); // transfersAllowed is set to TRUE here by default

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

        // --- Grant MINTER_ROLE to owner (test contract) for minting in tests ---
        token.grantRole(token.MINTER_ROLE(), owner);

        // --- Setup Initial State ---
        // Whitelist addresses using the Whitelist Module
        whitelistModule.addToWhitelist(owner);
        whitelistModule.addToWhitelist(alice);
        whitelistModule.addToWhitelist(bob);
        whitelistModule.addToWhitelist(charlie);

        // Now mint tokens after linking modules and whitelisting
        // Note: Initial supply is already minted to owner in initialize
        token.transfer(alice, 100e18); // Owner: 900e18, Alice: 100e18
    }

    // ============ Initialization Tests ============

    function test_Initialization() public {
        assertEq(token.name(), "Arc Token");
        assertEq(token.symbol(), "ARC");
        assertEq(token.decimals(), 18);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - 100e18);
        assertEq(token.balanceOf(alice), 100e18);
        assertTrue(whitelistModule.isWhitelisted(alice)); // Check via module
        assertTrue(whitelistModule.transfersAllowed()); // Check default is true
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

    function test_RevertWhen_WhitelistAddNotAdmin() public {
        vm.prank(alice); // Alice doesn't have MANAGER_ROLE on whitelistModule
        vm.expectRevert(); // Expect AccessControl revert
        whitelistModule.addToWhitelist(bob);
    }

    // ============ Transfer Tests (Token level, checks restrictions) ============

    function test_TransferBetweenWhitelisted() public {
        // Transfers are allowed by default
        assertTrue(whitelistModule.transfersAllowed());
        vm.prank(alice);
        token.transfer(bob, 50e18);
        assertEq(token.balanceOf(alice), 50e18);
        assertEq(token.balanceOf(bob), 50e18);
    }

    // Test transferring between two non-whitelisted addresses when transfers are restricted
    function test_RevertWhen_TransferBetweenNonWhitelisted() public {
        address nonWhitelisted1 = makeAddr("nonWhitelisted1");
        address nonWhitelisted2 = makeAddr("nonWhitelisted2");

        // 1. Mint tokens to nonWhitelisted1 (requires whitelisting temporarily or transfersAllowed=true)
        // Since transfersAllowed is true by default, minting works without whitelisting nonWhitelisted1.
        token.mint(nonWhitelisted1, 50e18);

        // 2. Explicitly restrict transfers
        whitelistModule.setTransfersAllowed(false);
        assertFalse(whitelistModule.transfersAllowed());

        // 3. Ensure neither party is whitelisted
        assertFalse(whitelistModule.isWhitelisted(nonWhitelisted1));
        assertFalse(whitelistModule.isWhitelisted(nonWhitelisted2));

        // 4. Attempt transfer and expect revert
        vm.prank(nonWhitelisted1);
        vm.expectRevert(ArcToken.TransferRestricted.selector);
        token.transfer(nonWhitelisted2, 10e18);

        // 5. (Optional) Set transfers back to allowed for other tests
        whitelistModule.setTransfersAllowed(true);
    }

    // ============ Yield Distribution Tests ============

    function test_YieldDistribution() public {
        // Approve and distribute yield
        yieldToken.approve(address(token), YIELD_AMOUNT);

        vm.expectEmit(true, true, true, true); // Check event from ArcToken
        emit YieldDistributed(YIELD_AMOUNT, address(yieldToken));

        uint256 ownerInitialYieldBalance = yieldToken.balanceOf(owner); // Should be 1e24
        uint256 aliceInitialYieldBalance = yieldToken.balanceOf(alice); // Should be 0

        token.distributeYield(YIELD_AMOUNT);

        // Calculate expected distribution (owner and alice are holders)
        uint256 totalEffectiveSupply = token.balanceOf(owner) + token.balanceOf(alice); // 900e18 + 100e18 = 1000e18
        uint256 ownerExpectedShare = (YIELD_AMOUNT * token.balanceOf(owner)) / totalEffectiveSupply; // (1e21 * 900e18)
            // / 1000e18 = 9e20
        uint256 aliceExpectedShare = YIELD_AMOUNT - ownerExpectedShare; // 1e21 - 9e20 = 1e20

        // Owner's balance = initial - amount_sent_to_contract + share_received
        assertEq(
            yieldToken.balanceOf(owner),
            ownerInitialYieldBalance - YIELD_AMOUNT + ownerExpectedShare,
            "Owner final balance mismatch"
        );
        // Alice's balance = initial + share_received
        assertEq(
            yieldToken.balanceOf(alice), aliceInitialYieldBalance + aliceExpectedShare, "Alice final balance mismatch"
        );
    }

    function test_YieldDistribution_WithBlacklist() public {
        // Blacklist alice using the yield blacklist module
        yieldBlacklistModule.addToBlacklist(alice);
        assertFalse(yieldBlacklistModule.isYieldAllowed(alice));
        assertTrue(yieldBlacklistModule.isYieldAllowed(owner));

        uint256 ownerInitialYieldBalance = yieldToken.balanceOf(owner); // 1e24
        uint256 aliceInitialYieldBalance = yieldToken.balanceOf(alice); // 0

        yieldToken.approve(address(token), YIELD_AMOUNT);
        vm.expectEmit(true, true, true, true);
        // Only owner should receive yield, so distributed amount is YIELD_AMOUNT
        emit YieldDistributed(YIELD_AMOUNT, address(yieldToken));
        token.distributeYield(YIELD_AMOUNT);

        // Owner should receive all yield back
        // Owner's balance = initial - amount_sent_to_contract + share_received (which is YIELD_AMOUNT)
        assertEq(
            yieldToken.balanceOf(owner),
            ownerInitialYieldBalance - YIELD_AMOUNT + YIELD_AMOUNT,
            "Owner final balance mismatch (blacklist)"
        );
        assertEq(yieldToken.balanceOf(alice), aliceInitialYieldBalance, "Alice final balance mismatch (blacklist)"); // Alice
            // is blacklisted, should receive 0

        // Un-blacklist alice
        yieldBlacklistModule.removeFromBlacklist(alice);
        assertTrue(yieldBlacklistModule.isYieldAllowed(alice));
    }

    // ============ Error Cases Tests ============

    function test_RevertWhen_DistributeYieldWithoutAllowance() public {
        // Expect the specific custom error with arguments: spender, allowance, needed
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(token), // spender is the token contract trying to pull funds
                0, // current allowance is 0
                YIELD_AMOUNT // amount needed
            )
        );
        token.distributeYield(YIELD_AMOUNT);
    }

    function test_RevertWhen_SetInvalidYieldToken() public {
        vm.expectRevert(ArcToken.InvalidYieldTokenAddress.selector); // Use selector comparison
        token.setYieldToken(address(0));
    }

}
