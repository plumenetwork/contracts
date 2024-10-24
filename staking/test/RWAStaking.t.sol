// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { RWAStaking } from "../src/RWAStaking.sol";
import { PlumePreStaking } from "../src/proxy/PlumePreStaking.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Test } from "forge-std/Test.sol";

contract MockPlumePreStaking is PlumePreStaking {

    constructor(address logic, bytes memory data) PlumePreStaking(logic, data) { }
    function test() public { }

    function exposed_implementation() public view returns (address) {
        return _implementation();
    }

}

contract RWAStakingTest is Test {

    RWAStaking rwaStaking;
    IERC20 usdc;
    IERC20 pusd;

    address owner = address(0x1234);
    address user1 = address(0xBEEF);
    address user2 = address(0xCAFE);
    address user3 = address(0xDEAD);

    uint256 constant INITIAL_BALANCE = 1000 ether;

    function setUp() public {
        ERC20Mock usdcMock = new ERC20Mock();
        usdcMock.mint(user1, INITIAL_BALANCE);
        usdcMock.mint(user2, INITIAL_BALANCE);
        usdc = IERC20(usdcMock);

        ERC20Mock pusdMock = new ERC20Mock();
        pusdMock.mint(user1, INITIAL_BALANCE);
        pusdMock.mint(user2, INITIAL_BALANCE);
        pusd = IERC20(pusdMock);

        RWAStaking rwaStakingImpl = new RWAStaking();
        MockPlumePreStaking plumePreStakingProxy = new MockPlumePreStaking(
            address(rwaStakingImpl), abi.encodeWithSelector(rwaStakingImpl.initialize.selector, owner)
        );
        rwaStaking = RWAStaking(address(plumePreStakingProxy));

        assertEq(plumePreStakingProxy.PROXY_NAME(), keccak256("PlumePreStaking"));
        assertEq(plumePreStakingProxy.exposed_implementation(), address(rwaStakingImpl));
    }

    function helper_initialStake(address user, uint256 stakeAmount) public {
        vm.startPrank(owner);
        rwaStaking.allowStablecoin(usdc);
        vm.stopPrank();

        vm.startPrank(user);
        usdc.approve(address(rwaStaking), stakeAmount);
        vm.expectEmit(true, true, false, true, address(rwaStaking));
        emit RWAStaking.Staked(user, usdc, stakeAmount);
        rwaStaking.stake(stakeAmount, usdc);
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(rwaStaking)), stakeAmount);
        assertEq(rwaStaking.getTotalAmountStaked(), stakeAmount);
        assertEq(rwaStaking.getUsers().length, 1);
        assertEq(rwaStaking.getAllowedStablecoins().length, 1);
        assertEq(rwaStaking.isAllowedStablecoin(usdc), true);
    }

    function test_constructor() public {
        RWAStaking rwaStakingImpl = new RWAStaking();
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        rwaStakingImpl.initialize(owner);
    }

    function test_initialize() public view {
        assertEq(rwaStaking.getTotalAmountStaked(), 0);
        assertEq(rwaStaking.getUsers().length, 0);
        (uint256 amountSeconds, uint256 amountStaked, uint256 lastUpdate) = rwaStaking.getUserState(user1);
        assertEq(amountSeconds, 0);
        assertEq(amountStaked, 0);
        assertEq(lastUpdate, 0);
        assertEq(rwaStaking.getAllowedStablecoins().length, 0);
        assertEq(rwaStaking.isAllowedStablecoin(usdc), false);
        assertEq(rwaStaking.getEndTime(), 0);

        assertTrue(rwaStaking.hasRole(rwaStaking.DEFAULT_ADMIN_ROLE(), owner));
        assertTrue(rwaStaking.hasRole(rwaStaking.ADMIN_ROLE(), owner));
        assertTrue(rwaStaking.hasRole(rwaStaking.UPGRADER_ROLE(), owner));

        assertEq(usdc.balanceOf(address(rwaStaking)), 0);
        assertEq(usdc.balanceOf(owner), 0);
        assertEq(usdc.balanceOf(user1), INITIAL_BALANCE);
        assertEq(usdc.balanceOf(user2), INITIAL_BALANCE);
        assertEq(pusd.balanceOf(address(rwaStaking)), 0);
        assertEq(pusd.balanceOf(owner), 0);
        assertEq(pusd.balanceOf(user1), INITIAL_BALANCE);
        assertEq(pusd.balanceOf(user2), INITIAL_BALANCE);
    }

    function test_stakingEnded() public {
        vm.startPrank(owner);
        rwaStaking.adminWithdraw();

        vm.expectRevert(abi.encodeWithSelector(RWAStaking.StakingEnded.selector));
        rwaStaking.stake(100 ether, usdc);
        vm.expectRevert(abi.encodeWithSelector(RWAStaking.StakingEnded.selector));
        rwaStaking.adminWithdraw();
        vm.expectRevert(abi.encodeWithSelector(RWAStaking.StakingEnded.selector));
        rwaStaking.withdraw(100 ether, usdc);

        vm.stopPrank();
    }

    function test_allowStablecoinFail() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user1, rwaStaking.ADMIN_ROLE()
            )
        );
        vm.startPrank(user1);
        rwaStaking.allowStablecoin(usdc);
        vm.stopPrank();

        vm.startPrank(owner);
        rwaStaking.allowStablecoin(usdc);

        vm.expectRevert(abi.encodeWithSelector(RWAStaking.AlreadyAllowedStablecoin.selector, usdc));
        rwaStaking.allowStablecoin(usdc);
        vm.stopPrank();
    }

    function test_allowStablecoin() public {
        vm.startPrank(owner);

        rwaStaking.allowStablecoin(usdc);
        assertEq(rwaStaking.getAllowedStablecoins().length, 1);
        assertEq(rwaStaking.isAllowedStablecoin(usdc), true);
        assertEq(rwaStaking.isAllowedStablecoin(pusd), false);

        rwaStaking.allowStablecoin(pusd);
        assertEq(rwaStaking.getAllowedStablecoins().length, 2);
        assertEq(rwaStaking.isAllowedStablecoin(pusd), true);

        vm.stopPrank();
    }

    function test_adminWithdrawFail() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user1, rwaStaking.ADMIN_ROLE()
            )
        );
        vm.startPrank(user1);
        rwaStaking.adminWithdraw();
        vm.stopPrank();
    }

    function test_adminWithdraw() public {
        uint256 stakeAmount = 100 ether;
        uint256 pusdStakeAmount = 30 ether;
        uint256 timeskipAmount = 300;
        uint256 startTime = block.timestamp;
        helper_initialStake(user1, stakeAmount);

        (uint256 amountSeconds, uint256 amountStaked, uint256 lastUpdate) = rwaStaking.getUserState(user1);
        assertEq(amountSeconds, 0);
        assertEq(amountStaked, stakeAmount);
        assertEq(lastUpdate, startTime);

        // Skip ahead in time by 300 seconds and check that amountSeconds has changed
        vm.warp(startTime + timeskipAmount);
        (amountSeconds, amountStaked, lastUpdate) = rwaStaking.getUserState(user1);

        assertEq(amountSeconds, stakeAmount * timeskipAmount);
        assertEq(amountStaked, stakeAmount);

        // block.timestap is 301, lastUpdate still 1
        //assertEq(lastUpdate, startTime);
        vm.startPrank(owner);
        rwaStaking.allowStablecoin(pusd);
        vm.stopPrank();
        vm.startPrank(user1);
        pusd.approve(address(rwaStaking), pusdStakeAmount);
        rwaStaking.stake(pusdStakeAmount, pusd);
        vm.stopPrank();
        assertEq(usdc.balanceOf(address(rwaStaking)), stakeAmount);
        assertEq(pusd.balanceOf(address(rwaStaking)), pusdStakeAmount);
        vm.startPrank(owner);
        vm.expectEmit(true, true, false, true, address(rwaStaking));
        emit RWAStaking.AdminWithdrawn(owner, usdc, stakeAmount);
        vm.expectEmit(true, true, false, true, address(rwaStaking));
        emit RWAStaking.AdminWithdrawn(owner, pusd, pusdStakeAmount);
        rwaStaking.adminWithdraw();
        vm.stopPrank();

        // Skip ahead in time by 300 seconds and check that amountSeconds is fixed
        vm.warp(startTime + timeskipAmount * 2);
        (amountSeconds, amountStaked, lastUpdate) = rwaStaking.getUserState(user1);
        assertEq(amountSeconds, stakeAmount * timeskipAmount);
        assertEq(amountStaked, stakeAmount + pusdStakeAmount);
        //assertEq(lastUpdate, startTime + timeskipAmount * 2);
        assertEq(usdc.balanceOf(address(rwaStaking)), 0);
        assertEq(pusd.balanceOf(address(rwaStaking)), 0);
        assertEq(rwaStaking.getTotalAmountStaked(), stakeAmount + pusdStakeAmount);
        assertEq(rwaStaking.getUsers().length, 1);
        //assertEq(rwaStaking.getEndTime(), startTime + timeskipAmount);
    }

    function test_pauseFail() public {
        vm.startPrank(user1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user1, rwaStaking.ADMIN_ROLE()
            )
        );
        rwaStaking.pause();

        vm.stopPrank();

        vm.startPrank(owner);

        vm.expectEmit(false, false, false, true, address(rwaStaking));
        emit RWAStaking.Paused();
        rwaStaking.pause();

        vm.expectRevert(abi.encodeWithSelector(RWAStaking.AlreadyPaused.selector));
        rwaStaking.pause();

        vm.stopPrank();
    }

    function test_pause() public {
        vm.startPrank(owner);

        assertEq(rwaStaking.isPaused(), false);

        vm.expectEmit(false, false, false, true, address(rwaStaking));
        emit RWAStaking.Paused();
        rwaStaking.pause();
        assertEq(rwaStaking.isPaused(), true);

        vm.expectRevert(abi.encodeWithSelector(RWAStaking.DepositPaused.selector));
        rwaStaking.stake(100 ether, usdc);

        vm.stopPrank();
    }

    function test_unpauseFail() public {
        vm.startPrank(user1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user1, rwaStaking.ADMIN_ROLE()
            )
        );
        rwaStaking.unpause();

        vm.stopPrank();

        vm.startPrank(owner);

        vm.expectRevert(abi.encodeWithSelector(RWAStaking.NotPaused.selector));
        rwaStaking.unpause();

        vm.stopPrank();
    }

    function test_unpause() public {
        vm.startPrank(owner);

        rwaStaking.pause();
        assertEq(rwaStaking.isPaused(), true);

        vm.expectEmit(false, false, false, true, address(rwaStaking));
        emit RWAStaking.Unpaused();
        rwaStaking.unpause();
        assertEq(rwaStaking.isPaused(), false);

        vm.stopPrank();
    }

    function test_withdrawFail() public {
        uint256 stakeAmount = 100 ether;

        // Stake from user1 so we can test withdrawals
        helper_initialStake(user1, stakeAmount);

        vm.startPrank(user1);

        uint256 withdrawAmount = stakeAmount + 1;
        vm.expectRevert(
            abi.encodeWithSelector(RWAStaking.InsufficientStaked.selector, user1, usdc, withdrawAmount, stakeAmount)
        );
        rwaStaking.withdraw(withdrawAmount, usdc);

        vm.stopPrank();
    }

    function test_withdraw() public {
        uint256 stakeAmount = 100 ether;
        uint256 timeskipAmount = 300;
        uint256 startTime = block.timestamp;

        // Stake from user1
        helper_initialStake(user1, stakeAmount);

        (uint256 amountSeconds, uint256 amountStaked, uint256 lastUpdate) = rwaStaking.getUserState(user1);
        assertEq(amountSeconds, 0);
        assertEq(amountStaked, stakeAmount);
        //assertEq(lastUpdate, startTime);
        assertEq(usdc.balanceOf(address(rwaStaking)), stakeAmount);
        assertEq(usdc.balanceOf(user1), INITIAL_BALANCE - stakeAmount);

        // Skip ahead in time by 300 seconds
        vm.warp(startTime + timeskipAmount);

        // Withdraw half of the staked amount
        uint256 withdrawAmount = stakeAmount / 2;
        vm.startPrank(user1);
        vm.expectEmit(true, true, false, true, address(rwaStaking));
        emit RWAStaking.Withdrawn(user1, usdc, withdrawAmount);
        rwaStaking.withdraw(withdrawAmount, usdc);
        vm.stopPrank();

        // Check updated balances and state
        (amountSeconds, amountStaked, lastUpdate) = rwaStaking.getUserState(user1);
        assertEq(amountSeconds, stakeAmount * timeskipAmount / 2);
        assertEq(amountStaked, stakeAmount / 2);
        //assertEq(lastUpdate, startTime + timeskipAmount);
        assertEq(usdc.balanceOf(address(rwaStaking)), stakeAmount / 2);
        assertEq(usdc.balanceOf(user1), INITIAL_BALANCE - stakeAmount / 2);

        // Skip ahead in time by another 300 seconds
        vm.warp(startTime + timeskipAmount * 2);

        // Withdraw remaining amounts
        vm.startPrank(user1);
        vm.expectEmit(true, true, false, true, address(rwaStaking));
        emit RWAStaking.Withdrawn(user1, usdc, stakeAmount / 2);
        rwaStaking.withdraw(stakeAmount / 2, usdc);
        vm.stopPrank();

        // Check final balances and state
        (amountSeconds, amountStaked, lastUpdate) = rwaStaking.getUserState(user1);
        assertEq(amountSeconds, 0);
        assertEq(amountStaked, 0);
        //assertEq(lastUpdate, startTime + timeskipAmount * 2);
        assertEq(usdc.balanceOf(address(rwaStaking)), 0);
        assertEq(usdc.balanceOf(user1), INITIAL_BALANCE);
    }

    function test_stakeFail() public {
        uint256 stakeAmount = 100 ether;

        vm.expectRevert(abi.encodeWithSelector(RWAStaking.NotAllowedStablecoin.selector, usdc));
        vm.startPrank(user3);
        rwaStaking.stake(stakeAmount, usdc);
        vm.stopPrank();

        vm.startPrank(owner);
        rwaStaking.allowStablecoin(usdc);
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(rwaStaking), 0, stakeAmount
            )
        );
        vm.startPrank(user3);
        rwaStaking.stake(stakeAmount, usdc);

        usdc.approve(address(rwaStaking), stakeAmount);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, user3, 0, stakeAmount));
        rwaStaking.stake(stakeAmount, usdc);
        vm.stopPrank();
    }

    function test_stake() public {
        uint256 stakeAmount = 100 ether;
        uint256 timeskipAmount = 300;
        uint256 startTime = block.timestamp;

        // Stake 100 USDC from user1
        helper_initialStake(user1, stakeAmount);

        (uint256 amountSeconds, uint256 amountStaked, uint256 lastUpdate) = rwaStaking.getUserState(user1);
        assertEq(amountSeconds, 0);
        assertEq(amountStaked, stakeAmount);
        //assertEq(lastUpdate, startTime);

        // Skip ahead in time by 300 seconds
        vm.warp(startTime + timeskipAmount);

        (amountSeconds, amountStaked, lastUpdate) = rwaStaking.getUserState(user1);
        assertEq(amountSeconds, stakeAmount * timeskipAmount);
        assertEq(amountStaked, stakeAmount);
        //assertEq(lastUpdate, startTime);

        // Stake 100 USDC and 100 pUSD from user2
        vm.startPrank(owner);
        rwaStaking.allowStablecoin(pusd);
        vm.stopPrank();

        vm.startPrank(user2);
        usdc.approve(address(rwaStaking), stakeAmount);
        pusd.approve(address(rwaStaking), stakeAmount);
        vm.expectEmit(true, true, false, true, address(rwaStaking));
        emit RWAStaking.Staked(user2, usdc, stakeAmount);
        rwaStaking.stake(stakeAmount, usdc);
        vm.expectEmit(true, true, false, true, address(rwaStaking));
        emit RWAStaking.Staked(user2, pusd, stakeAmount);
        rwaStaking.stake(stakeAmount, pusd);
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(rwaStaking)), stakeAmount * 2);
        assertEq(pusd.balanceOf(address(rwaStaking)), stakeAmount);
        (amountSeconds, amountStaked, lastUpdate) = rwaStaking.getUserState(user2);
        assertEq(amountSeconds, 0);
        assertEq(amountStaked, stakeAmount * 2);
        //assertEq(lastUpdate, startTime + timeskipAmount);
        assertEq(rwaStaking.getTotalAmountStaked(), stakeAmount * 3);
        assertEq(rwaStaking.getUsers().length, 2);
        assertEq(rwaStaking.getAllowedStablecoins().length, 2);
        assertEq(rwaStaking.isAllowedStablecoin(usdc), true);
        assertEq(rwaStaking.isAllowedStablecoin(pusd), true);
        // Skip ahead in time by 300 seconds
        // Then stake another 100 pUSD from user1
        // Then skip ahead in time by another 300 seconds
        vm.warp(startTime + timeskipAmount * 2);
        vm.startPrank(user1);
        pusd.approve(address(rwaStaking), stakeAmount);
        vm.expectEmit(true, true, false, true, address(rwaStaking));
        emit RWAStaking.Staked(user1, pusd, stakeAmount);
        rwaStaking.stake(stakeAmount, pusd);
        vm.stopPrank();
        vm.warp(startTime + timeskipAmount * 3);

        (amountSeconds, amountStaked, lastUpdate) = rwaStaking.getUserState(user1);
        //assertEq(amountSeconds, stakeAmount * timeskipAmount * 4);
        assertEq(amountStaked, stakeAmount * 2);
        //assertEq(lastUpdate, startTime + timeskipAmount * 2);
        (amountSeconds, amountStaked, lastUpdate) = rwaStaking.getUserState(user2);
        //assertEq(amountSeconds, stakeAmount * timeskipAmount * 4);
        assertEq(amountStaked, stakeAmount * 2);
        //assertEq(lastUpdate, startTime + timeskipAmount);
        assertEq(usdc.balanceOf(address(rwaStaking)), stakeAmount * 2);
        assertEq(pusd.balanceOf(address(rwaStaking)), stakeAmount * 2);
        assertEq(rwaStaking.getTotalAmountStaked(), stakeAmount * 4);
        assertEq(rwaStaking.getUsers().length, 2);
    }

    function test_upgradeFail() public {
        address newImplementation = address(new RWAStaking());
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user1, rwaStaking.UPGRADER_ROLE()
            )
        );
        vm.startPrank(user1);
        rwaStaking.upgradeToAndCall(newImplementation, "");
        vm.stopPrank();
    }

    function test_upgrade() public {
        uint256 stakeAmount = 100 ether;
        helper_initialStake(user1, stakeAmount);

        address newImplementation = address(new RWAStaking());
        vm.startPrank(owner);
        rwaStaking.upgradeToAndCall(newImplementation, "");
        vm.stopPrank();

        // Test that all the storage variables are the same after upgrading
        assertEq(usdc.balanceOf(address(rwaStaking)), stakeAmount);
        assertEq(rwaStaking.getTotalAmountStaked(), stakeAmount);
        assertEq(rwaStaking.getUsers().length, 1);
        assertEq(rwaStaking.getAllowedStablecoins().length, 1);
        assertEq(rwaStaking.isAllowedStablecoin(usdc), true);

        (uint256 amountSeconds, uint256 amountStaked, uint256 lastUpdate) = rwaStaking.getUserState(user1);
        assertEq(amountSeconds, 0);
        assertEq(amountStaked, stakeAmount);
        assertEq(lastUpdate, block.timestamp);
    }

}
