// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { SmartWallet } from "../src/SmartWallet.sol";
import { WalletUtils } from "../src/WalletUtils.sol";

import { IAssetToken } from "../src/interfaces/IAssetToken.sol";
import { ISmartWallet } from "../src/interfaces/ISmartWallet.sol";
import { YieldToken } from "../src/token/YieldToken.sol";

import { MockAssetToken } from "../src/mocks/MockAssetToken.sol";
import { MockInvalidAssetToken } from "../src/mocks/MockInvalidAssetToken.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";

contract YieldTokenTest is Test {

    YieldToken public yieldToken;
    ERC20Mock public mockCurrencyToken;
    ERC20Mock public currencyToken;

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

        // Deploy YieldToken
        yieldToken = new YieldToken(
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

        // Add assertions to verify the yield was received
        assertEq(mockCurrencyToken.balanceOf(address(yieldToken)), 10 ether);
    }

    function testReceiveYieldWithInvalidAssetToken() public {
        invalidAssetToken = new MockInvalidAssetToken();

        //vm.expectRevert(abi.encodeWithSelector(YieldToken.InvalidAssetToken.selector, address(invalidAssetToken),
        // address(assetToken)));

        vm.expectRevert();
        yieldToken.receiveYield(invalidAssetToken, currencyToken, 10 ether);
    }

    function testReceiveYieldWithInvalidCurrencyToken() public {
        //ERC20Mock invalidCurrencyToken = new ERC20Mock();

        // vm.expectRevert(abi.encodeWithSelector(YieldToken.InvalidCurrencyToken.selector,
        // address(invalidCurrencyToken),address(currencyToken)));
        vm.expectRevert();
        yieldToken.receiveYield(assetToken, invalidCurrencyToken, 10 ether);
    }

    function testRequestYieldSuccess() public {
        SmartWallet smartWallet = new SmartWallet();

        yieldToken.requestYield(address(smartWallet));
        // Optionally check that the smartWallet function was called properly
    }

    function testRequestYieldFailure() public {
        address invalidAddress = address(0);

        // Expect the correct error
        vm.expectRevert(abi.encodeWithSelector(WalletUtils.SmartWalletCallFailed.selector, invalidAddress));

        // Mock the call to fail
        vm.mockCallRevert(
            invalidAddress,
            abi.encodeWithSelector(ISmartWallet.claimAndRedistributeYield.selector, mockAssetToken),
            "CallFailed"
        );

        yieldToken.requestYield(invalidAddress);
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

}
