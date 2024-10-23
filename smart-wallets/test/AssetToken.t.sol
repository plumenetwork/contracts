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

    // Events for testing
    event Deposited(address indexed user, uint256 currencyTokenAmount);

    // small hack to be excluded from coverage report
    // function test_() public { }

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

        assetToken = new AssetToken(
            address(testWalletImplementation), // The SmartWallet is the owner
            "Asset Token",
            "AT",
            currencyToken,
            18,
            "http://example.com/token",
            10_000 * 10 ** 18, // Set initialSupply to zero
            10_000 * 10 ** 18,
            false // Whitelist enabled
        );

        assetTokenWhitelisted = new AssetToken(
            address(testWalletImplementation), // The SmartWallet is the owner
            "Whitelisted Asset Token",
            "WAT",
            currencyToken,
            18,
            "http://example.com/token",
            0, // Set initialSupply to zero
            10_000 * 10 ** 18,
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
        //assertEq(assetToken.tokenURI_(), "http://example.com/token", "TokenURI mismatch");
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

    //TODO: convert to SmartWalletCall
    function test_GetBalanceAvailable() public {
        vm.startPrank(address(testWalletImplementation));

        uint256 balance = 1000 * 10 ** 18;
        assetToken.addToWhitelist(user1);
        assetToken.mint(user1, balance);

        assertEq(assetToken.getBalanceAvailable(user1), balance);
        vm.stopPrank();
        // Note: To fully test getBalanceAvailable, you would need to mock a SmartWallet
        // contract that implements the ISmartWallet interface and returns a locked balance.
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
        AssetToken whitelistedToken = new AssetToken(
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
        AssetToken whitelistedToken = new AssetToken(
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
    // Update the test function

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

        vm.startPrank(address(testWalletImplementation));
        assetToken.addToWhitelist(address(mockSmartWallet));
        assetToken.mint(address(mockSmartWallet), 1000 * 10 ** 18);
        vm.stopPrank();

        assetToken.requestYield(address(mockSmartWallet));
        // You may need to implement a way to verify that the yield was requested
    }

    function test_GetWhitelist() public {
        vm.startPrank(address(testWalletImplementation));
        assetTokenWhitelisted.addToWhitelist(user1);
        assetTokenWhitelisted.addToWhitelist(user2);
        vm.stopPrank();

        address[] memory whitelist = assetTokenWhitelisted.getWhitelist();
        assertEq(whitelist.length, 3, "Whitelist should have 3 addresses including the owner");
    }

    function test_GetHoldersAndHasBeenHolder() public {
        vm.startPrank(address(testWalletImplementation));
        assetToken.addToWhitelist(user1);
        assetToken.addToWhitelist(user2);
        assetToken.mint(user1, 100 * 10 ** 18);
        assetToken.mint(user2, 100 * 10 ** 18);
        vm.stopPrank();

        address[] memory holders = assetToken.getHolders();
        assertEq(holders.length, 3, "Should have 3 holders (owner, user1, user2)");
        assertTrue(assetToken.hasBeenHolder(user1), "User1 should be a holder");
        assertTrue(assetToken.hasBeenHolder(user2), "User2 should be a holder");
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
        emit AddressRemovedFromWhitelist(user1);
        assetTokenWhitelisted.removeFromWhitelist(user1);

        // Verify user is no longer whitelisted
        assertFalse(assetTokenWhitelisted.isAddressWhitelisted(user1));
        vm.stopPrank();
    }

    // Helper function to check if event was emitted
    event AddressRemovedFromWhitelist(address indexed user);

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
        address user1 = address(0x1);
        address user2 = address(0x2);
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

        // Let yield accrue
        vm.warp(block.timestamp + 1 days);

        // Claim yield for both users
        vm.stopPrank();

        vm.prank(user1);
        (IERC20 token1, uint256 amount1) = assetToken.claimYield(user1);

        vm.prank(user2);
        (IERC20 token2, uint256 amount2) = assetToken.claimYield(user2);

        // Test assumptions:
        // 1. Both users should get roughly equal yield (within 1%)
        assertApproxEqRel(amount1, amount2, 0.01e18);

        // 2. The sum of claimed yields should be the unclaimed yield
        assertEq(assetToken.unclaimedYield(user1), 0); // All claimed for user1
        assertEq(assetToken.unclaimedYield(user2), 0); // All claimed for user2

        // 3. Individual claims should match user's total yield
        assertEq(amount1, assetToken.totalYield(user1));
        assertEq(amount2, assetToken.totalYield(user2));
    }

    function test_YieldCalculationsWithMultipleDeposits() public {
        address user1 = address(0x1);
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

        // Second yield deposit
        vm.warp(block.timestamp + 1 days);
        ERC20Mock(address(currencyToken)).mint(address(testWalletImplementation), secondYield);
        currencyToken.approve(address(assetToken), secondYield);
        assetToken.depositYield(secondYield);

        vm.stopPrank();

        // Claim yield
        vm.startPrank(user1);
        vm.warp(block.timestamp + 1 days);
        //console.log(assetToken.totalYield());
        //console.log(assetToken.claimedYield());
        assertEq(assetToken.totalYield(), 0);
        assertEq(assetToken.claimedYield(), 0);

        (IERC20 token, uint256 claimedAmount) = assetToken.claimYield(user1);
        vm.stopPrank();

        // Test assumptions:
        // 1. All yield should be claimed
        assertEq(assetToken.unclaimedYield(user1), 0);

        // 2. Claimed amount should match total yield
        assertEq(claimedAmount, assetToken.totalYield(user1));

        // 3. Token should be the correct currency token
        assertEq(address(token), address(currencyToken));

        // 4. Claimed yield should be the user's total yield
        assertEq(assetToken.claimedYield(user1), assetToken.totalYield(user1));
    }

}
