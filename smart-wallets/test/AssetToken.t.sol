// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { SmartWallet } from "../src/SmartWallet.sol";

import { WalletFactory } from "../src/WalletFactory.sol";
import { WalletProxy } from "../src/WalletProxy.sol";
import { IAssetVault } from "../src/interfaces/IAssetVault.sol";
import { MockSmartWallet } from "../src/mocks/MockSmartWallet.sol";
import "../src/token/AssetToken.sol";
import "../src/token/YieldDistributionToken.sol";

import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
//import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { Empty } from "../src/Empty.sol";
import { TestWalletImplementation } from "../src/TestWalletImplementation.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract Contract { }

contract AssetTokenTest is Test {

    address constant ADMIN_ADDRESS = 0xDE1509CC56D740997c70E1661BA687e950B4a241;
    bytes32 constant DEPLOY_SALT = keccak256("PlumeSmartWallets");

    AssetToken public assetToken;
    AssetToken public assetTokenWhitelisted;
    ERC20 public currencyToken;
    SmartWallet public mockSmartWallet;
    SmartWallet public testWalletImplementation;
    WalletProxy public walletProxy;
    //address public owner;
    address owner = makeAddr("alice");

    address public user1;
    address public user2;
    address public walletProxyAddress;

    function setUp() public {
        owner = ADMIN_ADDRESS;
        user1 = address(0x1);
        user2 = address(0x2);

        vm.startPrank(owner);

        // Deploy CurrencyToken
        currencyToken = new ERC20Mock();
        console.log("CurrencyToken deployed at:", address(currencyToken));

        // Deploy Empty contract
        Empty empty = new Empty{ salt: DEPLOY_SALT }();

        // Deploy WalletFactory
        WalletFactory walletFactory = new WalletFactory{ salt: DEPLOY_SALT }(owner, ISmartWallet(address(empty)));
        console.log("WalletFactory deployed at:", address(walletFactory));

        // Deploy WalletProxy
        //walletProxy = new WalletProxy{ salt: DEPLOY_SALT }(walletFactory);
        walletProxy = new WalletProxy(walletFactory);
        console.log("WalletProxy deployed at:", address(walletProxy));

        // Deploy TestWalletImplementation
        //        testWalletImplementation = new TestWalletImplementation();
        testWalletImplementation = new SmartWallet();
        console.log("TestWalletImplementation deployed at:", address(testWalletImplementation));

        // Upgrade WalletFactory to use TestWalletImplementation
        walletFactory.upgrade(ISmartWallet(address(testWalletImplementation)));
        console.log("walletFactory deployed at:", address(testWalletImplementation));

        assetToken = new AssetToken();
        assetToken.initialize(
            address(testWalletImplementation), // The SmartWallet is the owner
            "Asset Token",
            "AT",
            currencyToken,
            18,
            "http://example.com/token",
            10_000 * 10 ** 18, // initialSupply
            10_000 * 10 ** 18, // totalValue
            false // Whitelist enabled
        );

        // Deploy and initialize whitelisted AssetToken
        assetTokenWhitelisted = new AssetToken();
        assetTokenWhitelisted.initialize(
            address(testWalletImplementation), // The SmartWallet is the owner
            "Whitelisted Asset Token",
            "WAT",
            currencyToken,
            18,
            "http://example.com/token",
            0, // initialSupply
            10_000 * 10 ** 18, // totalValue
            true // Whitelist enabled
        );
        console.log("AssetToken deployed at:", address(assetTokenWhitelisted));

        vm.stopPrank();
    }

    // Helper function to call _implementation() on WalletProxy
    function test_Initialization() public {
        console.log("Starting testInitialization");
        require(address(assetToken) != address(0), "AssetToken not deployed");

        assertEq(assetToken.name(), "Asset Token", "Name mismatch");
        assertEq(assetToken.symbol(), "AT", "Symbol mismatch");
        assertEq(assetToken.decimals(), 18, "Decimals mismatch");
        assertEq(assetToken.totalSupply(), 10_000 * 10 ** 18, "Total supply mismatch");
        assertEq(assetToken.getTotalValue(), 10_000 * 10 ** 18, "Total value mismatch");
        assertFalse(assetToken.isWhitelistEnabled(), "Whitelist should be enabled");
        assertFalse(assetToken.isAddressWhitelisted(owner), "Owner should be whitelisted");

        console.log("testInitialization completed successfully");
    }

    function test_AssetTokenDeployment() public {
        assertTrue(address(assetTokenWhitelisted) != address(0), "AssetToken not deployed");
        assertEq(assetTokenWhitelisted.name(), "Whitelisted Asset Token", "Incorrect AssetToken name");
        assertTrue(assetTokenWhitelisted.isWhitelistEnabled(), "Whitelist should be enabled");
    }

    function test_VerifyAssetToken() public {
        require(address(assetTokenWhitelisted) != address(0), "AssetToken not deployed");

        vm.startPrank(owner);

        bytes memory bytecode = address(assetTokenWhitelisted).code;
        require(bytecode.length > 0, "AssetToken has no bytecode");

        try assetTokenWhitelisted.name() returns (string memory name) {
            console.log("AssetToken name:", name);
        } catch Error(string memory reason) {
            console.log("Failed to get AssetToken name. Reason:", reason);
            revert("Failed to get AssetToken name");
        }

        try assetTokenWhitelisted.symbol() returns (string memory symbol) {
            console.log("AssetToken symbol:", symbol);
        } catch Error(string memory reason) {
            console.log("Failed to get AssetToken symbol. Reason:", reason);
            revert("Failed to get AssetToken symbol");
        }

        try assetTokenWhitelisted.isWhitelistEnabled() returns (bool enabled) {
            console.log("Is whitelist enabled:", enabled);
        } catch Error(string memory reason) {
            console.log("Failed to check if whitelist is enabled. Reason:", reason);
            revert("Failed to check if whitelist is enabled");
        }

        vm.stopPrank();
    }

    function test_Minting() public {
        vm.startPrank(address(testWalletImplementation));
        uint256 initialSupply = assetToken.totalSupply();
        uint256 mintAmount = 500 * 10 ** 18;

        assetToken.addToWhitelist(user1);
        assetToken.mint(user1, mintAmount);

        assertEq(assetToken.totalSupply(), initialSupply + mintAmount);
        assertEq(assetToken.balanceOf(user1), mintAmount);
        vm.stopPrank();
    }

    function test_SetTotalValue() public {
        vm.startPrank(address(testWalletImplementation));
        uint256 newTotalValue = 20_000 * 10 ** 18;
        assetToken.setTotalValue(newTotalValue);
        assertEq(assetToken.getTotalValue(), newTotalValue);
        vm.stopPrank();
    }

    function test_GetBalanceAvailable() public {
        // Create new MockSmartWallet instance
        MockSmartWallet mockWallet = new MockSmartWallet();
        uint256 totalBalance = 1000 * 10 ** 18;
        uint256 lockedBalance = 300 * 10 ** 18;

        vm.startPrank(address(testWalletImplementation));

        // Setup the mock wallet with tokens
        assetToken.addToWhitelist(address(mockWallet));
        assetToken.mint(address(mockWallet), totalBalance);

        // Lock some tokens
        mockWallet.lockTokens(IAssetToken(address(assetToken)), lockedBalance);
        vm.stopPrank();

        // Test available balance
        uint256 availableBalance = assetToken.getBalanceAvailable(address(mockWallet));

        // Available balance should be total balance minus locked balance
        assertEq(availableBalance, totalBalance - lockedBalance, "Available balance incorrect");
        assertEq(
            mockWallet.getBalanceLocked(IAssetToken(address(assetToken))), lockedBalance, "Locked balance incorrect"
        );
    }

    function test_Transfer() public {
        vm.startPrank(address(testWalletImplementation));
        uint256 transferAmount = 100 * 10 ** 18;

        assetToken.addToWhitelist(user1);
        assetToken.addToWhitelist(user2);
        assetToken.mint(user1, transferAmount);
        vm.stopPrank();

        vm.prank(user1);
        assetToken.transfer(user2, transferAmount);

        assertEq(assetToken.balanceOf(user1), 0);
        assertEq(assetToken.balanceOf(user2), transferAmount);
    }

    function test_UnauthorizedTransfer() public {
        uint256 transferAmount = 100 * 10 ** 18;
        vm.expectRevert();
        assetToken.addToWhitelist(user1);
        vm.startPrank(address(testWalletImplementation));

        assetToken.mint(user1, transferAmount);
        vm.stopPrank();

        vm.prank(user1);
        assetToken.transfer(user2, transferAmount);
    }

    function test_ConstructorWithWhitelist() public {
        AssetToken whitelistedToken = new AssetToken();
        whitelistedToken.initialize(
            owner,
            "Whitelisted Asset Token",
            "WAT",
            currencyToken,
            18,
            "http://example.com/whitelisted-token",
            1000 * 10 ** 18,
            10_000 * 10 ** 18,
            true // Whitelist enabled
        );
        assertTrue(whitelistedToken.isWhitelistEnabled(), "Whitelist should be enabled");
    }

    function test_UpdateWithWhitelistEnabled() public {
        AssetToken whitelistedToken = new AssetToken();
        whitelistedToken.initialize(
            owner,
            "Whitelisted Asset Token",
            "WAT",
            currencyToken,
            18,
            "http://example.com/whitelisted-token",
            1000 * 10 ** 18,
            10_000 * 10 ** 18,
            true // Whitelist enabled
        );

        vm.startPrank(owner);
        whitelistedToken.addToWhitelist(user1);
        whitelistedToken.addToWhitelist(user2);
        whitelistedToken.mint(user1, 100 * 10 ** 18);
        vm.stopPrank();

        vm.prank(user1);
        whitelistedToken.transfer(user2, 50 * 10 ** 18);

        assertEq(whitelistedToken.balanceOf(user1), 50 * 10 ** 18);
        assertEq(whitelistedToken.balanceOf(user2), 50 * 10 ** 18);
    }

    function checkAssetTokenOwner() public view returns (address) {
        return assetTokenWhitelisted.owner();
    }

    function isWhitelistEnabled() public view returns (bool) {
        return assetTokenWhitelisted.isWhitelistEnabled();
    }

    function test_AddAndRemoveFromWhitelist() public {
        console.log("AssetToken owner:", assetTokenWhitelisted.owner());
        console.log("Is whitelist enabled:", assetTokenWhitelisted.isWhitelistEnabled());

        require(assetTokenWhitelisted.isWhitelistEnabled(), "Whitelist must be enabled for this test");

        console.log("Before adding to whitelist:");
        console.log("Is user1 whitelisted:", assetTokenWhitelisted.isAddressWhitelisted(user1));
        console.log("Is user2 whitelisted:", assetTokenWhitelisted.isAddressWhitelisted(user2));

        // Add user1 to whitelist
        vm.prank(assetTokenWhitelisted.owner()); // Act as the SmartWallet
        assetTokenWhitelisted.addToWhitelist(user1);

        console.log("After adding user1:");
        console.log("Is user1 whitelisted:", assetTokenWhitelisted.isAddressWhitelisted(user1));

        // Add user2 to whitelist
        vm.prank(assetTokenWhitelisted.owner()); // Act as the SmartWallet
        assetTokenWhitelisted.addToWhitelist(user2);

        console.log("After adding user2:");
        console.log("Is user1 whitelisted:", assetTokenWhitelisted.isAddressWhitelisted(user1));
        console.log("Is user2 whitelisted:", assetTokenWhitelisted.isAddressWhitelisted(user2));

        assertTrue(assetTokenWhitelisted.isAddressWhitelisted(user1), "User1 should be whitelisted");
        assertTrue(assetTokenWhitelisted.isAddressWhitelisted(user2), "User2 should be whitelisted");

        // Remove user1 from whitelist
        vm.prank(assetTokenWhitelisted.owner()); // Act as the SmartWallet
        assetTokenWhitelisted.removeFromWhitelist(user1);

        console.log("After removing user1:");
        console.log("Is user1 whitelisted:", assetTokenWhitelisted.isAddressWhitelisted(user1));
        console.log("Is user2 whitelisted:", assetTokenWhitelisted.isAddressWhitelisted(user2));

        assertFalse(assetTokenWhitelisted.isAddressWhitelisted(user1), "User1 should not be whitelisted");
        assertTrue(assetTokenWhitelisted.isAddressWhitelisted(user2), "User2 should still be whitelisted");
    }

    function test_RequestYield() public {
        mockSmartWallet = new SmartWallet();
        uint256 initialBalance = 100 ether;
        uint256 yieldAmount = 10 ether;

        // Setup: Mint tokens and deposit yield
        vm.startPrank(address(testWalletImplementation));

        // Setup mock wallet
        assetToken.addToWhitelist(address(mockSmartWallet));
        assetToken.mint(address(mockSmartWallet), initialBalance);

        // Setup yield
        ERC20Mock(address(currencyToken)).mint(address(testWalletImplementation), yieldAmount);
        currencyToken.approve(address(assetToken), yieldAmount);

        // Deposit yield
        vm.warp(block.timestamp + 1); // Advance time to avoid same block deposit
        assetToken.depositYield(yieldAmount);

        // Advance time to accrue yield
        vm.warp(block.timestamp + 60); // Advance by 1 minute
        vm.stopPrank();

        // Record balances before yield request
        uint256 walletBalanceBefore = currencyToken.balanceOf(address(mockSmartWallet));

        // Request yield
        vm.expectEmit(true, true, true, false); // Don't check data as exact yield amount may vary
        emit IYieldDistributionToken.YieldAccrued(address(mockSmartWallet), 0); // Amount will be checked separately
        assetToken.requestYield(address(mockSmartWallet));

        // Verify balances after yield request
        uint256 walletBalanceAfter = currencyToken.balanceOf(address(mockSmartWallet));
        uint256 claimedYield = walletBalanceAfter - walletBalanceBefore;

        // Assert balance changes
        assertGt(claimedYield, 0, "Should have claimed some yield");
        assertLe(claimedYield, yieldAmount, "Claimed yield should not exceed deposited amount");
    }

    function test_GetPricePerToken() public {
        uint256 price = assetToken.getPricePerToken();
        console.log("price", price);
        assertEq(price, 1, "Price per token should be 10");
    }

    function test_RevertUnauthorizedTo() public {
        // Setup: Add user1 to whitelist but not user2
        vm.startPrank(address(testWalletImplementation));
        assetTokenWhitelisted.addToWhitelist(user1);
        assetTokenWhitelisted.mint(user1, 100 ether);
        vm.stopPrank();

        // Test: Try to transfer to non-whitelisted user
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(AssetToken.Unauthorized.selector, user2));
        assetTokenWhitelisted.transfer(user2, 50 ether);
    }

    function test_RevertInsufficientBalance() public {
        // Setup: Add users to whitelist and mint tokens
        vm.startPrank(address(testWalletImplementation));
        assetTokenWhitelisted.addToWhitelist(user1);
        assetTokenWhitelisted.addToWhitelist(user2);
        assetTokenWhitelisted.mint(user1, 100 ether);
        vm.stopPrank();

        // Test: Try to transfer more than balance
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(AssetToken.InsufficientBalance.selector, user1));
        assetTokenWhitelisted.transfer(user2, 150 ether);
    }

    function test_RevertAddToWhitelistInvalidAddress() public {
        vm.prank(address(testWalletImplementation));
        vm.expectRevert(AssetToken.InvalidAddress.selector);
        assetTokenWhitelisted.addToWhitelist(address(0));
    }

    function test_RevertAddToWhitelistAlreadyWhitelisted() public {
        // Setup: Add user1 to whitelist
        vm.startPrank(address(testWalletImplementation));
        assetTokenWhitelisted.addToWhitelist(user1);

        // Test: Try to add user1 again
        vm.expectRevert(abi.encodeWithSelector(AssetToken.AddressAlreadyWhitelisted.selector, user1));
        assetTokenWhitelisted.addToWhitelist(user1);
        vm.stopPrank();
    }

    function test_RevertRemoveFromWhitelistInvalidAddress() public {
        vm.prank(address(testWalletImplementation));
        vm.expectRevert(AssetToken.InvalidAddress.selector);
        assetTokenWhitelisted.removeFromWhitelist(address(0));
    }

    function test_RevertRemoveFromWhitelistNotWhitelisted() public {
        vm.prank(address(testWalletImplementation));
        vm.expectRevert(abi.encodeWithSelector(AssetToken.AddressNotWhitelisted.selector, user1));
        assetTokenWhitelisted.removeFromWhitelist(user1);
    }

    function test_RemoveFromWhitelistSuccess() public {
        // Setup: Add user1 to whitelist
        vm.startPrank(address(testWalletImplementation));
        assetTokenWhitelisted.addToWhitelist(user1);

        // Test: Successfully remove from whitelist
        vm.expectEmit(true, false, false, false);
        emit AssetToken.AddressRemovedFromWhitelist(user1);
        assetTokenWhitelisted.removeFromWhitelist(user1);

        // Verify user is no longer whitelisted
        assertFalse(assetTokenWhitelisted.isAddressWhitelisted(user1));
        vm.stopPrank();
    }

    function test_DepositYield() public {
        uint256 depositAmount = 100 ether;

        vm.startPrank(address(testWalletImplementation));
        // Mint currency tokens to owner for deposit
        ERC20Mock(address(currencyToken)).mint(address(testWalletImplementation), depositAmount);
        currencyToken.approve(address(assetToken), depositAmount);

        // Need to advance block time to avoid DepositSameBlock error
        vm.warp(block.timestamp + 1);

        assetToken.depositYield(depositAmount);
        vm.stopPrank();
    }

    function test_RequestYieldRevert() public {
        address invalidSmartWallet = address(0x123);

        // Mock the call to return nothing and revert
        vm.mockCallRevert(
            invalidSmartWallet,
            abi.encodeWithSelector(ISmartWallet.claimAndRedistributeYield.selector, assetToken),
            hex""
        );

        vm.expectRevert(abi.encodeWithSelector(WalletUtils.SmartWalletCallFailed.selector, invalidSmartWallet));
        assetToken.requestYield(invalidSmartWallet);
    }

    function test_GetBalanceAvailableRevert() public {
        // Create a contract that doesn't implement the interface
        address mockContract = address(new Contract());

        vm.expectRevert(abi.encodeWithSelector(WalletUtils.SmartWalletCallFailed.selector, mockContract));
        assetToken.getBalanceAvailable(mockContract);
    }

    function test_YieldCalculations() public {
        uint256 initialMint = 100 ether;
        uint256 yieldAmount = 10 ether;

        vm.startPrank(address(testWalletImplementation));

        // Mint tokens to users - equal amounts
        assetToken.mint(user1, initialMint);
        assetToken.mint(user2, initialMint);

        // Mint & deposit yield
        ERC20Mock(address(currencyToken)).mint(address(testWalletImplementation), yieldAmount);
        currencyToken.approve(address(assetToken), yieldAmount);

        vm.warp(block.timestamp + 1);
        assetToken.depositYield(yieldAmount);

        // Let yield accrue for just a few seconds
        vm.warp(block.timestamp + 10); // Only 10 seconds instead of 1 hour

        vm.stopPrank();

        vm.prank(user1);
        (IERC20 token1, uint256 amount1) = assetToken.claimYield(user1);

        vm.prank(user2);
        (IERC20 token2, uint256 amount2) = assetToken.claimYield(user2);

        // Debug logs
        console.log("User 1 yield amount:", amount1);
        console.log("User 2 yield amount:", amount2);
        console.log("Total yield deposited:", yieldAmount);

        // Test assumptions:
        // 1. Both users should get roughly equal yield (within 1%)
        assertApproxEqRel(amount1, amount2, 0.01e18);
        // 2. Total claimed yield should not exceed deposited amount
        assertLe(amount1 + amount2, yieldAmount);
    }

    function test_YieldCalculationsWithMultipleDeposits() public {
        uint256 initialMint = 100 ether;
        uint256 firstYield = 10 ether;
        uint256 secondYield = 5 ether;

        vm.startPrank(address(testWalletImplementation));

        // Initial setup
        assetToken.mint(user1, initialMint);

        // First yield deposit
        ERC20Mock(address(currencyToken)).mint(address(testWalletImplementation), firstYield);
        currencyToken.approve(address(assetToken), firstYield);
        vm.warp(block.timestamp + 1);
        assetToken.depositYield(firstYield);

        // Second yield deposit after a short time
        vm.warp(block.timestamp + 10); // Only 10 seconds
        ERC20Mock(address(currencyToken)).mint(address(testWalletImplementation), secondYield);
        currencyToken.approve(address(assetToken), secondYield);
        assetToken.depositYield(secondYield);

        vm.stopPrank();

        // Claim yield after a short time
        vm.startPrank(user1);
        vm.warp(block.timestamp + 10); // Only 10 seconds

        (IERC20 token, uint256 claimedAmount) = assetToken.claimYield(user1);

        // Debug logs
        console.log("Claimed amount:", claimedAmount);
        console.log("Total yield deposited:", firstYield + secondYield);

        vm.stopPrank();

        // Test assumptions:
        // 1. Token should be the correct currency token
        assertEq(address(token), address(currencyToken));
        // 2. Claimed amount should not exceed total deposited yield
        assertLe(claimedAmount, firstYield + secondYield);
    }

    function test_RevertConstructorInvalidAddress() public {
        // First test: Invalid owner (should revert with OwnableInvalidOwner)
        AssetToken token = new AssetToken();

        // First test: Invalid owner
        vm.expectRevert(abi.encodeWithSignature("OwnableInvalidOwner(address)", address(0)));
        token.initialize(
            address(0), // Invalid owner address
            "Asset Token",
            "AT",
            ERC20(address(currencyToken)),
            18,
            "http://example.com/token",
            1000 * 10 ** 18,
            10_000 * 10 ** 18,
            true
        );

        // Second test: Invalid currency token (should revert with InvalidAddress)
        AssetToken token2 = new AssetToken();
        vm.expectRevert(AssetToken.InvalidAddress.selector);
        token2.initialize(
            address(this), // valid owner
            "Asset Token",
            "AT",
            ERC20(address(0)), // Invalid currency token address
            18,
            "http://example.com/token",
            1000 * 10 ** 18,
            10_000 * 10 ** 18,
            true
        );
    }

    function test_GetBalanceAvailableWithLockedBalance() public {
        uint256 initialBalance = 100 ether;
        uint256 lockedBalance = 30 ether;

        // Create new MockSmartWallet instance
        MockSmartWallet mockWallet = new MockSmartWallet();

        vm.startPrank(address(testWalletImplementation));

        // Mint some tokens to the mock wallet
        assetToken.mint(address(mockWallet), initialBalance);

        // Lock some tokens
        mockWallet.lockTokens(IAssetToken(address(assetToken)), lockedBalance);

        vm.stopPrank();

        // Check available balance
        uint256 availableBalance = assetToken.getBalanceAvailable(address(mockWallet));

        // Available balance should be initial balance minus locked balance
        assertEq(availableBalance, initialBalance - lockedBalance);
    }

}
