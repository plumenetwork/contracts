// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ArcToken } from "../src/ArcToken.sol";
import { ArcTokenPurchase } from "../src/ArcTokenPurchase.sol";
import { MockUSDC } from "../src/mock/MockUSDC.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

// Import necessary restriction contracts and interfaces
import { RestrictionsRouter } from "../src/restrictions/RestrictionsRouter.sol";
import { WhitelistRestrictions } from "../src/restrictions/WhitelistRestrictions.sol";
import { YieldBlacklistRestrictions } from "../src/restrictions/YieldBlacklistRestrictions.sol";

contract ArcTokenPurchaseTest is Test {

    ArcToken public token;
    ArcTokenPurchase public purchase;
    MockUSDC public purchaseToken;
    ERC20Mock public yieldToken; // For ArcToken itself

    // Infrastructure needed for ArcToken setup
    RestrictionsRouter public router;
    WhitelistRestrictions public whitelistModule;
    YieldBlacklistRestrictions public yieldBlacklistModule;

    address public owner;
    address public alice;
    address public bob;

    uint256 public constant INITIAL_SUPPLY = 1000e18;
    uint256 public constant TOKEN_PRICE = 100e6; // Price in USDC (6 decimals)
    uint256 public constant TOKENS_FOR_SALE = 500e18;
    uint256 public constant PURCHASE_AMOUNT = 200e6; // Amount of USDC to spend

    // Define module type constants matching ArcToken/Factory
    bytes32 public constant TRANSFER_RESTRICTION_TYPE = keccak256("TRANSFER_RESTRICTION");
    bytes32 public constant YIELD_RESTRICTION_TYPE = keccak256("YIELD_RESTRICTION");

    event PurchaseMade(address indexed buyer, address indexed tokenContract, uint256 amount, uint256 pricePaid);
    event TokenSaleEnabled(address indexed tokenContract, uint256 numberOfTokens, uint256 tokenPrice);
    event StorefrontConfigSet(address indexed tokenContract, string domain);
    event PurchaseTokenUpdated(address indexed newPurchaseToken);

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // Deploy mock tokens (using default constructor due to potential compiler issue)
        purchaseToken = new MockUSDC();

        yieldToken = new ERC20Mock();

        // --- Deploy Infrastructure for ArcToken ---
        router = new RestrictionsRouter();
        router.initialize(owner);
        whitelistModule = new WhitelistRestrictions();
        whitelistModule.initialize(owner);
        yieldBlacklistModule = new YieldBlacklistRestrictions();
        yieldBlacklistModule.initialize(owner);

        // --- Deploy ArcToken ---
        token = new ArcToken();
        token.initialize(
            "Test ArcToken", // name_
            "TAT", // symbol_
            INITIAL_SUPPLY,
            address(yieldToken),
            owner, // initial holder
            18, // decimals
            address(router) // router address
        );

        // --- Link Modules to Token ---
        token.setSpecificRestrictionModule(TRANSFER_RESTRICTION_TYPE, address(whitelistModule));
        token.setSpecificRestrictionModule(YIELD_RESTRICTION_TYPE, address(yieldBlacklistModule));

        // --- Deploy ArcTokenPurchase ---
        purchase = new ArcTokenPurchase();
        purchase.initialize(address(this)); // Initialize with admin

        // --- Setup Initial State ---
        // Whitelist relevant addresses in the Whitelist Module
        whitelistModule.addToWhitelist(owner);
        whitelistModule.addToWhitelist(alice);
        whitelistModule.addToWhitelist(bob);
        whitelistModule.addToWhitelist(address(purchase)); // IMPORTANT: Whitelist purchase contract

        // Mint purchase tokens to users
        purchaseToken.mint(alice, 1_000_000e6);
        purchaseToken.mint(bob, 1_000_000e6);

        // Note: Initial supply already minted to owner during ArcToken initialize

        // Set purchase token in ArcTokenPurchase
        purchase.setPurchaseToken(address(purchaseToken));

        // Owner transfers tokens TO the purchase contract
        token.transfer(address(purchase), TOKENS_FOR_SALE);

        // Now enable sale - purchase contract checks its own balance
        purchase.enableToken(address(token), TOKENS_FOR_SALE, TOKEN_PRICE);
    }

    // ============ Initialization Tests ============

    function test_Initialization() public {
        assertEq(address(purchase.purchaseToken()), address(purchaseToken));
    }

    // ============ Sale Management Tests ============

    function test_EnableToken() public {
        vm.expectEmit(true, true, true, true);
        emit TokenSaleEnabled(address(token), TOKENS_FOR_SALE, TOKEN_PRICE);

        purchase.enableToken(address(token), TOKENS_FOR_SALE, TOKEN_PRICE);

        ArcTokenPurchase.TokenInfo memory info = purchase.getTokenInfo(address(token));
        uint256 remainingForSale = info.totalAmountForSale - info.amountSold;

        assertTrue(info.isEnabled);
        assertEq(remainingForSale, TOKENS_FOR_SALE); // Check remaining based on struct fields
        assertEq(info.tokenPrice, TOKEN_PRICE);
    }

    function test_Buy() public {
        // Enable token sale
        purchase.enableToken(address(token), TOKENS_FOR_SALE, TOKEN_PRICE);

        // Approve purchase
        vm.prank(alice);
        purchaseToken.approve(address(purchase), TOKEN_PRICE * PURCHASE_AMOUNT);

        // Buy tokens
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit PurchaseMade(alice, address(token), PURCHASE_AMOUNT, TOKEN_PRICE * PURCHASE_AMOUNT);

        purchase.buy(address(token), PURCHASE_AMOUNT);

        // Verify balances
        assertEq(token.balanceOf(alice), PURCHASE_AMOUNT);
        assertEq(purchaseToken.balanceOf(alice), TOKEN_PRICE * (100 - PURCHASE_AMOUNT));

        // Verify final state
        address buyer2 = makeAddr("buyer2");
        whitelistModule.addToWhitelist(buyer2);
        purchaseToken.mint(buyer2, TOKEN_PRICE * 50);

        vm.prank(buyer2);
        purchaseToken.approve(address(purchase), TOKEN_PRICE * 50);
        vm.prank(buyer2);
        purchase.buy(address(token), 50);

        ArcTokenPurchase.TokenInfo memory finalInfo = purchase.getTokenInfo(address(token));
        uint256 finalRemaining = finalInfo.totalAmountForSale - finalInfo.amountSold;
        assertEq(finalRemaining, TOKENS_FOR_SALE - 80);
    }

    // ============ Storefront Configuration Tests ============

    function test_SetStorefrontConfig() public {
        vm.expectEmit(true, true, true, true);
        emit StorefrontConfigSet(address(token), "test.arc");

        purchase.setStorefrontConfig(
            address(token), "test.arc", "Test Sale", "Description", "image.url", "#FFFFFF", "#000000", "logo.url", true
        );

        ArcTokenPurchase.StorefrontConfig memory config = purchase.getStorefrontConfig(address(token));
        assertEq(config.domain, "test.arc");
        assertEq(config.title, "Test Sale");
        assertTrue(config.showPlumeBadge);
    }

    // ============ Purchase Token Management Tests ============

    function test_UpdatePurchaseToken() public {
        address newPurchaseToken = address(new ERC20Mock());

        vm.expectEmit(true, true, true, true);
        emit PurchaseTokenUpdated(newPurchaseToken);

        purchase.setPurchaseToken(newPurchaseToken);
        assertEq(address(purchase.purchaseToken()), newPurchaseToken);
    }

    // ============ Error Cases Tests ============

    function test_RevertWhen_EnableTokenNonOwner() public {
        vm.prank(bob);
        vm.expectRevert("Only token owner can call this function");
        purchase.enableToken(address(token), TOKENS_FOR_SALE, TOKEN_PRICE);
    }

    function test_RevertWhen_BuyWithoutEnabling() public {
        vm.prank(alice);
        vm.expectRevert("Token is not enabled for purchase");
        purchase.buy(address(token), PURCHASE_AMOUNT);
    }

    function test_RevertWhen_BuyWithoutApproval() public {
        purchase.enableToken(address(token), TOKENS_FOR_SALE, TOKEN_PRICE);

        vm.prank(alice);
        vm.expectRevert("ERC20: insufficient allowance");
        purchase.buy(address(token), PURCHASE_AMOUNT);
    }

    function test_RevertWhen_BuyMoreThanAvailable() public {
        purchase.enableToken(address(token), TOKENS_FOR_SALE, TOKEN_PRICE);

        vm.prank(alice);
        purchaseToken.approve(address(purchase), TOKEN_PRICE * (TOKENS_FOR_SALE + 1));

        vm.prank(alice);
        vm.expectRevert("Not enough tokens available for sale");
        purchase.buy(address(token), TOKENS_FOR_SALE + 1);
    }

    function test_RevertWhen_SetStorefrontConfigNonOwner() public {
        vm.prank(bob);
        vm.expectRevert("Only token owner can call this function");
        purchase.setStorefrontConfig(
            address(token), "test.arc", "Test Sale", "Description", "image.url", "#FFFFFF", "#000000", "logo.url", true
        );
    }

    // ============ Integration Tests ============

    function test_CompleteTokenSaleFlow() public {
        // Enable sale
        purchase.enableToken(address(token), TOKENS_FOR_SALE, TOKEN_PRICE);

        // Configure storefront
        purchase.setStorefrontConfig(
            address(token), "test.arc", "Test Sale", "Description", "image.url", "#FFFFFF", "#000000", "logo.url", true
        );

        // Multiple buyers
        address buyer2 = makeAddr("buyer2");
        whitelistModule.addToWhitelist(buyer2);
        purchaseToken.mint(buyer2, TOKEN_PRICE * 50);

        // First purchase
        vm.prank(alice);
        purchaseToken.approve(address(purchase), TOKEN_PRICE * 30);
        vm.prank(alice);
        purchase.buy(address(token), 30);

        // Second purchase
        vm.prank(buyer2);
        purchaseToken.approve(address(purchase), TOKEN_PRICE * 50);
        vm.prank(buyer2);
        purchase.buy(address(token), 50);

        // Verify final state
        assertEq(token.balanceOf(alice), 30);
        assertEq(token.balanceOf(buyer2), 50);
        ArcTokenPurchase.TokenInfo memory finalInfo = purchase.getTokenInfo(address(token));
        uint256 finalRemaining = finalInfo.totalAmountForSale - finalInfo.amountSold;
        assertEq(finalRemaining, TOKENS_FOR_SALE - 80);
    }

}
