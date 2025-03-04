// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {ArcToken} from "../src/token/ArcToken.sol";
import {ArcTokenPurchase} from "../src/token/ArcTokenPurchase.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract ArcTokenPurchaseTest is Test {
    ArcTokenPurchase public purchase;
    ArcToken public token;
    ERC20Mock public purchaseToken;
    ERC20Mock public yieldToken;
    
    address public owner;
    address public buyer;
    address public admin;
    
    uint256 public constant TOKEN_PRICE = 100e18;
    uint256 public constant TOKENS_FOR_SALE = 1000e18;
    uint256 public constant PURCHASE_AMOUNT = 10e18;
    
    event PurchaseMade(
        address indexed buyer,
        address indexed tokenContract,
        uint256 amount,
        uint256 pricePaid
    );
    event TokenSaleEnabled(
        address indexed tokenContract,
        uint256 numberOfTokens,
        uint256 tokenPrice
    );
    event StorefrontConfigSet(address indexed tokenContract, string domain);
    event PurchaseTokenUpdated(address indexed newPurchaseToken);

    function setUp() public {
        owner = address(this);
        buyer = makeAddr("buyer");
        admin = makeAddr("admin");

        // Deploy tokens
        purchaseToken = new ERC20Mock();
        yieldToken = new ERC20Mock();
        
        // Deploy ArcToken
        token = new ArcToken();
        token.initialize(
            "Arc Token",
            "ARC",
            "Test Asset",
            1000000e18,
            10000e18,
            address(yieldToken),
            100e18,
            6342013888889,
            10000e18
        );

        // Deploy purchase contract
        purchase = new ArcTokenPurchase(address(this));

        // Setup initial state - whitelist addresses BEFORE any transfers
        token.addToWhitelist(address(this));  // Whitelist owner first
        token.addToWhitelist(address(purchase));
        token.addToWhitelist(buyer);
        
        // Now mint tokens after whitelisting
        token.mint(address(this), TOKENS_FOR_SALE);  // Mint to owner first
        token.approve(address(purchase), TOKENS_FOR_SALE);
        
        // Set purchase token
        purchase.setPurchaseToken(address(purchaseToken));
        
        // Fund buyer
        purchaseToken.mint(buyer, TOKEN_PRICE * 100);
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
        
        (bool isEnabled, uint256 price, uint256 tokensAvailable) = purchase.tokenInfo(address(token));
        assertTrue(isEnabled);
        assertEq(tokensAvailable, TOKENS_FOR_SALE);
        assertEq(price, TOKEN_PRICE);
    }

    function test_Buy() public {
        // Enable token sale
        purchase.enableToken(address(token), TOKENS_FOR_SALE, TOKEN_PRICE);
        
        // Approve purchase
        vm.prank(buyer);
        purchaseToken.approve(address(purchase), TOKEN_PRICE * PURCHASE_AMOUNT);
        
        // Buy tokens
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit PurchaseMade(buyer, address(token), PURCHASE_AMOUNT, TOKEN_PRICE * PURCHASE_AMOUNT);
        
        purchase.buy(address(token), PURCHASE_AMOUNT);
        
        // Verify balances
        assertEq(token.balanceOf(buyer), PURCHASE_AMOUNT);
        assertEq(purchaseToken.balanceOf(buyer), TOKEN_PRICE * (100 - PURCHASE_AMOUNT));
    }

    // ============ Storefront Configuration Tests ============

    function test_SetStorefrontConfig() public {
        vm.expectEmit(true, true, true, true);
        emit StorefrontConfigSet(address(token), "test.arc");
        
        purchase.setStorefrontConfig(
            address(token),
            "test.arc",
            "Test Sale",
            "Description",
            "image.url",
            "#FFFFFF",
            "#000000",
            "logo.url",
            true
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
        vm.prank(buyer);
        vm.expectRevert("Only token owner can call this function");
        purchase.enableToken(address(token), TOKENS_FOR_SALE, TOKEN_PRICE);
    }

    function test_RevertWhen_BuyWithoutEnabling() public {
        vm.prank(buyer);
        vm.expectRevert("Token is not enabled for purchase");
        purchase.buy(address(token), PURCHASE_AMOUNT);
    }

    function test_RevertWhen_BuyWithoutApproval() public {
        purchase.enableToken(address(token), TOKENS_FOR_SALE, TOKEN_PRICE);
        
        vm.prank(buyer);
        vm.expectRevert("ERC20: insufficient allowance");
        purchase.buy(address(token), PURCHASE_AMOUNT);
    }

    function test_RevertWhen_BuyMoreThanAvailable() public {
        purchase.enableToken(address(token), TOKENS_FOR_SALE, TOKEN_PRICE);
        
        vm.prank(buyer);
        purchaseToken.approve(address(purchase), TOKEN_PRICE * (TOKENS_FOR_SALE + 1));
        
        vm.prank(buyer);
        vm.expectRevert("Not enough tokens available for sale");
        purchase.buy(address(token), TOKENS_FOR_SALE + 1);
    }

    function test_RevertWhen_SetStorefrontConfigNonOwner() public {
        vm.prank(buyer);
        vm.expectRevert("Only token owner can call this function");
        purchase.setStorefrontConfig(
            address(token),
            "test.arc",
            "Test Sale",
            "Description",
            "image.url",
            "#FFFFFF",
            "#000000",
            "logo.url",
            true
        );
    }

    // ============ Integration Tests ============

    function test_CompleteTokenSaleFlow() public {
        // Enable sale
        purchase.enableToken(address(token), TOKENS_FOR_SALE, TOKEN_PRICE);
        
        // Configure storefront
        purchase.setStorefrontConfig(
            address(token),
            "test.arc",
            "Test Sale",
            "Description",
            "image.url",
            "#FFFFFF",
            "#000000",
            "logo.url",
            true
        );
        
        // Multiple buyers
        address buyer2 = makeAddr("buyer2");
        token.addToWhitelist(buyer2);
        purchaseToken.mint(buyer2, TOKEN_PRICE * 50);
        
        // First purchase
        vm.prank(buyer);
        purchaseToken.approve(address(purchase), TOKEN_PRICE * 30);
        vm.prank(buyer);
        purchase.buy(address(token), 30);
        
        // Second purchase
        vm.prank(buyer2);
        purchaseToken.approve(address(purchase), TOKEN_PRICE * 50);
        vm.prank(buyer2);
        purchase.buy(address(token), 50);
        
        // Verify final state
        assertEq(token.balanceOf(buyer), 30);
        assertEq(token.balanceOf(buyer2), 50);
        (, , uint256 remaining) = purchase.tokenInfo(address(token));
        assertEq(remaining, TOKENS_FOR_SALE - 80);
    }
} 