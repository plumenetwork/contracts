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

// Import ERC20 error interface for checking reverts
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract ArcTokenPurchaseTest is Test, IERC20Errors {

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
    uint256 public constant USDC_TO_SPEND_ALICE = 200e6; // Amount of USDC (6 decimals) Alice spends

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
        token.setRestrictionModule(TRANSFER_RESTRICTION_TYPE, address(whitelistModule));
        token.setRestrictionModule(YIELD_RESTRICTION_TYPE, address(yieldBlacklistModule));

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
        // Enable token sale (already done in setUp, but explicit is fine)
        purchase.enableToken(address(token), TOKENS_FOR_SALE, TOKEN_PRICE);

        // --- Alice's Purchase ---
        // Calculate how many ArcTokens Alice should get (ArcToken has 18 decimals)
        uint256 tokensToBuyAlice = (USDC_TO_SPEND_ALICE * 1e18) / TOKEN_PRICE;
        assertEq(tokensToBuyAlice, 2e18, "Calculation mismatch for Alice"); // 200e6 * 1e18 / 100e6 = 2e18

        // Approve purchase
        vm.prank(alice);
        purchaseToken.approve(address(purchase), USDC_TO_SPEND_ALICE);

        // Expect the correct event parameters (amount is now ArcToken base units)
        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true);
        emit PurchaseMade(alice, address(token), tokensToBuyAlice, USDC_TO_SPEND_ALICE); // tokensToBuyAlice already has
            // 18 decimals

        // Buy tokens - Alice spends 200 USDC (200e6)
        purchase.buy(address(token), USDC_TO_SPEND_ALICE);

        // Verify Alice's balances
        assertEq(token.balanceOf(alice), tokensToBuyAlice, "Alice ArcToken balance mismatch");
        assertEq(purchaseToken.balanceOf(alice), (1_000_000e6 - USDC_TO_SPEND_ALICE), "Alice USDC balance mismatch"); // Initial
            // mint was 1M USDC
        vm.stopPrank();

        // --- Buyer2's Purchase ---
        address buyer2 = makeAddr("buyer2");
        whitelistModule.addToWhitelist(buyer2); // Buyer needs to be whitelisted for ArcToken transfer

        uint256 tokensToBuyBuyer2 = 50e18; // Buyer2 wants 50 ArcTokens
        uint256 usdcToSpendBuyer2 = (tokensToBuyBuyer2 * TOKEN_PRICE) / 1e18;
        assertEq(usdcToSpendBuyer2, 5000e6, "Calculation mismatch for Buyer2"); // 50e18 * 100e6 / 1e18 = 5000e6

        purchaseToken.mint(buyer2, usdcToSpendBuyer2);

        vm.prank(buyer2);
        purchaseToken.approve(address(purchase), usdcToSpendBuyer2);

        vm.startPrank(buyer2);
        vm.expectEmit(true, true, true, true);
        emit PurchaseMade(buyer2, address(token), tokensToBuyBuyer2, usdcToSpendBuyer2);

        // Buyer2 buys 50 ArcTokens by spending 5000 USDC (5000e6)
        purchase.buy(address(token), usdcToSpendBuyer2);

        // Verify Buyer2's balances
        assertEq(token.balanceOf(buyer2), tokensToBuyBuyer2, "Buyer2 ArcToken balance mismatch");
        assertEq(purchaseToken.balanceOf(buyer2), 0, "Buyer2 USDC balance mismatch");

        // --- Verify Final State ---
        ArcTokenPurchase.TokenInfo memory finalInfo = purchase.getTokenInfo(address(token));
        uint256 totalTokensSold = tokensToBuyAlice + tokensToBuyBuyer2; // 2e18 + 50e18 = 52e18
        assertEq(finalInfo.amountSold, totalTokensSold, "Final amountSold mismatch");

        uint256 finalRemaining = finalInfo.totalAmountForSale - finalInfo.amountSold;
        assertEq(finalRemaining, TOKENS_FOR_SALE - totalTokensSold, "Final remaining mismatch"); // 500e18 - 52e18 =
            // 448e18

        assertEq(
            token.balanceOf(address(purchase)), TOKENS_FOR_SALE - totalTokensSold, "Contract final ArcToken balance"
        );
        assertEq(
            purchaseToken.balanceOf(address(purchase)),
            USDC_TO_SPEND_ALICE + usdcToSpendBuyer2,
            "Contract final USDC balance"
        );
        vm.stopPrank();
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
        // Expect the specific error instance with arguments
        vm.expectRevert(abi.encodeWithSelector(ArcTokenPurchase.NotTokenAdmin.selector, bob, address(token)));
        purchase.enableToken(address(token), TOKENS_FOR_SALE, TOKEN_PRICE);
    }

    function test_RevertWhen_BuyWithoutEnabling() public {
        // Disable the token first (it's enabled in setUp)
        vm.prank(owner); // Use owner who has ADMIN_ROLE on the token
        // Need a function to disable token sale. Let's assume we add disableToken().
        // purchase.disableToken(address(token));
        // For now, let's test by deploying a new token that isn't enabled
        ArcToken newToken = new ArcToken();
        newToken.initialize("New", "NEW", 0, address(yieldToken), owner, 18, address(router));

        vm.prank(alice);
        vm.expectRevert(ArcTokenPurchase.TokenNotEnabled.selector);
        purchase.buy(address(newToken), USDC_TO_SPEND_ALICE);
    }

    function test_RevertWhen_BuyWithoutApproval() public {
        purchase.enableToken(address(token), TOKENS_FOR_SALE, TOKEN_PRICE);

        vm.prank(alice);
        // Expect the specific error instance with arguments
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(purchase), 0, USDC_TO_SPEND_ALICE
            )
        );
        purchase.buy(address(token), USDC_TO_SPEND_ALICE);
    }

    function test_RevertWhen_BuyMoreThanAvailable() public {
        purchase.enableToken(address(token), TOKENS_FOR_SALE, TOKEN_PRICE);

        ArcTokenPurchase.TokenInfo memory info = purchase.getTokenInfo(address(token));

        // Calculate the USDC amount required to buy exactly one more base unit (1) than available

        uint256 tokensAvailable = info.totalAmountForSale - info.amountSold;
        uint256 usdcForAvailableTokens = (tokensAvailable * info.tokenPrice) / 1e18;
        uint256 usdcAmountToCauseRevert = usdcForAvailableTokens + 1; // Try to buy with 1 extra base unit of USDC

        vm.startPrank(alice);
        purchaseToken.approve(address(purchase), usdcAmountToCauseRevert); // Approve the amount that should cause
            // revert

        vm.expectRevert(ArcTokenPurchase.NotEnoughTokensForSale.selector);
        // Attempt to buy with the USDC amount calculated to be just over the limit
        purchase.buy(address(token), usdcAmountToCauseRevert);
        vm.stopPrank();
    }

    function test_RevertWhen_SetStorefrontConfigNonOwner() public {
        vm.prank(bob);
        // Expect the specific error instance with arguments
        vm.expectRevert(abi.encodeWithSelector(ArcTokenPurchase.NotTokenAdmin.selector, bob, address(token)));
        purchase.setStorefrontConfig(
            address(token), "test.arc", "Test Sale", "Description", "image.url", "#FFFFFF", "#000000", "logo.url", true
        );
    }

    // ============ Integration Tests ============

    function test_CompleteTokenSaleFlow() public {
        // Enable sale
        // Sale is already enabled in setUp

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
        uint256 alicePurchaseAmount = 30 * TOKEN_PRICE; // Buy 30 tokens worth of USDC
        purchase.buy(address(token), alicePurchaseAmount);

        // Second purchase
        uint256 buyer2PurchaseAmount = 50 * TOKEN_PRICE; // Buy 50 tokens worth of USDC
        vm.prank(buyer2);
        purchaseToken.approve(address(purchase), buyer2PurchaseAmount);
        vm.prank(buyer2);
        purchase.buy(address(token), buyer2PurchaseAmount);

        // Verify final state
        assertEq(token.balanceOf(alice), 30e18); // Assuming 1 token = 1e18
        assertEq(token.balanceOf(buyer2), 50e18);
        ArcTokenPurchase.TokenInfo memory finalInfo = purchase.getTokenInfo(address(token));
        uint256 finalRemaining = finalInfo.totalAmountForSale - finalInfo.amountSold;
        assertEq(finalRemaining, TOKENS_FOR_SALE - (30e18 + 50e18));
    }

}
