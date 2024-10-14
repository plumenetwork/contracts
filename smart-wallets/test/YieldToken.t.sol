// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import { YieldToken } from "../src/token/YieldToken.sol";
import { MockSmartWallet } from "../src/mocks/MockSmartWallet.sol";
import { MockAssetToken } from "../src/mocks/MockAssetToken.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


import "../src/interfaces/IAssetToken.sol";


contract YieldTokenTest is Test {
    YieldToken yieldToken;
    ERC20Mock currencyToken;
    MockAssetToken assetToken;
    address owner;
    address user1;
    address user2;

    function setUp() public {
        owner = address(this);
        user1 = address(0x123);
        user2 = address(0x456);

        // Deploy mock ERC20 token (CurrencyToken)
        currencyToken = new ERC20Mock();

        // Deploy mock AssetToken
        assetToken = new MockAssetToken(IERC20(address(currencyToken)));

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

    function testInitialDeployment() public {
        assertEq(yieldToken.name(), "Yield Token");
        assertEq(yieldToken.symbol(), "YLT");
        assertEq(yieldToken.balanceOf(owner), 100 ether);
    }

    function testInvalidCurrencyTokenOnDeploy() public {
        ERC20Mock invalidCurrencyToken = new ERC20Mock();
        
        vm.expectRevert(abi.encodeWithSelector(YieldToken.InvalidCurrencyToken.selector, address(invalidCurrencyToken), address(currencyToken)));
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
    }

    function testMintingByOwner() public {
        yieldToken.mint(user1, 50 ether);
        assertEq(yieldToken.balanceOf(user1), 50 ether);
    }
/*
    function testMintingByNonOwnerFails() public {
        vm.prank(user1);  // Use user1 for this call
        vm.expectRevert("Ownable: caller is not the owner");
        yieldToken.mint(user2, 50 ether);
    }

    function testReceiveYieldWithValidTokens() public {
        currencyToken.approve(address(yieldToken), 10 ether);
        yieldToken.receiveYield(assetToken, currencyToken, 10 ether);
        // Optionally check internal states or events for yield deposit
    }
*/
    function testReceiveYieldWithInvalidAssetToken() public {
        MockAssetToken invalidAssetToken = new MockAssetToken(IERC20(address(currencyToken)));

        vm.expectRevert(abi.encodeWithSelector(YieldToken.InvalidAssetToken.selector, address(invalidAssetToken), address(assetToken)));
        yieldToken.receiveYield(invalidAssetToken, currencyToken, 10 ether);
    }

    function testReceiveYieldWithInvalidCurrencyToken() public {
        ERC20Mock invalidCurrencyToken = new ERC20Mock();
        
        vm.expectRevert(abi.encodeWithSelector(YieldToken.InvalidCurrencyToken.selector, address(invalidCurrencyToken), address(currencyToken)));
        yieldToken.receiveYield(assetToken, invalidCurrencyToken, 10 ether);
    }

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

