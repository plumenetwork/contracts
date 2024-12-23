// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ComponentToken } from "../src/ComponentToken.sol";

import { IComponentToken } from "../src/interfaces/IComponentToken.sol";
import { IERC7575 } from "../src/interfaces/IERC7575.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Test } from "forge-std/Test.sol";

import { MockComponentToken } from "../src/mocks/MockComponentToken.sol";
import { MockERC20 } from "../src/mocks/MockERC20.sol";

contract ComponentTokenTest is Test {

    MockComponentToken public mockToken;
    MockERC20 public asset;
    address public owner;
    address public user;
    address public attacker;

    event DepositRequest(
        address indexed controller, address indexed owner, uint256 indexed requestId, address receiver, uint256 assets
    );

    event RedeemRequest(
        address indexed controller, address indexed owner, uint256 indexed requestId, address receiver, uint256 shares
    );

    function setUp() public {
        user = makeAddr("user");
        attacker = makeAddr("attacker");

        asset = new MockERC20("Mock Token", "MOCK");
        mockToken = new MockComponentToken();
        mockToken.initialize(address(this), "Component Token", "COMP", IERC20(address(asset)), true, true);

        asset.mint(address(this), 1_000_000e18);
        asset.transfer(user, 100e18);
        vm.label(user, "User");
    }

    function test_requestDeposit() public {
        vm.startPrank(user);
        asset.approve(address(mockToken), 1e19);

        vm.expectEmit(true, true, true, true);
        emit DepositRequest(user, user, 0, user, 1e19);
        mockToken.requestDeposit(1e19, user, user);

        assertEq(mockToken.pendingDepositRequest(0, user), 1e19);
        vm.stopPrank();
    }

    function test_requestRedeem() public {
        // First deposit to get some shares
        vm.startPrank(user);
        asset.approve(address(mockToken), 1e19);
        mockToken.deposit(1e19, user, user);

        // Now test redeem request
        vm.expectEmit(true, true, true, true);
        emit RedeemRequest(user, user, 0, user, 1e19);
        mockToken.requestRedeem(1e19, user, user);

        assertEq(mockToken.pendingRedeemRequest(0, user), 1e19);
        vm.stopPrank();
    }

    function test_deposit() public {
        vm.startPrank(user);
        asset.approve(address(mockToken), 1e19);
        uint256 shares = mockToken.deposit(1e19, user, user);
        assertEq(shares, 1e19);
        assertEq(mockToken.balanceOf(user), 1e19);
        vm.stopPrank();
    }

    function test_redeem() public {
        // First deposit
        vm.startPrank(user);
        asset.approve(address(mockToken), 1e19);
        mockToken.deposit(1e19, user, user);

        // Then redeem
        uint256 assets = mockToken.redeem(1e19, user, user);
        assertEq(assets, 1e19);
        assertEq(mockToken.balanceOf(user), 0);
        vm.stopPrank();
    }

    function test_unauthorized_deposit() public {
        vm.startPrank(attacker);
        vm.expectRevert(abi.encodeWithSelector(ComponentToken.Unauthorized.selector, attacker, user));
        mockToken.requestDeposit(1e19, user, user);
        vm.stopPrank();
    }

    function test_unauthorized_redeem() public {
        vm.startPrank(attacker);
        vm.expectRevert(abi.encodeWithSelector(ComponentToken.Unauthorized.selector, attacker, user));
        mockToken.requestRedeem(1e19, user, user);
        vm.stopPrank();
    }

    function test_zero_amount_deposit() public {
        vm.startPrank(user);
        vm.expectRevert(ComponentToken.ZeroAmount.selector);
        mockToken.requestDeposit(0, user, user);
        vm.stopPrank();
    }

    function test_zero_amount_redeem() public {
        vm.startPrank(user);
        vm.expectRevert(ComponentToken.ZeroAmount.selector);
        mockToken.requestRedeem(0, user, user);
        vm.stopPrank();
    }

    /*


    function test_initialization() public {
        assertEq(mockToken.name(), "Component Token");
        assertEq(mockToken.symbol(), "COMP");
        assertEq(address(mockToken.asset()), address(asset));
        assertTrue(mockToken.hasRole(mockToken.DEFAULT_ADMIN_ROLE(), owner));
        assertTrue(mockToken.hasRole(mockToken.ADMIN_ROLE(), owner));
        assertTrue(mockToken.hasRole(mockToken.UPGRADER_ROLE(), owner));
    }

    function test_requestDeposit() public {
        uint256 depositAmount = 10e18;
        
        vm.startPrank(user);
        asset.approve(address(mockToken), depositAmount);
        
        vm.expectEmit(true, true, true, true);
        emit DepositRequest(user, user, 0, user, depositAmount);
        
        mockToken.requestDeposit(depositAmount, user, user);
        vm.stopPrank();

        assertEq(mockToken.pendingDepositRequest(0, user), depositAmount);
    }

    function test_requestDeposit_unauthorized() public {
        uint256 depositAmount = 10e18;
        
        vm.startPrank(attacker);
        asset.approve(address(mockToken), depositAmount);
        
        vm.expectRevert(abi.encodeWithSelector(ComponentToken.Unauthorized.selector, attacker, user));
        mockToken.requestDeposit(depositAmount, user, user);
        vm.stopPrank();
    }

    function test_requestRedeem() public {
        // First mint some tokens to the user
        uint256 mintAmount = 10e18;
        vm.startPrank(user);
        asset.approve(address(mockToken), mintAmount);
        mockToken.deposit(mintAmount, user, user);

        // Now test redeem request
        vm.expectEmit(true, true, true, true);
        emit RedeemRequest(user, user, 0, user, mintAmount);
        
        mockToken.requestRedeem(mintAmount, user, user);
        vm.stopPrank();

        assertEq(mockToken.pendingRedeemRequest(0, user), mintAmount);
    }

    function test_supportsInterface() public {
        assertTrue(mockToken.supportsInterface(type(IERC20).interfaceId));
        assertTrue(mockToken.supportsInterface(type(IAccessControl).interfaceId));
        assertTrue(mockToken.supportsInterface(type(IERC7575).interfaceId));
        assertTrue(mockToken.supportsInterface(type(IComponentToken).interfaceId));
    }

    function testFuzz_requestDeposit(uint256 amount) public {
        vm.assume(amount > 0 && amount <= asset.balanceOf(user));
        
        vm.startPrank(user);
        asset.approve(address(mockToken), amount);
        mockToken.requestDeposit(amount, user, user);
        vm.stopPrank();

        assertEq(mockToken.pendingDepositRequest(0, user), amount);
    }

    function test_zeroAmountDeposit() public {
        vm.startPrank(user);
        vm.expectRevert(ComponentToken.ZeroAmount.selector);
        mockToken.requestDeposit(0, user, user);
        vm.stopPrank();
    }


     function test_ComponentToken_initialization() public {
        ComponentToken token = new ComponentToken();
        mockToken.initialize(address(this), "Component Token", "COMP", IERC20(address(mockToken)), true, true);

        assertEq(mockToken.name(), "Component Token");
        assertEq(mockToken.symbol(), "COMP");
        assertEq(address(mockToken.asset()), address(mockToken));
        assertTrue(mockToken.hasRole(mockToken.DEFAULT_ADMIN_ROLE(), address(this)));
        assertTrue(mockToken.hasRole(mockToken.ADMIN_ROLE(), address(this)));
        assertTrue(mockToken.hasRole(mockToken.UPGRADER_ROLE(), address(this)));
    }

    function test_ComponentToken_requestDeposit() public {
        ComponentToken token = new ComponentToken();
        mockToken.initialize(address(this), "Component Token", "COMP", IERC20(address(mockToken)), true, true);

        vm.startPrank(user);
        mockToken.approve(address(token), 1e19);
        
        vm.expectEmit(true, true, true, true);
        emit DepositRequest(user, user, 0, user, 1e19);
        mockToken.requestDeposit(1e19, user, user);

        assertEq(mockToken.pendingDepositRequest(0, user), 1e19);
        vm.stopPrank();
    }

    function test_ComponentToken_requestRedeem() public {
        ComponentToken token = new ComponentToken();
        mockToken.initialize(address(this), "Component Token", "COMP", IERC20(address(mockToken)), true, true);

        // First deposit to get some shares
        vm.startPrank(user);
        mockToken.approve(address(token), 1e19);
        mockToken.deposit(1e19, user, user);

        vm.expectEmit(true, true, true, true);
        emit RedeemRequest(user, user, 0, user, 1e19);
        mockToken.requestRedeem(1e19, user, user);

        assertEq(mockToken.pendingRedeemRequest(0, user), 1e19);
        vm.stopPrank();
    }

    function test_ComponentToken_deposit() public {
        ComponentToken token = new ComponentToken();
        mockToken.initialize(address(this), "Component Token", "COMP", IERC20(address(mockToken)), false, true);

        vm.startPrank(user);
        mockToken.approve(address(token), 1e19);
        uint256 shares = mockToken.deposit(1e19, user, user);
        assertEq(shares, 1e19);
        assertEq(mockToken.balanceOf(user), 1e19);
        vm.stopPrank();
    }

    function test_ComponentToken_redeem() public {
        ComponentToken token = new ComponentToken();
        mockToken.initialize(address(this), "Component Token", "COMP", IERC20(address(mockToken)), false, false);

        // First deposit
        vm.startPrank(user);
        mockToken.approve(address(token), 1e19);
        mockToken.deposit(1e19, user, user);

        // Then redeem
        uint256 assets = mockToken.redeem(1e19, user, user);
        assertEq(assets, 1e19);
        assertEq(mockToken.balanceOf(user), 0);
        vm.stopPrank();
    }

    function test_ComponentToken_convertToShares() public {
        ComponentToken token = new ComponentToken();
        mockToken.initialize(address(this), "Component Token", "COMP", IERC20(address(mockToken)), false, false);

        assertEq(mockToken.convertToShares(1e18), 1e18);
    }

    function test_ComponentToken_convertToAssets() public {
        ComponentToken token = new ComponentToken();
        mockToken.initialize(address(this), "Component Token", "COMP", IERC20(address(mockToken)), false, false);

        assertEq(mockToken.convertToAssets(1e18), 1e18);
    }

    function test_ComponentToken_totalAssets() public {
        ComponentToken token = new ComponentToken();
        mockToken.initialize(address(this), "Component Token", "COMP", IERC20(address(mockToken)), false, false);

        vm.startPrank(user);
        mockToken.approve(address(token), 1e19);
        mockToken.deposit(1e19, user, user);
        vm.stopPrank();

        assertEq(mockToken.totalAssets(), 1e19);
    }

    function test_ComponentToken_assetsOf() public {
        ComponentToken token = new ComponentToken();
        mockToken.initialize(address(this), "Component Token", "COMP", IERC20(address(mockToken)), false, false);

        vm.startPrank(user);
        mockToken.approve(address(token), 1e19);
        mockToken.deposit(1e19, user, user);
        vm.stopPrank();

        assertEq(mockToken.assetsOf(user), 1e19);
    }
    */

}
