// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Test } from "forge-std/Test.sol";

import { ReserveStaking } from "../src/ReserveStaking.sol";

contract ReserveStakingTest is Test {

    ReserveStaking staking;
    IERC20 sbtc;
    IERC20 stone;

    address owner = address(0x1234);
    address user1 = address(0xBEEF);
    address user2 = address(0xCAFE);
    address user3 = address(0xDEAD);

    uint256 constant INITIAL_BALANCE = 1000 ether;

    function setUp() public {
        ERC20Mock sbtcMock = new ERC20Mock();
        ERC20Mock stoneMock = new ERC20Mock();
        sbtcMock.mint(user1, INITIAL_BALANCE);
        sbtcMock.mint(user2, INITIAL_BALANCE);
        stoneMock.mint(user1, INITIAL_BALANCE);
        stoneMock.mint(user2, INITIAL_BALANCE);
        sbtc = IERC20(sbtcMock);
        stone = IERC20(stoneMock);

        ReserveStaking stakingImpl = new ReserveStaking();
        ERC1967Proxy stakingProxy = new ERC1967Proxy(
            address(stakingImpl), abi.encodeWithSelector(stakingImpl.initialize.selector, owner, sbtc, stone)
        );
        staking = ReserveStaking(address(stakingProxy));
    }

    function helper_initialStake(address user, uint256 sbtcAmount, uint256 stoneAmount) public {
        vm.startPrank(user);
        sbtc.approve(address(staking), sbtcAmount);
        stone.approve(address(staking), stoneAmount);
        vm.expectEmit(true, true, false, true, address(staking));
        emit ReserveStaking.Staked(user, sbtcAmount, stoneAmount, block.timestamp);
        staking.stake(sbtcAmount, stoneAmount);
        vm.stopPrank();

        assertEq(sbtc.balanceOf(address(staking)), sbtcAmount);
        assertEq(stone.balanceOf(address(staking)), stoneAmount);
        assertEq(staking.getSBTCTotalAmountStaked(), sbtcAmount);
        assertEq(staking.getSTONETotalAmountStaked(), stoneAmount);
        assertEq(staking.getUsers().length, 1);

        (
            uint256 sbtcAmountSeconds,
            uint256 sbtcAmountStaked,
            uint256 sbtcLastUpdate,
            uint256 stoneAmountSeconds,
            uint256 stoneAmountStaked,
            uint256 stoneLastUpdate
        ) = staking.getUserState(user);
        assertEq(sbtcAmountSeconds, 0);
        assertEq(stoneAmountSeconds, 0);
        assertEq(sbtcAmountStaked, sbtcAmount);
        assertEq(stoneAmountStaked, stoneAmount);
        assertEq(sbtcLastUpdate, block.timestamp);
        assertEq(stoneLastUpdate, block.timestamp);
    }

    function test_constructor() public {
        ReserveStaking stakingImpl = new ReserveStaking();
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        stakingImpl.initialize(owner, sbtc, stone);
    }

    function test_initialize() public view {
        assertEq(address(staking.getSBTC()), address(sbtc));
        assertEq(address(staking.getSTONE()), address(stone));
        assertEq(staking.getSBTCTotalAmountStaked(), 0);
        assertEq(staking.getSTONETotalAmountStaked(), 0);
        assertEq(staking.getUsers().length, 0);
        assertEq(staking.getEndTime(), 0);

        (
            uint256 sbtcAmountSeconds,
            uint256 sbtcAmountStaked,
            uint256 sbtcLastUpdate,
            uint256 stoneAmountSeconds,
            uint256 stoneAmountStaked,
            uint256 stoneLastUpdate
        ) = staking.getUserState(owner);
        assertEq(sbtcAmountSeconds, 0);
        assertEq(stoneAmountSeconds, 0);
        assertEq(sbtcAmountStaked, 0);
        assertEq(stoneAmountStaked, 0);
        assertEq(sbtcLastUpdate, 0);
        assertEq(stoneLastUpdate, 0);

        assertTrue(staking.hasRole(staking.DEFAULT_ADMIN_ROLE(), owner));
        assertTrue(staking.hasRole(staking.ADMIN_ROLE(), owner));
        assertTrue(staking.hasRole(staking.UPGRADER_ROLE(), owner));

        assertEq(sbtc.balanceOf(address(staking)), 0);
        assertEq(stone.balanceOf(address(staking)), 0);
        assertEq(sbtc.balanceOf(owner), 0);
        assertEq(stone.balanceOf(owner), 0);
        assertEq(sbtc.balanceOf(user1), INITIAL_BALANCE);
        assertEq(stone.balanceOf(user1), INITIAL_BALANCE);
        assertEq(sbtc.balanceOf(user2), INITIAL_BALANCE);
        assertEq(stone.balanceOf(user2), INITIAL_BALANCE);
    }

    function test_stakingEnded() public {
        vm.startPrank(owner);
        staking.withdraw();

        vm.expectRevert(abi.encodeWithSelector(ReserveStaking.StakingEnded.selector));
        staking.stake(100 ether, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(ReserveStaking.StakingEnded.selector));
        staking.withdraw();

        vm.stopPrank();
    }

    function test_withdrawFail() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user1, staking.ADMIN_ROLE()
            )
        );
        vm.prank(user1);
        staking.withdraw();
    }

    function test_withdraw() public {
        uint256 sbtcAmount = 100 ether;
        uint256 stoneAmount = 50 ether;
        uint256 timeskipAmount = 300;
        uint256 startTime = block.timestamp;
        helper_initialStake(user1, sbtcAmount, stoneAmount);

        (
            uint256 sbtcAmountSeconds,
            uint256 sbtcAmountStaked,
            uint256 sbtcLastUpdate,
            uint256 stoneAmountSeconds,
            uint256 stoneAmountStaked,
            uint256 stoneLastUpdate
        ) = staking.getUserState(user1);
        assertEq(sbtcAmountSeconds, 0);
        assertEq(stoneAmountSeconds, 0);
        assertEq(sbtcAmountStaked, sbtcAmount);
        assertEq(stoneAmountStaked, stoneAmount);
        assertEq(sbtcLastUpdate, startTime);
        assertEq(stoneLastUpdate, startTime);

        // Skip ahead in time by 300 seconds and check that AmountSeconds has changed
        vm.warp(startTime + timeskipAmount);
        (sbtcAmountSeconds, sbtcAmountStaked, sbtcLastUpdate, stoneAmountSeconds, stoneAmountStaked, stoneLastUpdate) =
            staking.getUserState(user1);
        assertEq(sbtcAmountSeconds, sbtcAmount * timeskipAmount);
        assertEq(stoneAmountSeconds, stoneAmount * timeskipAmount);
        assertEq(sbtcAmountStaked, sbtcAmount);
        assertEq(stoneAmountStaked, stoneAmount);
        assertEq(sbtcLastUpdate, startTime);
        assertEq(stoneLastUpdate, startTime);
        assertEq(sbtc.balanceOf(address(staking)), sbtcAmount);
        assertEq(stone.balanceOf(address(staking)), stoneAmount);

        vm.startPrank(owner);
        vm.expectEmit(true, true, false, true, address(staking));
        emit ReserveStaking.Withdrawn(owner, sbtcAmount, stoneAmount);
        staking.withdraw();
        vm.stopPrank();

        // Skip ahead in time by 300 seconds and check that AmountSeconds is fixed
        vm.warp(startTime + timeskipAmount * 2);
        (sbtcAmountSeconds, sbtcAmountStaked, sbtcLastUpdate, stoneAmountSeconds, stoneAmountStaked, stoneLastUpdate) =
            staking.getUserState(user1);
        assertEq(sbtcAmountSeconds, sbtcAmount * timeskipAmount);
        assertEq(stoneAmountSeconds, stoneAmount * timeskipAmount);
        assertEq(sbtcAmountStaked, sbtcAmount);
        assertEq(stoneAmountStaked, stoneAmount);
        assertEq(sbtcLastUpdate, startTime);
        assertEq(stoneLastUpdate, startTime);

        assertEq(sbtc.balanceOf(address(staking)), 0);
        assertEq(stone.balanceOf(address(staking)), 0);
        assertEq(staking.getSBTCTotalAmountStaked(), sbtcAmount);
        assertEq(staking.getSTONETotalAmountStaked(), stoneAmount);
        assertEq(staking.getUsers().length, 1);
        assertEq(staking.getEndTime(), startTime + timeskipAmount);
    }

    function test_stakeFail() public {
        uint256 sbtcAmount = 100 ether;
        uint256 stoneAmount = 50 ether;
        vm.startPrank(user3);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(staking), 0, sbtcAmount)
        );
        staking.stake(sbtcAmount, stoneAmount);

        sbtc.approve(address(staking), sbtcAmount);
        stone.approve(address(staking), stoneAmount);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, user3, 0, sbtcAmount));
        staking.stake(sbtcAmount, stoneAmount);

        vm.stopPrank();
    }

    function test_stake() public {
        uint256 sbtcAmount = 100 ether;
        uint256 stoneAmount = 50 ether;
        uint256 timeskipAmount = 300;
        uint256 startTime = block.timestamp;

        // Stake from user1
        helper_initialStake(user1, sbtcAmount, stoneAmount);

        (
            uint256 sbtcAmountSeconds,
            uint256 sbtcAmountStaked,
            uint256 sbtcLastUpdate,
            uint256 stoneAmountSeconds,
            uint256 stoneAmountStaked,
            uint256 stoneLastUpdate
        ) = staking.getUserState(user1);
        assertEq(sbtcAmountSeconds, 0);
        assertEq(stoneAmountSeconds, 0);
        assertEq(sbtcAmountStaked, sbtcAmount);
        assertEq(stoneAmountStaked, stoneAmount);
        assertEq(sbtcLastUpdate, startTime);
        assertEq(stoneLastUpdate, startTime);

        // Skip ahead in time by 300 seconds
        vm.warp(startTime + timeskipAmount);

        (sbtcAmountSeconds, sbtcAmountStaked, sbtcLastUpdate, stoneAmountSeconds, stoneAmountStaked, stoneLastUpdate) =
            staking.getUserState(user1);
        assertEq(sbtcAmountSeconds, sbtcAmount * timeskipAmount);
        assertEq(stoneAmountSeconds, stoneAmount * timeskipAmount);
        assertEq(sbtcAmountStaked, sbtcAmount);
        assertEq(stoneAmountStaked, stoneAmount);
        assertEq(sbtcLastUpdate, startTime);
        assertEq(stoneLastUpdate, startTime);

        // Stake from user2
        vm.startPrank(user2);
        sbtc.approve(address(staking), sbtcAmount);
        stone.approve(address(staking), stoneAmount);
        vm.expectEmit(true, true, false, true, address(staking));
        emit ReserveStaking.Staked(user2, sbtcAmount, stoneAmount, startTime + timeskipAmount);
        staking.stake(sbtcAmount, stoneAmount);
        vm.stopPrank();

        assertEq(sbtc.balanceOf(address(staking)), sbtcAmount * 2);
        assertEq(stone.balanceOf(address(staking)), stoneAmount * 2);
        (sbtcAmountSeconds, sbtcAmountStaked, sbtcLastUpdate, stoneAmountSeconds, stoneAmountStaked, stoneLastUpdate) =
            staking.getUserState(user2);
        assertEq(sbtcAmountSeconds, 0);
        assertEq(stoneAmountSeconds, 0);
        assertEq(sbtcAmountStaked, sbtcAmount);
        assertEq(stoneAmountStaked, stoneAmount);
        assertEq(sbtcLastUpdate, startTime + timeskipAmount);
        assertEq(stoneLastUpdate, startTime + timeskipAmount);
        assertEq(staking.getSBTCTotalAmountStaked(), sbtcAmount * 2);
        assertEq(staking.getSTONETotalAmountStaked(), stoneAmount * 2);
        assertEq(staking.getUsers().length, 2);

        // Skip ahead in time by 300 seconds
        // Then stake again from user1
        // Then skip ahead in time by another 300 seconds
        vm.warp(startTime + timeskipAmount * 2);
        vm.startPrank(user1);
        sbtc.approve(address(staking), sbtcAmount);
        stone.approve(address(staking), stoneAmount);
        vm.expectEmit(true, true, false, true, address(staking));
        emit ReserveStaking.Staked(user1, sbtcAmount, stoneAmount, startTime + timeskipAmount * 2);
        staking.stake(sbtcAmount, stoneAmount);
        vm.stopPrank();
        vm.warp(startTime + timeskipAmount * 3);

        (sbtcAmountSeconds, sbtcAmountStaked, sbtcLastUpdate, stoneAmountSeconds, stoneAmountStaked, stoneLastUpdate) =
            staking.getUserState(user1);
        assertEq(sbtcAmountSeconds, sbtcAmount * timeskipAmount * 4);
        assertEq(stoneAmountSeconds, stoneAmount * timeskipAmount * 4);
        assertEq(sbtcAmountStaked, sbtcAmount * 2);
        assertEq(stoneAmountStaked, stoneAmount * 2);
        assertEq(sbtcLastUpdate, startTime + timeskipAmount * 2);
        assertEq(stoneLastUpdate, startTime + timeskipAmount * 2);
        (sbtcAmountSeconds, sbtcAmountStaked, sbtcLastUpdate, stoneAmountSeconds, stoneAmountStaked, stoneLastUpdate) =
            staking.getUserState(user2);
        assertEq(sbtcAmountSeconds, sbtcAmount * timeskipAmount * 2);
        assertEq(stoneAmountSeconds, stoneAmount * timeskipAmount * 2);
        assertEq(sbtcAmountStaked, sbtcAmount);
        assertEq(stoneAmountStaked, stoneAmount);
        assertEq(sbtcLastUpdate, startTime + timeskipAmount);
        assertEq(stoneLastUpdate, startTime + timeskipAmount);

        assertEq(sbtc.balanceOf(address(staking)), sbtcAmount * 3);
        assertEq(stone.balanceOf(address(staking)), stoneAmount * 3);
        assertEq(staking.getSBTCTotalAmountStaked(), sbtcAmount * 3);
        assertEq(staking.getSTONETotalAmountStaked(), stoneAmount * 3);
        assertEq(staking.getUsers().length, 2);
    }

    function test_upgradeFail() public {
        address newImplementation = address(new ReserveStaking());
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user1, staking.UPGRADER_ROLE()
            )
        );
        vm.prank(user1);
        staking.upgradeToAndCall(newImplementation, "");
    }

    function test_upgrade() public {
        uint256 sbtcAmount = 100 ether;
        uint256 stoneAmount = 50 ether;
        helper_initialStake(user1, sbtcAmount, stoneAmount);

        // Test that all the storage variables are the same after upgrading
        assertEq(address(staking.getSBTC()), address(sbtc));
        assertEq(address(staking.getSTONE()), address(stone));
        assertEq(staking.getSBTCTotalAmountStaked(), sbtcAmount);
        assertEq(staking.getSTONETotalAmountStaked(), stoneAmount);
        assertEq(staking.getUsers().length, 1);

        (
            uint256 sbtcAmountSeconds,
            uint256 sbtcAmountStaked,
            uint256 sbtcLastUpdate,
            uint256 stoneAmountSeconds,
            uint256 stoneAmountStaked,
            uint256 stoneLastUpdate
        ) = staking.getUserState(user1);
        assertEq(sbtcAmountSeconds, 0);
        assertEq(stoneAmountSeconds, 0);
        assertEq(sbtcAmountStaked, sbtcAmount);
        assertEq(stoneAmountStaked, stoneAmount);
        assertEq(sbtcLastUpdate, block.timestamp);
        assertEq(stoneLastUpdate, block.timestamp);
    }

}
