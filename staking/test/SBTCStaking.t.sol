// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Test } from "forge-std/Test.sol";

import { SBTCStaking } from "../src/SBTCStaking.sol";

contract SBTCStakingTest is Test {

    SBTCStaking sbtcStaking;
    IERC20 sbtc;

    address owner = address(0x1234);
    address user1 = address(0xBEEF);
    address user2 = address(0xCAFE);
    address user3 = address(0xDEAD);

    uint256 constant INITIAL_BALANCE = 1000 ether;

    function setUp() public {
        ERC20Mock sbtcMock = new ERC20Mock();
        sbtcMock.mint(user1, INITIAL_BALANCE);
        sbtcMock.mint(user2, INITIAL_BALANCE);
        sbtc = IERC20(sbtcMock);

        SBTCStaking sbtcStakingImpl = new SBTCStaking();
        ERC1967Proxy sbtcStakingProxy = new ERC1967Proxy(
            address(sbtcStakingImpl), abi.encodeWithSelector(sbtcStakingImpl.initialize.selector, owner, sbtc)
        );
        sbtcStaking = SBTCStaking(address(sbtcStakingProxy));
    }

    function helper_initialStake(address user, uint256 stakeAmount) public {
        vm.startPrank(user);
        sbtc.approve(address(sbtcStaking), stakeAmount);
        vm.expectEmit(true, false, false, true, address(sbtcStaking));
        emit SBTCStaking.Staked(user, stakeAmount, block.timestamp);
        sbtcStaking.stake(stakeAmount);
        vm.stopPrank();

        assertEq(sbtc.balanceOf(address(sbtcStaking)), stakeAmount);
        assertEq(sbtcStaking.getTotalAmountStaked(), stakeAmount);
        assertEq(sbtcStaking.getUsers().length, 1);
    }

    function test_constructor() public {
        SBTCStaking sbtcStakingImpl = new SBTCStaking();
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        sbtcStakingImpl.initialize(owner, sbtc);
    }

    function test_initialize() public view {
        assertEq(address(sbtcStaking.getSBTC()), address(sbtc));
        assertEq(sbtcStaking.getTotalAmountStaked(), 0);
        assertEq(sbtcStaking.getUsers().length, 0);
        assertEq(sbtcStaking.getEndTime(), 0);

        (uint256 amountSeconds, uint256 amountStaked, uint256 lastUpdate) = sbtcStaking.getUserState(user1);
        assertEq(amountSeconds, 0);
        assertEq(amountStaked, 0);
        assertEq(lastUpdate, 0);

        assertTrue(sbtcStaking.hasRole(sbtcStaking.DEFAULT_ADMIN_ROLE(), owner));
        assertTrue(sbtcStaking.hasRole(sbtcStaking.ADMIN_ROLE(), owner));
        assertTrue(sbtcStaking.hasRole(sbtcStaking.UPGRADER_ROLE(), owner));

        assertEq(sbtc.balanceOf(address(sbtcStaking)), 0);
        assertEq(sbtc.balanceOf(owner), 0);
        assertEq(sbtc.balanceOf(user1), INITIAL_BALANCE);
        assertEq(sbtc.balanceOf(user2), INITIAL_BALANCE);
    }

    function test_stakingEnded() public {
        vm.startPrank(owner);
        sbtcStaking.withdraw();

        vm.expectRevert(abi.encodeWithSelector(SBTCStaking.StakingEnded.selector));
        sbtcStaking.stake(100 ether);
        vm.expectRevert(abi.encodeWithSelector(SBTCStaking.StakingEnded.selector));
        sbtcStaking.withdraw();

        vm.stopPrank();
    }

    function test_withdrawFail() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user1, sbtcStaking.ADMIN_ROLE()
            )
        );
        vm.startPrank(user1);
        sbtcStaking.withdraw();
        vm.stopPrank();
    }

    function test_withdraw() public {
        uint256 stakeAmount = 100 ether;
        uint256 timeskipAmount = 300;
        uint256 startTime = block.timestamp;
        helper_initialStake(user1, stakeAmount);

        (uint256 amountSeconds, uint256 amountStaked, uint256 lastUpdate) = sbtcStaking.getUserState(user1);
        assertEq(amountSeconds, 0);
        assertEq(amountStaked, stakeAmount);
        assertEq(lastUpdate, startTime);

        // Skip ahead in time by 300 seconds and check that amountSeconds has changed
        vm.warp(startTime + timeskipAmount);
        (amountSeconds, amountStaked, lastUpdate) = sbtcStaking.getUserState(user1);
        assertEq(amountSeconds, stakeAmount * timeskipAmount);
        assertEq(amountStaked, stakeAmount);
        assertEq(lastUpdate, startTime);
        assertEq(sbtc.balanceOf(address(sbtcStaking)), stakeAmount);

        vm.startPrank(owner);
        vm.expectEmit(true, false, false, true, address(sbtcStaking));
        emit SBTCStaking.Withdrawn(owner, stakeAmount);
        sbtcStaking.withdraw();
        vm.stopPrank();

        // Skip ahead in time by 300 seconds and check that amountSeconds is fixed
        vm.warp(startTime + timeskipAmount * 2);
        (amountSeconds, amountStaked, lastUpdate) = sbtcStaking.getUserState(user1);
        assertEq(amountSeconds, stakeAmount * timeskipAmount);
        assertEq(amountStaked, stakeAmount);
        assertEq(lastUpdate, startTime);

        assertEq(sbtc.balanceOf(address(sbtcStaking)), 0);
        assertEq(sbtcStaking.getTotalAmountStaked(), stakeAmount);
        assertEq(sbtcStaking.getUsers().length, 1);
        assertEq(sbtcStaking.getEndTime(), startTime + timeskipAmount);
    }

    function test_stakeFail() public {
        uint256 stakeAmount = 100 ether;
        vm.startPrank(user3);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(sbtcStaking), 0, stakeAmount
            )
        );
        sbtcStaking.stake(stakeAmount);

        sbtc.approve(address(sbtcStaking), stakeAmount);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, user3, 0, stakeAmount));
        sbtcStaking.stake(stakeAmount);

        vm.stopPrank();
    }

    function test_stake() public {
        uint256 stakeAmount = 100 ether;
        uint256 timeskipAmount = 300;
        uint256 startTime = block.timestamp;

        // Stake 100 SBTC from user1
        helper_initialStake(user1, stakeAmount);

        (uint256 amountSeconds, uint256 amountStaked, uint256 lastUpdate) = sbtcStaking.getUserState(user1);
        assertEq(amountSeconds, 0);
        assertEq(amountStaked, stakeAmount);
        assertEq(lastUpdate, startTime);

        // Skip ahead in time by 300 seconds
        vm.warp(startTime + timeskipAmount);

        (amountSeconds, amountStaked, lastUpdate) = sbtcStaking.getUserState(user1);
        assertEq(amountSeconds, stakeAmount * timeskipAmount);
        assertEq(amountStaked, stakeAmount);
        assertEq(lastUpdate, startTime);

        // Stake 100 SBTC from user2
        vm.startPrank(user2);
        sbtc.approve(address(sbtcStaking), stakeAmount);
        vm.expectEmit(true, false, false, true, address(sbtcStaking));
        emit SBTCStaking.Staked(user2, stakeAmount, startTime + timeskipAmount);
        sbtcStaking.stake(stakeAmount);
        vm.stopPrank();

        assertEq(sbtc.balanceOf(address(sbtcStaking)), stakeAmount * 2);
        (amountSeconds, amountStaked, lastUpdate) = sbtcStaking.getUserState(user2);
        assertEq(amountSeconds, 0);
        assertEq(amountStaked, stakeAmount);
        assertEq(lastUpdate, startTime + timeskipAmount);
        assertEq(sbtcStaking.getTotalAmountStaked(), stakeAmount * 2);
        assertEq(sbtcStaking.getUsers().length, 2);

        // Skip ahead in time by 300 seconds
        // Then stake another 100 SBTC from user1
        // Then skip ahead in time by another 300 seconds
        vm.warp(startTime + timeskipAmount * 2);
        vm.startPrank(user1);
        sbtc.approve(address(sbtcStaking), stakeAmount);
        vm.expectEmit(true, false, false, true, address(sbtcStaking));
        emit SBTCStaking.Staked(user1, stakeAmount, startTime + timeskipAmount * 2);
        sbtcStaking.stake(stakeAmount);
        vm.stopPrank();
        vm.warp(startTime + timeskipAmount * 3);

        (amountSeconds, amountStaked, lastUpdate) = sbtcStaking.getUserState(user1);
        assertEq(amountSeconds, stakeAmount * timeskipAmount * 4);
        assertEq(amountStaked, stakeAmount * 2);
        assertEq(lastUpdate, startTime + timeskipAmount * 2);
        (amountSeconds, amountStaked, lastUpdate) = sbtcStaking.getUserState(user2);
        assertEq(amountSeconds, stakeAmount * timeskipAmount * 2);
        assertEq(amountStaked, stakeAmount);
        assertEq(lastUpdate, startTime + timeskipAmount);

        assertEq(sbtc.balanceOf(address(sbtcStaking)), stakeAmount * 3);
        assertEq(sbtcStaking.getTotalAmountStaked(), stakeAmount * 3);
        assertEq(sbtcStaking.getUsers().length, 2);
    }

    function test_upgradeFail() public {
        address newImplementation = address(new SBTCStaking());
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user1, sbtcStaking.UPGRADER_ROLE()
            )
        );
        vm.startPrank(user1);
        sbtcStaking.upgradeToAndCall(newImplementation, "");
        vm.stopPrank();
    }

    function test_upgrade() public {
        uint256 stakeAmount = 100 ether;
        helper_initialStake(user1, stakeAmount);

        address newImplementation = address(new SBTCStaking());
        vm.startPrank(owner);
        sbtcStaking.upgradeToAndCall(newImplementation, "");
        vm.stopPrank();

        // Test that all the storage variables are the same after upgrading
        assertEq(address(sbtcStaking.getSBTC()), address(sbtc));
        assertEq(sbtcStaking.getTotalAmountStaked(), stakeAmount);
        assertEq(sbtcStaking.getUsers().length, 1);

        (uint256 amountSeconds, uint256 amountStaked, uint256 lastUpdate) = sbtcStaking.getUserState(user1);
        assertEq(amountSeconds, 0);
        assertEq(amountStaked, stakeAmount);
        assertEq(lastUpdate, block.timestamp);
    }

}
