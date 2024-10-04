// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { SBTCStaking } from "../src/SBTCStaking.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Test } from "forge-std/Test.sol";

contract SBTCStakingTest is Test {

    SBTCStaking sbtcStaking;
    IERC20 sbtc;

    address owner = address(0x1234);
    address user1 = address(0xBEEF);
    address user2 = address(0xCAFE);

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

    function test_initialize() public view {
        assertEq(address(sbtcStaking.getSBTC()), address(sbtc));
        assertEq(sbtcStaking.getTotalAmountStaked(), 0);
        assertEq(sbtcStaking.getUsers().length, 0);
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

    function test_stake() public {
        uint256 stakeAmount = 100 ether;
        uint256 timeskipAmount = 300;
        uint256 timestamp = block.timestamp;

        // Stake 100 SBTC from user1
        vm.startPrank(user1);
        sbtc.approve(address(sbtcStaking), stakeAmount);
        sbtcStaking.stake(stakeAmount);
        vm.stopPrank();

        assertEq(sbtc.balanceOf(address(sbtcStaking)), stakeAmount);
        (uint256 amountSeconds, uint256 amountStaked, uint256 lastUpdate) = sbtcStaking.getUserState(user1);
        assertEq(amountSeconds, 0);
        assertEq(amountStaked, stakeAmount);
        assertEq(lastUpdate, timestamp);
        assertEq(sbtcStaking.getTotalAmountStaked(), stakeAmount);
        assertEq(sbtcStaking.getUsers().length, 1);

        // Skip ahead in time by 300 seconds
        vm.warp(timestamp + timeskipAmount);

        (amountSeconds, amountStaked, lastUpdate) = sbtcStaking.getUserState(user1);
        assertEq(amountSeconds, stakeAmount * timeskipAmount);
        assertEq(amountStaked, stakeAmount);
        assertEq(lastUpdate, timestamp);

        // Stake 100 SBTC from user2
        vm.startPrank(user2);
        sbtc.approve(address(sbtcStaking), stakeAmount);
        sbtcStaking.stake(stakeAmount);
        vm.stopPrank();

        assertEq(sbtc.balanceOf(address(sbtcStaking)), stakeAmount * 2);
        (amountSeconds, amountStaked, lastUpdate) = sbtcStaking.getUserState(user2);
        assertEq(amountSeconds, 0);
        assertEq(amountStaked, stakeAmount);
        assertEq(lastUpdate, timestamp + timeskipAmount);
        assertEq(sbtcStaking.getTotalAmountStaked(), stakeAmount * 2);
        assertEq(sbtcStaking.getUsers().length, 2);

        // Skip ahead in time by 300 seconds
        // Then stake another 100 SBTC from user1
        // Then skip ahead in time by another 300 seconds
        vm.warp(timestamp + timeskipAmount * 2);
        vm.startPrank(user1);
        sbtc.approve(address(sbtcStaking), stakeAmount);
        sbtcStaking.stake(stakeAmount);
        vm.stopPrank();
        vm.warp(timestamp + timeskipAmount * 3);

        (amountSeconds, amountStaked, lastUpdate) = sbtcStaking.getUserState(user1);
        assertEq(amountSeconds, stakeAmount * timeskipAmount * 4);
        assertEq(amountStaked, stakeAmount * 2);
        assertEq(lastUpdate, timestamp + timeskipAmount * 2);
        (amountSeconds, amountStaked, lastUpdate) = sbtcStaking.getUserState(user2);
        assertEq(amountSeconds, stakeAmount * timeskipAmount * 2);
        assertEq(amountStaked, stakeAmount);
        assertEq(lastUpdate, timestamp + timeskipAmount);

        assertEq(sbtc.balanceOf(address(sbtcStaking)), stakeAmount * 3);
        assertEq(sbtcStaking.getTotalAmountStaked(), stakeAmount * 3);
        assertEq(sbtcStaking.getUsers().length, 2);
    }

}
