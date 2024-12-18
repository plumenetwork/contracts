// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { MockAssetToken } from "../src/mocks/MockAssetToken.sol";

import { MockInvalidAssetToken } from "../src/mocks/MockInvalidAssetToken.sol";
import { MockSmartWallet } from "../src/mocks/MockSmartWallet.sol";
import { YieldToken } from "../src/token/YieldToken.sol";

import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";

import "../src/interfaces/IAssetToken.sol";

// This file is a big mess and should not be committed anywhere

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
        //invalidCurrencyToken = new ERC20Mock();
        invalidAssetToken = new MockInvalidAssetToken();
    }

    /*

    function setUp() public {
        owner = address(this);
        user1 = address(0x123);
        user2 = address(0x456);

        // Deploy mock ERC20 token (CurrencyToken)
        currencyToken = new ERC20Mock();

        // Deploy mock AssetToken
        assetToken = new MockAssetToken();
    //        assetToken = new MockAssetToken(IERC20(address(currencyToken)));

        // Deploy the YieldToken contract
        yieldToken = new YieldToken(
            owner, 
            "Yield Token", 
            "YLT", 
            IERC20(address(currencyToken)), 
            18, 
            "http://example.com", 
            IAssetToken(address(assetToken)), 
            100 ether
        );
    }
    */
    function testInitialDeployment() public {
        assertEq(yieldToken.name(), "Yield Token");
        assertEq(yieldToken.symbol(), "YLT");
        assertEq(yieldToken.balanceOf(owner), 100 ether);
    }
    /*
    function testInvalidCurrencyTokenOnDeploy() public {
        //ERC20Mock invalidCurrencyToken = new ERC20Mock();
        
    vm.expectRevert(abi.encodeWithSelector(YieldToken.InvalidCurrencyToken.selector, address(invalidCurrencyToken),
    address(currencyToken)));
        new YieldToken(
            owner, 
            "Yield Token", 
            "YLT", 
            IERC20(address(invalidCurrencyToken)), 
            18, 
            "http://example.com", 
            IAssetToken(address(assetToken)), 
            100 ether
        );
    }*/

    function testMintingByOwner() public {
        yieldToken.adminMint(user1, 50 ether);
        assertEq(yieldToken.balanceOf(user1), 50 ether);
    }
    /*
    function testMintingByNonOwnerFails() public {
        vm.prank(user1);  // Use user1 for this call
        vm.expectRevert("Ownable: caller is not the owner");
        yieldToken.adminMint(user2, 50 ether);
    }

    function testReceiveYieldWithValidTokens() public {
        currencyToken.approve(address(yieldToken), 10 ether);
        yieldToken.receiveYield(assetToken, currencyToken, 10 ether);
        // Optionally check internal states or events for yield deposit
    }

    function testReceiveYieldWithInvalidAssetToken() public {
        //MockAssetToken invalidAssetToken = new MockAssetToken();

    vm.expectRevert(abi.encodeWithSelector(YieldToken.InvalidAssetToken.selector, address(invalidAssetToken),
    address(assetToken)));
        yieldToken.receiveYield(invalidAssetToken, currencyToken, 10 ether);
    }

    function testReceiveYieldWithInvalidCurrencyToken() public {
        //ERC20Mock invalidCurrencyToken = new ERC20Mock();
        
    vm.expectRevert(abi.encodeWithSelector(YieldToken.InvalidCurrencyToken.selector, address(invalidCurrencyToken),
    address(currencyToken)));
        yieldToken.receiveYield(assetToken, invalidCurrencyToken, 10 ether);
    }*/

    function testRequestYieldSuccess() public {
        MockSmartWallet smartWallet = new MockSmartWallet();

        yieldToken.requestYield(address(smartWallet));
        // Optionally check that the smartWallet function was called properly
    }
    /*
    function testRequestYieldFailure() public {
        vm.expectRevert(abi.encodeWithSelector(YieldToken.SmartWalletCallFailed.selector, address(0)));
        yieldToken.requestYield(address(0));  // Invalid address
    }
    */

}
