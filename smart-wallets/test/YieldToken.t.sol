// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { SmartWallet } from "../src/SmartWallet.sol";
import { WalletUtils } from "../src/WalletUtils.sol";

import { IAssetToken } from "../src/interfaces/IAssetToken.sol";
import { ISmartWallet } from "../src/interfaces/ISmartWallet.sol";
import { YieldToken } from "../src/token/YieldToken.sol";

import { MockAssetToken } from "../src/mocks/MockAssetToken.sol";

import { MockInvalidAssetToken } from "../src/mocks/MockInvalidAssetToken.sol";
import { MockInvalidSmartWallet } from "../src/mocks/MockInvalidSmartWallet.sol";
import { MockYieldToken } from "../src/mocks/MockYieldToken.sol";

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import "forge-std/Test.sol";

contract YieldTokenTest is Test {

    ERC20Mock public mockCurrencyToken;
    ERC20Mock public currencyToken;
    MockYieldToken public yieldToken;

    MockAssetToken public mockAssetToken;
    MockAssetToken assetToken;

    address public owner;
    address public user1;
    address public user2;

    ERC20Mock public invalidCurrencyToken;
    MockInvalidAssetToken public invalidAssetToken;

    // small hack to be excluded from coverage report
    function test() public { }

    function setUp() public {
        owner = address(this);
        user1 = address(0x123);
        user2 = address(0x456);
        // Deploy mock currency token
        mockCurrencyToken = new ERC20Mock();
        currencyToken = new ERC20Mock();

        // Deploy mock asset token
        mockAssetToken = new MockAssetToken();
        assetToken = new MockAssetToken();

        mockAssetToken.initialize(
            owner,
            "Mock Asset Token",
            "MAT",
            mockCurrencyToken,
            false // isWhitelistEnabled
        );

        // Verify that the mock asset token has the correct currency token
        require(
            address(mockAssetToken.getCurrencyToken()) == address(mockCurrencyToken),
            "MockAssetToken not initialized correctly"
        );

        // Deploy MockYieldToken instead of YieldToken
        yieldToken = new MockYieldToken(
            owner,
            "Yield Token",
            "YLT",
            mockCurrencyToken,
            18,
            "https://example.com/token-uri",
            mockAssetToken,
            100 * 10 ** 18 // Initial supply
        );

        // Deploy invalid tokens for testing
        invalidAssetToken = new MockInvalidAssetToken();
    }

    function testInitialDeployment() public {
        assertEq(yieldToken.name(), "Yield Token");
        assertEq(yieldToken.symbol(), "YLT");
        assertEq(yieldToken.balanceOf(owner), 100 ether);
    }

    function testInvalidCurrencyTokenOnDeploy() public {
        // Deploy mock tokens with different currency tokens
        invalidCurrencyToken = new ERC20Mock();
        MockAssetToken testAssetToken = new MockAssetToken();
        testAssetToken.initialize(
            owner,
            "Test Asset Token",
            "TAT",
            currencyToken, // Use the valid currencyToken
            false
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                YieldToken.InvalidCurrencyToken.selector, address(invalidCurrencyToken), address(currencyToken)
            )
        );

        new YieldToken(
            owner, "Yield Token", "YLT", invalidCurrencyToken, 18, "https://example.com", testAssetToken, 100 ether
        );
    }

    function testMintingByOwner() public {
        yieldToken.adminMint(user1, 50 ether);
        assertEq(yieldToken.balanceOf(user1), 50 ether);
    }

    function testMintingByNonOwnerFails() public {
        vm.prank(user1); // Use user1 for this call
        vm.expectRevert();
        yieldToken.adminMint(user2, 50 ether);
    }

    function testReceiveYieldWithValidTokens() public {
        // Use mockAssetToken and mockCurrencyToken that are already properly initialized
        mockCurrencyToken.mint(address(this), 10 ether); // Mint tokens to test with
        mockCurrencyToken.approve(address(yieldToken), 10 ether);

        // Advance the block timestamp to avoid DepositSameBlock error
        vm.warp(block.timestamp + 1);

        // Use mockAssetToken instead of assetToken since it's properly initialized
        yieldToken.receiveYield(mockAssetToken, mockCurrencyToken, 10 ether);

        // Verify the yield was received
        assertEq(mockCurrencyToken.balanceOf(address(yieldToken)), 10 ether);
    }

    function testReceiveYieldWithInvalidAssetToken() public {
        invalidAssetToken = new MockInvalidAssetToken();

        vm.expectRevert(
            abi.encodeWithSelector(
                YieldToken.InvalidAssetToken.selector, address(invalidAssetToken), address(mockAssetToken)
            )
        );
        yieldToken.receiveYield(invalidAssetToken, mockCurrencyToken, 10 ether);
    }

    function testReceiveYieldWithInvalidCurrencyToken() public {
        invalidCurrencyToken = new ERC20Mock();

        vm.expectRevert(
            abi.encodeWithSelector(
                YieldToken.InvalidCurrencyToken.selector,
                address(invalidCurrencyToken),
                address(mockCurrencyToken) // Use mockCurrencyToken since it's the one initialized in setUp
            )
        );
        yieldToken.receiveYield(mockAssetToken, invalidCurrencyToken, 10 ether);
    }

    function testRequestYieldSuccess() public {
        SmartWallet smartWallet = new SmartWallet();

        // Get initial state
        address vaultBefore = address(smartWallet.getAssetVault());

        // Call requestYield
        yieldToken.requestYield(address(smartWallet));

        // Verify the smart wallet received the request:
        // 1. AssetVault should be created if it didn't exist
        address vaultAfter = address(smartWallet.getAssetVault());
        assertTrue(vaultAfter != address(0));
        if (vaultBefore == address(0)) {
            assertTrue(vaultAfter != vaultBefore);
        }
    }

    function testRequestYieldFailure() public {
        // Deploy an invalid smart wallet that doesn't implement the interface
        MockInvalidSmartWallet invalidWallet = new MockInvalidSmartWallet();

        // Expect the correct error when calling a contract that doesn't implement the interface
        vm.expectRevert(abi.encodeWithSelector(WalletUtils.SmartWalletCallFailed.selector, address(invalidWallet)));

        yieldToken.requestYield(address(invalidWallet));
    }

    function testConstructorInvalidCurrencyToken() public {
        // Create a new asset token with a different currency token
        MockAssetToken newAssetToken = new MockAssetToken();
        ERC20Mock differentCurrencyToken = new ERC20Mock();

        newAssetToken.initialize(
            owner,
            "New Asset Token",
            "NAT",
            differentCurrencyToken, // Initialize with different currency token
            false
        );

        // Try to create YieldToken with mismatched currency token
        vm.expectRevert(
            abi.encodeWithSelector(
                YieldToken.InvalidCurrencyToken.selector, address(mockCurrencyToken), address(differentCurrencyToken)
            )
        );

        new YieldToken(
            owner,
            "Yield Token",
            "YLT",
            mockCurrencyToken, // This doesn't match the asset token's currency
            18,
            "https://example.com/token-uri",
            newAssetToken,
            100 ether
        );
    }

    function testConstructorSuccess() public {
        // Test the successful deployment case explicitly
        YieldToken newYieldToken = new YieldToken(
            owner,
            "New Yield Token",
            "NYT",
            mockCurrencyToken,
            18,
            "https://example.com/new-token-uri",
            mockAssetToken,
            50 ether
        );

        // Verify all constructor parameters were set correctly
        assertEq(newYieldToken.name(), "New Yield Token");
        assertEq(newYieldToken.symbol(), "NYT");
        assertEq(newYieldToken.decimals(), 18);
        assertEq(newYieldToken.getTokenURI(), "https://example.com/new-token-uri");
        assertEq(newYieldToken.balanceOf(owner), 50 ether);
        assertEq(address(newYieldToken.getCurrencyToken()), address(mockCurrencyToken));
    }

    function testReceiveYieldInvalidCurrencyToken() public {
        // Create tokens with a different currency token for testing
        ERC20Mock differentCurrencyToken = new ERC20Mock();

        // Mint and approve tokens
        differentCurrencyToken.mint(address(this), 10 ether);
        differentCurrencyToken.approve(address(yieldToken), 10 ether);

        // Advance time to avoid DepositSameBlock error
        vm.warp(block.timestamp + 1);

        // Try to receive yield with wrong currency token
        vm.expectRevert(
            abi.encodeWithSelector(
                YieldToken.InvalidCurrencyToken.selector, address(differentCurrencyToken), address(mockCurrencyToken)
            )
        );

        yieldToken.receiveYield(mockAssetToken, differentCurrencyToken, 10 ether);
    }

    function testMintWithZeroAmount() public {
        vm.expectRevert(YieldToken.ZeroAmount.selector);
        yieldToken.mint(0, user1, owner);
    }

    function testMintWithZeroAddressReceiver() public {
        vm.expectRevert(abi.encodeWithSelector(YieldToken.ZeroAddress.selector, "receiver"));
        yieldToken.mint(100 ether, address(0), owner);
    }

    function testMintUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(YieldToken.Unauthorized.selector, user1, owner));
        yieldToken.mint(100 ether, user2, owner);
    }

    function testMintSuccess() public {
        // First need to request deposit
        uint256 depositAmount = 100 ether;
        mockCurrencyToken.mint(user1, depositAmount);

        vm.startPrank(user1);
        mockCurrencyToken.approve(address(yieldToken), depositAmount);
        yieldToken.requestDeposit(depositAmount, owner, user1);
        vm.stopPrank();

        // Simulate notification of deposit
        uint256 sharesToMint = 100 ether; // In this case 1:1 ratio
        vm.prank(address(mockAssetToken));
        yieldToken.notifyDeposit(depositAmount, sharesToMint, owner);

        // Now test the mint
        uint256 assets = yieldToken.mint(sharesToMint, user1, owner);
        assertEq(assets, depositAmount);
        assertEq(yieldToken.balanceOf(user1), sharesToMint);
    }

    function testRequestDepositWithZeroAmount() public {
        vm.expectRevert(YieldToken.ZeroAmount.selector);
        yieldToken.requestDeposit(0, owner, user1);
    }

    function testRequestDepositUnauthorized() public {
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(YieldToken.Unauthorized.selector, user2, user1));
        yieldToken.requestDeposit(100 ether, owner, user1);
    }

    function testRequestDepositSuccess() public {
        uint256 depositAmount = 100 ether;
        mockCurrencyToken.mint(user1, depositAmount);

        vm.startPrank(user1);
        mockCurrencyToken.approve(address(yieldToken), depositAmount);
        uint256 requestId = yieldToken.requestDeposit(depositAmount, owner, user1);
        vm.stopPrank();

        assertEq(requestId, 0); // REQUEST_ID is always 0
        assertEq(yieldToken.pendingDepositRequest(0, owner), depositAmount);
    }

    function testDepositWithZeroAmount() public {
        vm.expectRevert(YieldToken.ZeroAmount.selector);
        yieldToken.deposit(0, user1, owner);
    }

    function testDepositWithZeroAddressReceiver() public {
        vm.expectRevert(abi.encodeWithSelector(YieldToken.ZeroAddress.selector, "receiver"));
        yieldToken.deposit(100 ether, address(0), owner);
    }

    function testDepositUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(YieldToken.Unauthorized.selector, user1, owner));
        yieldToken.deposit(100 ether, user2, owner);
    }

    function testDepositSuccess() public {
        uint256 depositAmount = 100 ether;
        mockCurrencyToken.mint(user1, depositAmount);

        vm.startPrank(user1);
        mockCurrencyToken.approve(address(yieldToken), depositAmount);
        yieldToken.requestDeposit(depositAmount, owner, user1);
        vm.stopPrank();

        // Simulate notification of deposit
        uint256 sharesToMint = 100 ether; // 1:1 ratio for simplicity
        vm.prank(address(mockAssetToken));
        yieldToken.notifyDeposit(depositAmount, sharesToMint, owner);

        // Test deposit
        uint256 shares = yieldToken.deposit(depositAmount, user1, owner);
        assertEq(shares, sharesToMint);
        assertEq(yieldToken.balanceOf(user1), sharesToMint);
    }

    function testRedeemWithZeroAmount() public {
        vm.expectRevert(YieldToken.ZeroAmount.selector);
        yieldToken.redeem(0, user1, owner);
    }

    function testRedeemWithZeroAddressReceiver() public {
        vm.expectRevert(abi.encodeWithSelector(YieldToken.ZeroAddress.selector, "receiver"));
        yieldToken.redeem(100 ether, address(0), owner);
    }

    function testRedeemUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(YieldToken.Unauthorized.selector, user1, owner));
        yieldToken.redeem(100 ether, user2, owner);
    }

    // Withdraw tests
    function testWithdrawWithZeroAmount() public {
        vm.expectRevert(YieldToken.ZeroAmount.selector);
        yieldToken.withdraw(0, user1, owner);
    }

    function testWithdrawWithZeroAddressReceiver() public {
        vm.expectRevert(abi.encodeWithSelector(YieldToken.ZeroAddress.selector, "receiver"));
        yieldToken.withdraw(100 ether, address(0), owner);
    }

    function testWithdrawUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(YieldToken.Unauthorized.selector, user1, owner));
        yieldToken.withdraw(100 ether, user2, owner);
    }

    function testWithdrawInsufficientRequestBalance() public {
        vm.expectRevert(abi.encodeWithSelector(YieldToken.InsufficientRequestBalance.selector, owner, 100 ether, 3));
        yieldToken.withdraw(100 ether, user1, owner);
    }

    function testWithdrawSuccess() public {
        uint256 amount = 100 ether;

        // Setup: First mint some tokens and request deposit
        mockCurrencyToken.mint(user1, amount);

        vm.startPrank(user1);
        mockCurrencyToken.approve(address(yieldToken), amount);
        yieldToken.requestDeposit(amount, owner, user1);
        vm.stopPrank();

        // Notify deposit
        yieldToken.notifyDeposit(amount, amount, owner);
        yieldToken.deposit(amount, user1, owner);

        // Request redeem
        vm.prank(user1);
        yieldToken.requestRedeem(amount, owner, user1);

        // Notify redeem
        yieldToken.notifyRedeem(amount, amount, owner);

        // Test withdraw
        uint256 withdrawnAmount = yieldToken.withdraw(amount, user1, owner);

        // Verify the withdrawal
        assertEq(withdrawnAmount, amount);
        assertEq(mockCurrencyToken.balanceOf(user1), amount);
        assertEq(yieldToken.balanceOf(user1), 0);
    }

    // Redeem tests
    function testRedeemSuccess() public {
        // Setup: First mint some tokens
        uint256 amount = 100 ether;
        mockCurrencyToken.mint(user1, amount);

        vm.startPrank(user1);
        mockCurrencyToken.approve(address(yieldToken), amount);
        yieldToken.requestDeposit(amount, owner, user1);
        vm.stopPrank();

        yieldToken.notifyDeposit(amount, amount, owner);
        yieldToken.deposit(amount, user1, owner);

        // Now test redeem
        vm.startPrank(user1);
        yieldToken.requestRedeem(amount, owner, user1);
        vm.stopPrank();

        yieldToken.notifyRedeem(amount, amount, owner);
        uint256 redeemedAssets = yieldToken.redeem(amount, user1, owner);

        assertEq(redeemedAssets, amount);
        assertEq(mockCurrencyToken.balanceOf(user1), amount);
    }

    // NotifyRedeem tests
    function testNotifyRedeemWithZeroAmount() public {
        vm.expectRevert(YieldToken.ZeroAmount.selector);
        yieldToken.notifyRedeem(100 ether, 0, owner);
    }

    function testNotifyRedeemInsufficientPendingRequest() public {
        vm.expectRevert(abi.encodeWithSelector(YieldToken.InsufficientRequestBalance.selector, owner, 100 ether, 2));
        yieldToken.notifyRedeem(100 ether, 100 ether, owner);
    }

    // RequestRedeem tests
    function testRequestRedeemWithZeroAmount() public {
        vm.expectRevert(YieldToken.ZeroAmount.selector);
        yieldToken.requestRedeem(0, owner, user1);
    }

    function testRequestRedeemUnauthorized() public {
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(YieldToken.Unauthorized.selector, user2, user1));
        yieldToken.requestRedeem(100 ether, owner, user1);
    }

    // Mint tests for InsufficientRequestBalance
    function testMintInsufficientRequestBalance() public {
        uint256 amount = 100 ether;

        // First need to request deposit
        mockCurrencyToken.mint(user1, amount);

        vm.startPrank(user1);
        mockCurrencyToken.approve(address(yieldToken), amount);
        yieldToken.requestDeposit(amount, owner, user1);
        vm.stopPrank();

        // Try to mint without having notified the deposit
        vm.expectRevert(
            abi.encodeWithSelector(
                YieldToken.InsufficientRequestBalance.selector,
                owner,
                amount,
                1 // Claimable deposit request type
            )
        );
        yieldToken.mint(amount, user1, owner);
    }
    // Deposit tests for InsufficientRequestBalance

    function testDepositInsufficientRequestBalance() public {
        vm.expectRevert(abi.encodeWithSelector(YieldToken.InsufficientRequestBalance.selector, owner, 100 ether, 1));
        yieldToken.deposit(100 ether, user1, owner);
    }

    // NotifyDeposit tests
    function testNotifyDepositWithZeroAmount() public {
        vm.expectRevert(YieldToken.ZeroAmount.selector);
        yieldToken.notifyDeposit(0, 100 ether, owner);
    }

    // RequestDeposit tests for InsufficientBalance
    function testRequestDepositInsufficientBalance() public {
        uint256 amount = 100 ether;

        vm.startPrank(user1);
        mockCurrencyToken.approve(address(yieldToken), amount);

        // Expect the ERC20InsufficientBalance error instead
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                user1,
                0, // current balance
                amount
            )
        );
        yieldToken.requestDeposit(amount, owner, user1);
        vm.stopPrank();
    }

    // ConvertToAssets tests
    function testConvertToAssetsWithZeroSupply() public {
        // Deploy new token with 0 supply
        MockYieldToken newToken =
            new MockYieldToken(owner, "Test Token", "TEST", mockCurrencyToken, 18, "uri", mockAssetToken, 0);

        uint256 result = newToken.convertToAssets(100 ether);
        assertEq(result, 100 ether);
    }

    // ConvertToShares tests
    function testConvertToSharesWithZeroSupply() public {
        // Deploy new token with 0 supply
        MockYieldToken newToken =
            new MockYieldToken(owner, "Test Token", "TEST", mockCurrencyToken, 18, "uri", mockAssetToken, 0);

        uint256 result = newToken.convertToShares(100 ether);
        assertEq(result, 100 ether);
    }

    function testConvertToSharesWithNonZeroSupply() public {
        // Initial supply is 100 ether from setUp
        uint256 result = yieldToken.convertToShares(50 ether);
        assertEq(result, 50 ether);
    }

    // AssetsOf tests
    function testAssetsOf() public {
        uint256 shares = 100 ether;
        yieldToken.adminMint(user1, shares);

        uint256 assets = yieldToken.assetsOf(user1);
        assertEq(assets, yieldToken.convertToAssets(shares));
    }

    function testAssetsOfWithZeroBalance() public {
        uint256 assets = yieldToken.assetsOf(user1);
        assertEq(assets, 0);
    }

    function testClaimableDepositRequest() public {
        uint256 amount = 100 ether;

        // Initially should be 0
        assertEq(yieldToken.claimableDepositRequest(0, owner), 0);

        // Setup a deposit request
        mockCurrencyToken.mint(user1, amount);
        vm.startPrank(user1);
        mockCurrencyToken.approve(address(yieldToken), amount);
        yieldToken.requestDeposit(amount, owner, user1);
        vm.stopPrank();

        // Notify deposit to make it claimable
        yieldToken.notifyDeposit(amount, amount, owner);

        // Should now show the claimable amount
        assertEq(yieldToken.claimableDepositRequest(0, owner), amount);

        // After claiming (depositing), should be 0 again
        yieldToken.deposit(amount, user1, owner);
        assertEq(yieldToken.claimableDepositRequest(0, owner), 0);
    }

    function testPendingRedeemRequest() public {
        uint256 amount = 100 ether;

        // Initially should be 0
        assertEq(yieldToken.pendingRedeemRequest(0, owner), 0);

        // Setup: First mint some tokens to test with
        mockCurrencyToken.mint(user1, amount);
        vm.startPrank(user1);
        mockCurrencyToken.approve(address(yieldToken), amount);
        yieldToken.requestDeposit(amount, owner, user1);
        vm.stopPrank();

        yieldToken.notifyDeposit(amount, amount, owner);
        yieldToken.deposit(amount, user1, owner);

        // Request redeem
        vm.prank(user1);
        yieldToken.requestRedeem(amount, owner, user1);

        // Should show pending amount
        assertEq(yieldToken.pendingRedeemRequest(0, owner), amount);
    }

    function testClaimableRedeemRequest() public {
        uint256 amount = 100 ether;

        // Initially should be 0
        assertEq(yieldToken.claimableRedeemRequest(0, owner), 0);

        // Setup: First mint some tokens to test with
        mockCurrencyToken.mint(user1, amount);
        vm.startPrank(user1);
        mockCurrencyToken.approve(address(yieldToken), amount);
        yieldToken.requestDeposit(amount, owner, user1);
        vm.stopPrank();

        yieldToken.notifyDeposit(amount, amount, owner);
        yieldToken.deposit(amount, user1, owner);

        // Request redeem
        vm.prank(user1);
        yieldToken.requestRedeem(amount, owner, user1);

        // Notify redeem to make it claimable
        yieldToken.notifyRedeem(amount, amount, owner);

        // Should show claimable amount
        assertEq(yieldToken.claimableRedeemRequest(0, owner), amount);

        // After claiming (withdrawing), should be 0 again
        yieldToken.withdraw(amount, user1, owner);
        assertEq(yieldToken.claimableRedeemRequest(0, owner), 0);
    }

}
