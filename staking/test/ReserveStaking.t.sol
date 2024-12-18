// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Test } from "forge-std/Test.sol";

import { ReserveStaking } from "../src/ReserveStaking.sol";
import { SBTC } from "../src/SBTC.sol";
import { STONE } from "../src/STONE.sol";
import { PlumePreReserveFund } from "../src/proxy/PlumePreReserveFund.sol";

contract MockPlumePreReserveFund is PlumePreReserveFund {

    constructor(address logic, bytes memory data) PlumePreReserveFund(logic, data) { }
    function test() public override { }

    function exposed_implementation() public view returns (address) {
        return _implementation();
    }

}

contract ReserveStakingTest is Test {

    ReserveStaking staking;
    TimelockController timelock;
    IERC20 sbtc;
    IERC20 stone;

    address owner = address(0x1234);
    address user1 = address(0xBEEF);
    address user2 = address(0xCAFE);
    address user3 = address(0xDEAD);

    uint256 constant INITIAL_BALANCE = 1000 ether;

    function setUp() public {
        vm.startPrank(owner);

        SBTC sbtcMock = new SBTC(owner);
        STONE stoneMock = new STONE(owner);
        sbtcMock.mint(user1, INITIAL_BALANCE);
        sbtcMock.mint(user2, INITIAL_BALANCE);
        stoneMock.mint(user1, INITIAL_BALANCE);
        stoneMock.mint(user2, INITIAL_BALANCE);
        sbtc = IERC20(sbtcMock);
        stone = IERC20(stoneMock);

        vm.stopPrank();

        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        proposers[0] = owner;
        executors[0] = owner;
        timelock = new TimelockController(0 seconds, proposers, executors, address(0));

        ReserveStaking stakingImpl = new ReserveStaking();
        MockPlumePreReserveFund plumeReserveFundProxy = new MockPlumePreReserveFund(
            address(stakingImpl), abi.encodeWithSelector(stakingImpl.initialize.selector, timelock, owner, sbtc, stone)
        );
        staking = ReserveStaking(address(plumeReserveFundProxy));

        assertEq(plumeReserveFundProxy.PROXY_NAME(), keccak256("PlumePreReserveFund"));
        assertEq(plumeReserveFundProxy.exposed_implementation(), address(stakingImpl));
    }

    function helper_initialStake(address user, uint256 sbtcAmount, uint256 stoneAmount) public {
        vm.startPrank(user);

        sbtc.approve(address(staking), sbtcAmount);
        stone.approve(address(staking), stoneAmount);
        vm.expectEmit(true, false, false, true, address(staking));
        emit ReserveStaking.Staked(user, sbtcAmount, stoneAmount);
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
        stakingImpl.initialize(timelock, owner, sbtc, stone);
    }

    function test_initialize() public view {
        assertEq(address(staking.getSBTC()), address(sbtc));
        assertEq(address(staking.getSTONE()), address(stone));
        assertEq(staking.getMultisig(), owner);
        assertEq(address(staking.getTimelock()), address(timelock));
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

        assertEq(sbtc.balanceOf(address(staking)), 0);
        assertEq(stone.balanceOf(address(staking)), 0);
        assertEq(sbtc.balanceOf(owner), 0);
        assertEq(stone.balanceOf(owner), 0);
        assertEq(sbtc.balanceOf(user1), INITIAL_BALANCE);
        assertEq(stone.balanceOf(user1), INITIAL_BALANCE);
        assertEq(sbtc.balanceOf(user2), INITIAL_BALANCE);
        assertEq(stone.balanceOf(user2), INITIAL_BALANCE);
    }

    function test_reinitializeFail() public {
        vm.startPrank(user1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user1, staking.ADMIN_ROLE()
            )
        );
        staking.reinitialize(user1, timelock);

        vm.stopPrank();

        vm.startPrank(owner);

        staking.reinitialize(owner, timelock);
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        staking.reinitialize(user1, timelock);

        vm.stopPrank();
    }

    function test_reinitialize() public {
        vm.startPrank(owner);

        assertEq(staking.getMultisig(), owner);
        assertEq(address(staking.getTimelock()), address(timelock));
        staking.reinitialize(user1, TimelockController(payable(user2)));
        assertEq(staking.getMultisig(), user1);
        assertEq(address(staking.getTimelock()), address(user2));

        vm.stopPrank();
    }

    function test_stakingEnded() public {
        vm.startPrank(address(timelock));
        staking.adminWithdraw();

        vm.expectRevert(abi.encodeWithSelector(ReserveStaking.StakingEnded.selector));
        staking.stake(100 ether, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(ReserveStaking.StakingEnded.selector));
        staking.adminWithdraw();
        vm.expectRevert(abi.encodeWithSelector(ReserveStaking.StakingEnded.selector));
        staking.withdraw(100 ether, 100 ether);

        vm.stopPrank();
    }

    function test_setMultisigFail() public {
        vm.expectRevert(abi.encodeWithSelector(ReserveStaking.Unauthorized.selector, user1, address(timelock)));
        vm.startPrank(user1);
        staking.setMultisig(user1);
        vm.stopPrank();
    }

    function test_setMultisig() public {
        assertEq(staking.getMultisig(), owner);

        vm.startPrank(address(timelock));
        staking.setMultisig(user1);
        vm.stopPrank();

        assertEq(staking.getMultisig(), user1);
    }

    function test_adminWithdrawFail() public {
        vm.expectRevert(abi.encodeWithSelector(ReserveStaking.Unauthorized.selector, user1, address(timelock)));
        vm.prank(user1);
        staking.adminWithdraw();
    }

    function test_adminWithdraw() public {
        uint256 sbtcAmount = 100 ether;
        uint256 stoneAmount = 50 ether;
        uint256 timeskipAmount = 300;
        uint256 startTime = 1;
        vm.warp(startTime);
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

        vm.startPrank(address(timelock));
        vm.expectEmit(true, false, false, true, address(staking));
        emit ReserveStaking.AdminWithdrawn(owner, sbtcAmount, stoneAmount);
        staking.adminWithdraw();
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

    function test_pauseFail() public {
        vm.startPrank(user1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user1, staking.ADMIN_ROLE()
            )
        );
        staking.pause();

        vm.stopPrank();

        vm.startPrank(owner);

        vm.expectEmit(false, false, false, true, address(staking));
        emit ReserveStaking.Paused();
        staking.pause();

        vm.expectRevert(abi.encodeWithSelector(ReserveStaking.AlreadyPaused.selector));
        staking.pause();

        vm.stopPrank();
    }

    function test_pause() public {
        vm.startPrank(owner);

        assertEq(staking.isPaused(), false);

        vm.expectEmit(false, false, false, true, address(staking));
        emit ReserveStaking.Paused();
        staking.pause();
        assertEq(staking.isPaused(), true);

        vm.expectRevert(abi.encodeWithSelector(ReserveStaking.DepositPaused.selector));
        staking.stake(100 ether, 0);

        vm.stopPrank();
    }

    function test_unpauseFail() public {
        vm.startPrank(user1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user1, staking.ADMIN_ROLE()
            )
        );
        staking.unpause();

        vm.stopPrank();

        vm.startPrank(owner);

        vm.expectRevert(abi.encodeWithSelector(ReserveStaking.NotPaused.selector));
        staking.unpause();

        vm.stopPrank();
    }

    function test_unpause() public {
        vm.startPrank(owner);

        staking.pause();
        assertEq(staking.isPaused(), true);

        vm.expectEmit(false, false, false, true, address(staking));
        emit ReserveStaking.Unpaused();
        staking.unpause();
        assertEq(staking.isPaused(), false);

        vm.stopPrank();
    }

    function test_withdrawFail() public {
        uint256 sbtcAmount = 100 ether;
        uint256 stoneAmount = 50 ether;

        // Stake from user1 so we can test withdrawals
        helper_initialStake(user1, sbtcAmount, stoneAmount);

        vm.startPrank(user1);

        uint256 sbtcWithdrawAmount = sbtcAmount + 1;
        uint256 stoneWithdrawAmount = stoneAmount + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                ReserveStaking.InsufficientStaked.selector,
                user1,
                sbtcWithdrawAmount,
                stoneWithdrawAmount,
                sbtcAmount,
                stoneAmount
            )
        );
        staking.withdraw(sbtcWithdrawAmount, stoneWithdrawAmount);

        vm.stopPrank();
    }

    function test_withdraw() public {
        uint256 sbtcAmount = 100 ether;
        uint256 stoneAmount = 50 ether;
        uint256 timeskipAmount = 300;
        uint256 startTime = 1;
        vm.warp(startTime);

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

        assertEq(sbtc.balanceOf(address(staking)), sbtcAmount);
        assertEq(stone.balanceOf(address(staking)), stoneAmount);
        assertEq(sbtc.balanceOf(user1), INITIAL_BALANCE - sbtcAmount);
        assertEq(stone.balanceOf(user1), INITIAL_BALANCE - stoneAmount);

        // Skip ahead in time by 300 seconds
        vm.warp(startTime + timeskipAmount);

        // Withdraw half of the staked amounts
        uint256 sbtcWithdrawAmount = sbtcAmount / 2;
        uint256 stoneWithdrawAmount = stoneAmount / 2;
        vm.startPrank(user1);
        vm.expectEmit(true, false, false, true, address(staking));
        emit ReserveStaking.Withdrawn(user1, sbtcWithdrawAmount, stoneWithdrawAmount);
        staking.withdraw(sbtcWithdrawAmount, stoneWithdrawAmount);
        vm.stopPrank();

        // Check updated balances and state
        (sbtcAmountSeconds, sbtcAmountStaked, sbtcLastUpdate, stoneAmountSeconds, stoneAmountStaked, stoneLastUpdate) =
            staking.getUserState(user1);
        assertEq(sbtcAmountSeconds, sbtcAmount * timeskipAmount / 2);
        assertEq(stoneAmountSeconds, stoneAmount * timeskipAmount / 2);
        assertEq(sbtcAmountStaked, sbtcAmount - sbtcWithdrawAmount);
        assertEq(stoneAmountStaked, stoneAmount - stoneWithdrawAmount);
        assertEq(sbtcLastUpdate, startTime + timeskipAmount);
        assertEq(stoneLastUpdate, startTime + timeskipAmount);

        assertEq(sbtc.balanceOf(address(staking)), sbtcAmount / 2);
        assertEq(stone.balanceOf(address(staking)), stoneAmount / 2);
        assertEq(sbtc.balanceOf(user1), INITIAL_BALANCE - sbtcAmount / 2);
        assertEq(stone.balanceOf(user1), INITIAL_BALANCE - stoneAmount / 2);

        // Skip ahead in time by another 300 seconds
        vm.warp(startTime + timeskipAmount * 2);

        // Withdraw remaining amounts
        vm.startPrank(user1);
        vm.expectEmit(true, false, false, true, address(staking));
        emit ReserveStaking.Withdrawn(user1, sbtcAmount - sbtcWithdrawAmount, stoneAmount - stoneWithdrawAmount);
        staking.withdraw(sbtcAmount - sbtcWithdrawAmount, stoneAmount - stoneWithdrawAmount);
        vm.stopPrank();

        // Check final balances and state
        (sbtcAmountSeconds, sbtcAmountStaked, sbtcLastUpdate, stoneAmountSeconds, stoneAmountStaked, stoneLastUpdate) =
            staking.getUserState(user1);
        assertEq(sbtcAmountSeconds, 0);
        assertEq(stoneAmountSeconds, 0);
        assertEq(sbtcAmountStaked, 0);
        assertEq(stoneAmountStaked, 0);
        assertEq(sbtcLastUpdate, startTime + timeskipAmount * 2);
        assertEq(stoneLastUpdate, startTime + timeskipAmount * 2);

        assertEq(sbtc.balanceOf(address(staking)), 0);
        assertEq(stone.balanceOf(address(staking)), 0);
        assertEq(sbtc.balanceOf(user1), INITIAL_BALANCE);
        assertEq(stone.balanceOf(user1), INITIAL_BALANCE);
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
        uint256 startTime = 1;
        vm.warp(startTime);

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
        vm.expectEmit(true, false, false, true, address(staking));
        emit ReserveStaking.Staked(user2, sbtcAmount, 0);
        staking.stake(sbtcAmount, 0);
        vm.stopPrank();

        assertEq(sbtc.balanceOf(address(staking)), sbtcAmount * 2);
        assertEq(stone.balanceOf(address(staking)), stoneAmount);
        (sbtcAmountSeconds, sbtcAmountStaked, sbtcLastUpdate, stoneAmountSeconds, stoneAmountStaked, stoneLastUpdate) =
            staking.getUserState(user2);
        assertEq(sbtcAmountSeconds, 0);
        assertEq(stoneAmountSeconds, 0);
        assertEq(sbtcAmountStaked, sbtcAmount);
        assertEq(stoneAmountStaked, 0);
        assertEq(sbtcLastUpdate, startTime + timeskipAmount);
        assertEq(stoneLastUpdate, 0);
        assertEq(staking.getSBTCTotalAmountStaked(), sbtcAmount * 2);
        assertEq(staking.getSTONETotalAmountStaked(), stoneAmount);
        assertEq(staking.getUsers().length, 2);

        // Skip ahead in time by 300 seconds
        // Then stake again from user1
        // Then skip ahead in time by another 300 seconds
        vm.warp(startTime + timeskipAmount * 2);
        vm.startPrank(user1);
        stone.approve(address(staking), stoneAmount);
        vm.expectEmit(true, false, false, true, address(staking));
        emit ReserveStaking.Staked(user1, 0, stoneAmount);
        staking.stake(0, stoneAmount);
        vm.stopPrank();
        vm.warp(startTime + timeskipAmount * 3);

        (sbtcAmountSeconds, sbtcAmountStaked, sbtcLastUpdate, stoneAmountSeconds, stoneAmountStaked, stoneLastUpdate) =
            staking.getUserState(user1);
        assertEq(sbtcAmountSeconds, sbtcAmount * timeskipAmount * 3);
        assertEq(stoneAmountSeconds, stoneAmount * timeskipAmount * 4);
        assertEq(sbtcAmountStaked, sbtcAmount);
        assertEq(stoneAmountStaked, stoneAmount * 2);
        assertEq(sbtcLastUpdate, startTime);
        assertEq(stoneLastUpdate, startTime + timeskipAmount * 2);
        (sbtcAmountSeconds, sbtcAmountStaked, sbtcLastUpdate, stoneAmountSeconds, stoneAmountStaked, stoneLastUpdate) =
            staking.getUserState(user2);
        assertEq(sbtcAmountSeconds, sbtcAmount * timeskipAmount * 2);
        assertEq(stoneAmountSeconds, 0);
        assertEq(sbtcAmountStaked, sbtcAmount);
        assertEq(stoneAmountStaked, 0);
        assertEq(sbtcLastUpdate, startTime + timeskipAmount);
        assertEq(stoneLastUpdate, 0);

        assertEq(sbtc.balanceOf(address(staking)), sbtcAmount * 2);
        assertEq(stone.balanceOf(address(staking)), stoneAmount * 2);
        assertEq(staking.getSBTCTotalAmountStaked(), sbtcAmount * 2);
        assertEq(staking.getSTONETotalAmountStaked(), stoneAmount * 2);
        assertEq(staking.getUsers().length, 2);
    }

    function test_upgradeFail() public {
        address newImplementation = address(new ReserveStaking());
        vm.expectRevert(abi.encodeWithSelector(ReserveStaking.Unauthorized.selector, user1, address(timelock)));
        vm.prank(user1);
        staking.upgradeToAndCall(newImplementation, "");
    }

    function test_upgrade() public {
        uint256 sbtcAmount = 100 ether;
        uint256 stoneAmount = 50 ether;
        helper_initialStake(user1, sbtcAmount, stoneAmount);

        address newImplementation = address(new ReserveStaking());
        vm.startPrank(address(timelock));
        staking.upgradeToAndCall(newImplementation, "");
        vm.stopPrank();

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
