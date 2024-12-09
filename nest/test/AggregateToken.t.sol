// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { AggregateToken } from "../src/AggregateToken.sol";
import { IComponentToken } from "../src/interfaces/IComponentToken.sol";
import { AggregateTokenProxy } from "../src/proxy/AggregateTokenProxy.sol";
import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { MockInvalidToken } from "../src/mocks/MockInvalidToken.sol";
import { MockUSDC } from "../src/mocks/MockUSDC.sol";

contract AggregateTokenTest is Test {

    AggregateToken public token;
    MockUSDC public usdc;
    MockUSDC public newUsdc;
    address public owner;
    address public user1;
    address public user2;

    // Events
    event AssetTokenUpdated(IERC20 indexed oldAsset, IERC20 indexed newAsset);
    event ComponentTokenListed(IComponentToken indexed componentToken);
    event ComponentTokenUnlisted(IComponentToken indexed componentToken);
    event ComponentTokenBought(
        address indexed buyer, IComponentToken indexed componentToken, uint256 componentTokenAmount, uint256 assets
    );
    event ComponentTokenSold(
        address indexed seller, IComponentToken indexed componentToken, uint256 componentTokenAmount, uint256 assets
    );
    event Paused();
    event Unpaused();
    event ComponentTokenRemoved(IComponentToken indexed componentToken);

    event ComponentTokenBuyRequested(
        address indexed buyer, IComponentToken indexed componentToken, uint256 assets, uint256 requestId
    );

    event ComponentTokenSellRequested(
        address indexed seller, IComponentToken indexed componentToken, uint256 componentTokenAmount, uint256 requestId
    );

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy tokens
        usdc = new MockUSDC();
        newUsdc = new MockUSDC();

        // Deploy through proxy
        AggregateToken impl = new AggregateToken();
        ERC1967Proxy proxy = new AggregateTokenProxy(
            address(impl),
            abi.encodeCall(
                AggregateToken.initialize,
                (
                    owner,
                    "Aggregate Token",
                    "AGG",
                    IComponentToken(address(usdc)),
                    1e18, // 1:1 askPrice
                    1e18 // 1:1 bidPrice
                )
            )
        );
        token = AggregateToken(address(proxy));

        // Setup initial balances and approvals
        usdc.mint(user1, 1000e6);
        vm.prank(user1);
        usdc.approve(address(token), type(uint256).max);
    }

    function testAddComponentToken() public {
        vm.startPrank(owner);

        // Should succeed first time
        token.addComponentToken(IComponentToken(address(newUsdc)));

        // Should fail second time
        vm.expectRevert(
            abi.encodeWithSelector(
                AggregateToken.ComponentTokenAlreadyListed.selector, IComponentToken(address(newUsdc))
            )
        );
        token.addComponentToken(IComponentToken(address(newUsdc)));

        vm.stopPrank();
    }

    function testRemoveComponentToken() public {
        vm.startPrank(owner);

        // Add a token first
        token.addComponentToken(IComponentToken(address(newUsdc)));

        // Should fail when trying to remove current asset
        vm.expectRevert(
            abi.encodeWithSelector(AggregateToken.ComponentTokenIsAsset.selector, IComponentToken(address(usdc)))
        );
        token.removeComponentToken(IComponentToken(address(usdc)));

        // Should succeed with non-asset token
        token.removeComponentToken(IComponentToken(address(newUsdc)));

        // Should fail when trying to remove non-existent token
        vm.expectRevert(
            abi.encodeWithSelector(AggregateToken.ComponentTokenNotListed.selector, IComponentToken(address(newUsdc)))
        );
        token.removeComponentToken(IComponentToken(address(newUsdc)));

        vm.stopPrank();
    }

    function testPauseUnpause() public {
        vm.startPrank(owner);

        // Should start unpaused
        assertFalse(token.isPaused());

        // Should pause
        vm.expectEmit(address(token));
        emit Paused();
        token.pause();
        assertTrue(token.isPaused());

        // Should fail when already paused
        vm.expectRevert(AggregateToken.AlreadyPaused.selector);
        token.pause();

        // Should unpause
        vm.expectEmit(address(token));
        emit Unpaused();
        token.unpause();
        assertFalse(token.isPaused());

        // Should fail when already unpaused
        vm.expectRevert(AggregateToken.NotPaused.selector);
        token.unpause();

        vm.stopPrank();
    }

    function testSetPrices() public {
        // Grant price updater role
        bytes32 priceUpdaterRole = token.PRICE_UPDATER_ROLE();
        vm.startPrank(owner);
        token.grantRole(priceUpdaterRole, owner);

        // Test ask price
        token.setAskPrice(2e18);
        assertEq(token.getAskPrice(), 2e18);

        // Test bid price
        token.setBidPrice(1.5e18);
        assertEq(token.getBidPrice(), 1.5e18);

        vm.stopPrank();
    }

    function testConversion() public {
        // Test convertToShares
        assertEq(token.convertToShares(2e18), 2e18); // With askPrice = 1e18, 2 assets = 2 shares

        // Test convertToAssets
        assertEq(token.convertToAssets(2e18), 2e18); // With bidPrice = 1e18, 2 shares = 2 assets

        // Test with different prices
        vm.startPrank(owner);
        token.grantRole(token.PRICE_UPDATER_ROLE(), owner);
        token.setAskPrice(2e18); // 2:1 ratio
        token.setBidPrice(0.5e18); // 1:2 ratio
        vm.stopPrank();

        assertEq(token.convertToShares(2e18), 1e18); // 2 assets = 1 share at 2:1 ratio
        assertEq(token.convertToAssets(2e18), 1e18); // 2 shares = 1 asset at 1:2 ratio
    }

    function testDeposit() public {
        // Test deposit when paused
        vm.prank(owner);
        token.pause();

        vm.expectRevert(AggregateToken.DepositPaused.selector);
        token.deposit(1e18, address(this), address(this));

        // Test successful deposit
        vm.prank(owner);
        token.unpause();

        vm.startPrank(user1);
        usdc.approve(address(token), 1e18);
        uint256 shares = token.deposit(1e18, user1, user1);
        assertEq(shares, 1e18);
        assertEq(token.balanceOf(user1), 1e18);
        vm.stopPrank();
    }

    function testRedeem() public {
        // Setup: First deposit some tokens
        vm.startPrank(user1);
        usdc.approve(address(token), 1e18);
        token.deposit(1e18, user1, user1);

        // Test redeem
        uint256 assets = token.redeem(1e18, user1, user1);
        assertEq(assets, 1e18);
        assertEq(token.balanceOf(user1), 0);
        assertEq(usdc.balanceOf(user1), 1000e6); // Back to original balance
        vm.stopPrank();
    }

    function testTotalAssets() public {
        assertEq(token.totalAssets(), 0);

        // Deposit some assets
        vm.startPrank(user1);
        usdc.approve(address(token), 1e18);
        token.deposit(1e18, user1, user1);
        assertEq(token.totalAssets(), 1e18);
        vm.stopPrank();
    }

    function testApproveComponentToken() public {
        vm.startPrank(owner);

        // Test ComponentTokenNotListed error
        vm.expectRevert(
            abi.encodeWithSelector(AggregateToken.ComponentTokenNotListed.selector, IComponentToken(address(newUsdc)))
        );
        token.approveComponentToken(IComponentToken(address(newUsdc)), 1e6);

        // Test successful approval
        token.addComponentToken(IComponentToken(address(newUsdc)));
        token.approveComponentToken(IComponentToken(address(newUsdc)), 1e6);
        assertEq(usdc.allowance(address(token), address(newUsdc)), 1e6);

        vm.stopPrank();
    }

    function testComponentTokenOperations() public {
        vm.startPrank(owner);

        // Test buyComponentToken
        token.addComponentToken(IComponentToken(address(newUsdc)));
        vm.expectEmit(address(token));
        emit ComponentTokenBought(owner, IComponentToken(address(newUsdc)), 1e18, 1e18);
        token.buyComponentToken(IComponentToken(address(newUsdc)), 1e18);

        // Test sellComponentToken
        vm.expectEmit(address(token));
        emit ComponentTokenSold(owner, IComponentToken(address(newUsdc)), 1e18, 1e18);
        token.sellComponentToken(IComponentToken(address(newUsdc)), 1e18);

        // Test requestBuyComponentToken
        vm.expectEmit(address(token));
        emit ComponentTokenBuyRequested(owner, IComponentToken(address(newUsdc)), 1e18, 0);
        token.requestBuyComponentToken(IComponentToken(address(newUsdc)), 1e18);

        // Test requestSellComponentToken
        vm.expectEmit(address(token));
        emit ComponentTokenSellRequested(owner, IComponentToken(address(newUsdc)), 1e18, 0);
        token.requestSellComponentToken(IComponentToken(address(newUsdc)), 1e18);

        vm.stopPrank();
    }

    function testGetters() public {
        // Test getComponentTokenList
        IComponentToken[] memory list = token.getComponentTokenList();
        assertEq(list.length, 1);
        assertEq(address(list[0]), address(usdc));

        // Test getComponentToken
        assertTrue(token.getComponentToken(IComponentToken(address(usdc))));
        assertFalse(token.getComponentToken(IComponentToken(address(newUsdc))));
    }
    /*
    function testSupportsInterface() public {
        // Test standard interfaces
        assertTrue(token.supportsInterface(type(IERC20).interfaceId));
        assertTrue(token.supportsInterface(type(IERC4626).interfaceId));
        assertTrue(token.supportsInterface(type(IAccessControl).interfaceId));

        // Test custom interfaces
        assertTrue(token.supportsInterface(type(IComponentToken).interfaceId));
        assertTrue(token.supportsInterface(type(IAggregateToken).interfaceId));
    }
    */
    // Helper function for access control error message

    function accessControlErrorMessage(address account, bytes32 role) internal pure returns (bytes memory) {
        return abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(account),
            " is missing role ",
            Strings.toHexString(uint256(role), 32)
        );
    }

}
