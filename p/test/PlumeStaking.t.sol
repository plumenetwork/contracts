// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Plume } from "../src/Plume.sol";
import { PlumeStaking } from "../src/PlumeStaking.sol";

import { PlumeStakingProxy } from "../src/proxy/PlumeStakingProxy.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Test } from "forge-std/Test.sol"; // Add Math import
import { console2 } from "forge-std/console2.sol";

contract PlumeStakingTest is Test {

    // Contracts
    PlumeStaking public staking;
    Plume public plume;
    IERC20 public pUSD;

    // Addresses from deployment script
    address public constant ADMIN = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;
    address public constant PLUME_TOKEN = 0x17F085f1437C54498f0085102AB33e7217C067C8;
    address public constant PUSD_TOKEN = 0xdddD73F5Df1F0DC31373357beAC77545dC5A6f3F;
    address public constant PLUMESTAKING_PROXY = 0x632c5513fb6715789efdb0d61b960cA1706d9E45;

    // Test addresses
    address public user1 = makeAddr("bob");
    address public user2 = makeAddr("alice");
    address public admin = makeAddr("admin");

    // Constants
    uint256 public constant MIN_STAKE = 1e18;
    uint256 public constant BASE = 1e18;
    uint256 public constant INITIAL_BALANCE = 1000e18;
    uint256 public constant PUSD_REWARD_RATE = 1_587_301_587; // ~5% APY
    uint256 public constant PLUME_REWARD_RATE = 0; // ~5% APY

    function setUp() public {
        // Fork mainnet
        string memory PLUME_RPC = vm.envOr("PLUME_RPC_URL", string(""));
        uint256 FORK_BLOCK = 373_551;
        vm.createSelectFork(vm.rpcUrl(PLUME_RPC), FORK_BLOCK);

        vm.startPrank(ADMIN);

        // Deploy implementation and proxy
        PlumeStaking implementation = new PlumeStaking();

        bytes memory initData = abi.encodeCall(PlumeStaking.initialize, (ADMIN, PUSD_TOKEN));

        ERC1967Proxy proxy = new PlumeStakingProxy(address(implementation), initData);

        // Setup contract interfaces
        staking = PlumeStaking(payable(address(proxy)));
        plume = Plume(PLUME_TOKEN);
        pUSD = IERC20(PUSD_TOKEN);

        // Setup reward tokens
        staking.addRewardToken(PUSD_TOKEN);
        staking.addRewardToken(PLUME_TOKEN);

        address[] memory tokens = new address[](2);
        uint256[] memory rates = new uint256[](2);

        tokens[0] = PUSD_TOKEN;
        tokens[1] = PLUME_TOKEN;
        rates[0] = PUSD_REWARD_RATE;
        rates[1] = PLUME_REWARD_RATE;

        staking.setRewardRates(tokens, rates);

        deal(PLUME_TOKEN, user1, INITIAL_BALANCE);
        deal(PLUME_TOKEN, user2, INITIAL_BALANCE);
        deal(PLUME_TOKEN, address(staking), INITIAL_BALANCE);

        vm.stopPrank();
    }

    function testInitialState() public {
        //assertEq(staking.minStakeAmount(), MIN_STAKE);
        // assertEq(staking.cooldownInterval(), 7 days);
        assertTrue(staking.hasRole(staking.DEFAULT_ADMIN_ROLE(), ADMIN));
        assertTrue(staking.hasRole(staking.ADMIN_ROLE(), ADMIN));
        assertTrue(staking.hasRole(staking.UPGRADER_ROLE(), ADMIN));
    }

    function testUnstakeAndCooldown() public {
        uint256 amount = 100e18;

        vm.startPrank(user1);
        plume.approve(address(staking), amount);
        staking.stake{ value: amount }();

        vm.expectEmit(true, false, false, true);
        emit PlumeStaking.Unstaked(user1, amount);

        staking.unstake();

        PlumeStaking.StakeInfo memory info = staking.stakeInfo(user1);
        assertEq(info.staked, 0);
        assertEq(info.cooled, amount);
        assertEq(info.cooldownEnd, block.timestamp + 7 days);
        vm.stopPrank();
    }

    function testRewardAccrual() public {
        uint256 amount = 100e18;
        uint256 rewardPoolAmount = 1000e18;
        uint256 balanceBefore = IERC20(PUSD_TOKEN).balanceOf(user1);

        deal(PUSD_TOKEN, address(staking), rewardPoolAmount);

        vm.startPrank(user1);
        plume.approve(address(staking), amount);
        staking.stake{ value: amount }();

        vm.warp(block.timestamp + 1 days);

        uint256 expectedReward = (amount * 1 days * PUSD_REWARD_RATE) / BASE;
        //assertEq(staking.getClaimableReward(user1, PUSD_TOKEN), expectedReward);

        // Verify PUSD balance before claim
        assertGe(IERC20(PUSD_TOKEN).balanceOf(address(staking)), expectedReward, "Insufficient reward tokens");

        // Test claim
        vm.expectEmit(true, true, false, true);
        emit PlumeStaking.RewardClaimed(user1, PUSD_TOKEN, staking.getClaimableReward(user1, PUSD_TOKEN));

        staking.claim(PUSD_TOKEN);
        //assertEq(IERC20(PUSD_TOKEN).balanceOf(user1)-balanceBefore, expectedReward);
        vm.stopPrank();
    }

    function testClaimRewards() public {
        address user = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;

        // Get initial state
        uint256 initialPlumeBalance = plume.balanceOf(user);
        uint256 claimableRewards = staking.getClaimableReward(user, PLUME_TOKEN);

        // Claim rewards as the user
        vm.startPrank(user);
        staking.claim(PLUME_TOKEN);
        vm.stopPrank();

        // Check final state
        uint256 finalPlumeBalance = plume.balanceOf(user);
        uint256 finalClaimableRewards = staking.getClaimableReward(user, PLUME_TOKEN);

        // Verify rewards were claimed
        assertGt(finalPlumeBalance, initialPlumeBalance, "Should have received rewards");
        assertEq(finalClaimableRewards, 0, "Should have no more claimable rewards");
    }

    function testMultipleUsersStaking() public {
        uint256 amount1 = 100e18;
        uint256 amount2 = 200e18;

        // User 1 stakes
        vm.startPrank(user1);
        plume.approve(address(staking), amount1);
        staking.stake{ value: amount1 }();
        vm.stopPrank();

        // User 2 stakes
        vm.startPrank(user2);
        plume.approve(address(staking), amount2);
        staking.stake{ value: amount2 }();
        vm.stopPrank();

        // Move forward in time
        vm.warp(block.timestamp + 1 days);

        // Check rewards
        uint256 expectedReward1 = (amount1 * 1 days * PUSD_REWARD_RATE) / BASE;
        uint256 expectedReward2 = (amount2 * 1 days * PUSD_REWARD_RATE) / BASE;

        assertEq(staking.getClaimableReward(user1, PUSD_TOKEN), expectedReward1);
        assertEq(staking.getClaimableReward(user2, PUSD_TOKEN), expectedReward2);
    }

    function testRevertInvalidAmount() public {
        vm.startPrank(user1);
        plume.approve(address(staking), MIN_STAKE - 1);

        vm.expectRevert(abi.encodeWithSelector(PlumeStaking.InvalidAmount.selector, MIN_STAKE - 1, MIN_STAKE));
        staking.stake{ value: MIN_STAKE - 1 }();
        vm.stopPrank();
    }

    function testAddRewardTokenZeroAddress() public {
        vm.startPrank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(PlumeStaking.ZeroAddress.selector, "token"));
        staking.addRewardToken(address(0));
        vm.stopPrank();
    }

    function testAddRewardTokenAlreadyExists() public {
        vm.startPrank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(PlumeStaking.TokenAlreadyExists.selector, PUSD_TOKEN));
        staking.addRewardToken(PUSD_TOKEN);
        vm.stopPrank();
    }

    function testRemoveRewardToken() public {
        vm.startPrank(ADMIN);

        vm.expectEmit(true, false, false, true);
        emit PlumeStaking.RewardTokenRemoved(PUSD_TOKEN);
        staking.removeRewardToken(PUSD_TOKEN);

        // Verify token was removed
        (address[] memory tokens,) = staking.getRewardTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            assertFalse(tokens[i] == PUSD_TOKEN);
        }
        vm.stopPrank();
    }

    function testSetMinStakeAmount() public {
        uint256 newMinStake = 5e18;
        vm.startPrank(ADMIN);

        vm.expectEmit(true, false, false, true);
        emit PlumeStaking.MinStakeAmountSet(newMinStake);
        staking.setMinStakeAmount(newMinStake);

        assertEq(staking.getMinStakeAmount(), newMinStake);
        vm.stopPrank();
    }

    function testSetRewardRatesValidation() public {
        vm.startPrank(ADMIN);

        // Test empty arrays
        address[] memory tokens = new address[](0);
        uint256[] memory rates = new uint256[](0);
        vm.expectRevert(PlumeStaking.EmptyArray.selector);
        staking.setRewardRates(tokens, rates);

        // Test length mismatch
        tokens = new address[](2);
        rates = new uint256[](1);
        tokens[0] = PUSD_TOKEN;
        tokens[1] = PLUME_TOKEN;
        rates[0] = 1e18;
        vm.expectRevert(PlumeStaking.ArrayLengthMismatch.selector);
        staking.setRewardRates(tokens, rates);

        // Test non-existent token
        tokens = new address[](1);
        rates = new uint256[](1);
        tokens[0] = address(0x123);
        rates[0] = 1e18;
        vm.expectRevert(abi.encodeWithSelector(PlumeStaking.TokenDoesNotExist.selector, address(0x123)));
        staking.setRewardRates(tokens, rates);

        // Test exceeds max rate
        tokens[0] = PUSD_TOKEN;
        rates[0] = 1e21;
        vm.expectRevert(abi.encodeWithSelector(PlumeStaking.RewardRateExceedsMax.selector, 1e21, 1e20));
        staking.setRewardRates(tokens, rates);

        vm.stopPrank();
    }

    function testSetMaxRewardRate() public {
        uint256 newMaxRate = 2e20;
        vm.startPrank(ADMIN);

        vm.expectEmit(true, false, false, true);
        emit PlumeStaking.MaxRewardRateUpdated(PUSD_TOKEN, newMaxRate);
        staking.setMaxRewardRate(PUSD_TOKEN, newMaxRate);

        assertEq(staking.getMaxRewardRate(PUSD_TOKEN), newMaxRate);
        vm.stopPrank();
    }

    /*

    function testAdminWithdraw() public {
        uint256 amount = 100e18;
        deal(PUSD_TOKEN, address(staking), amount);
        
        // Store initial balance
        uint256 initialBalance = IERC20(PUSD_TOKEN).balanceOf(ADMIN);
        
        vm.startPrank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit PlumeStaking.AdminWithdraw(PUSD_TOKEN, amount, ADMIN);
        staking.adminWithdraw(PUSD_TOKEN, amount, ADMIN);
        
        // Check that admin received at least the withdrawn amount
        uint256 finalBalance = IERC20(PUSD_TOKEN).balanceOf(ADMIN);
        assertGe(finalBalance, initialBalance + amount);
        vm.stopPrank();
    }
    */

    // Stake & unstake first amount (50e18 goes to cooling)
    // Stake second amount (uses 30e18 from cooling, leaving 20e18)
    // Unstake second amount (puts 30e18 back in cooling, total back to 50e18)
    // Final stake uses 50e18 from cooling and 50e18 from wallet
    function testStakeFromMultipleSources() public {
        uint256 coolingAmount = 50e18;
        uint256 parkedAmount = 30e18;
        uint256 walletAmount = 20e18;
        uint256 totalStakeAmount = 100e18;

        vm.startPrank(user1);

        // Setup initial cooling balance (50e18)
        plume.approve(address(staking), coolingAmount);
        staking.stake{ value: coolingAmount }();
        staking.unstake(); // This puts 50e18 in cooling

        // Verify initial cooling balance
        PlumeStaking.StakeInfo memory info = staking.stakeInfo(user1);
        assertEq(info.cooled, 50e18, "Initial cooling balance should be 50e18");

        // Second stake uses 30e18 from cooling
        plume.approve(address(staking), parkedAmount);
        staking.stake{ value: parkedAmount }(); // Uses 30e18 from cooling
        staking.unstake(); // Puts 30e18 back in cooling

        // Verify cooling balance is still 50e18
        info = staking.stakeInfo(user1);
        assertEq(info.cooled, 50e18, "Cooling balance should still be 50e18");
        assertEq(info.parked, 0, "Parked balance should be 0");

        // Approve remaining amount needed from wallet
        plume.approve(address(staking), totalStakeAmount - info.cooled);

        vm.expectEmit(true, true, true, true);
        emit PlumeStaking.Staked(user1, totalStakeAmount, 50e18, 0, 50e18);
        staking.stake{ value: totalStakeAmount }();

        // Verify final state
        info = staking.stakeInfo(user1);
        assertEq(info.staked, totalStakeAmount, "Should have total amount staked");
        assertEq(info.cooled, 0, "Cooling should be empty");
        assertEq(info.parked, 0, "Parked should be empty");
        vm.stopPrank();
    }

    function testWithdrawAndReverts() public {
        uint256 stakeAmount = 100e18;

        vm.startPrank(user1);
        plume.approve(address(staking), stakeAmount);
        staking.stake{ value: stakeAmount }();

        // Verify initial state
        PlumeStaking.StakeInfo memory info = staking.stakeInfo(user1);
        assertEq(info.staked, stakeAmount);
        assertEq(info.cooled, 0);

        // Try to withdraw more than staked (should fail)
        uint256 withdrawAmount = stakeAmount + 1;

        staking.withdraw();

        // Now unstake
        staking.unstake();

        // Wait for cooldown
        vm.warp(block.timestamp + 7 days + 1);

        staking.withdraw();

        vm.stopPrank();
    }

    function testViewFunctions() public {
        uint256 stakeAmount = 100e18;

        vm.startPrank(user1);
        plume.approve(address(staking), stakeAmount);
        staking.stake{ value: stakeAmount }();
        staking.unstake(); // This initiates cooldown

        // Check reward token info
        (address[] memory tokens, uint256[] memory rates) = staking.getRewardTokens();
        assertTrue(tokens.length == rates.length);

        // Check that the rate matches what's returned in getRewardTokens
        (uint256 rate0,) = staking.tokenRewardInfo(tokens[0]);
        (uint256 rate1,) = staking.tokenRewardInfo(tokens[1]);
        assertEq(rate0, rates[0]);
        assertEq(rate1, rates[1]);

        // Check cooldown - do this before stopPrank
        uint256 cooldownEnd = staking.cooldownEndDateOf(user1);
        assertTrue(cooldownEnd > block.timestamp, "Cooldown should end in the future");

        vm.stopPrank();

        // Rest of view function checks that don't need user context
        PlumeStaking.StakeInfo memory info = staking.stakeInfo(user1);
        assertEq(info.cooled, stakeAmount);
        assertEq(info.staked, 0);
        assertEq(info.parked, 0);
        assertEq(info.cooldownEnd, cooldownEnd);
    }

    function testSetCooldownInterval() public {
        // Only admin can set
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(user1);
        staking.setCooldownInterval(1 days);

        // Admin can set
        vm.prank(admin);
        staking.setCooldownInterval(1 days);
        assertEq(staking.cooldownInterval(), 1 days);

        // Can set to 0
        vm.prank(admin);
        staking.setCooldownInterval(0);
        assertEq(staking.cooldownInterval(), 0);
    }

    function testAdminWithdraw() public {
        vm.startPrank(admin);

        // Zero address checks
        vm.expectRevert(abi.encodeWithSelector(PlumeStaking.ZeroAddress.selector, "token"));
        staking.adminWithdraw(address(0), 1e18, user1);

        vm.expectRevert(abi.encodeWithSelector(PlumeStaking.ZeroAddress.selector, "recipient"));
        staking.adminWithdraw(address(plume), 1e18, address(0));

        // Zero amount check
        vm.expectRevert(abi.encodeWithSelector(PlumeStaking.InvalidAmount.selector, 0, 1));
        staking.adminWithdraw(address(plume), 0, user1);

        // Test PLUME withdrawal restrictions
        uint256 stakeAmount = 100e18;
        vm.stopPrank();

        // Setup some staked tokens
        vm.startPrank(user1);
        plume.approve(address(staking), stakeAmount);
        staking.stake{ value: stakeAmount }();
        vm.stopPrank();

        // Try to withdraw staked tokens
        vm.startPrank(admin);
        uint256 totalLocked = staking.totalAmountStaked() + staking.totalAmountCooling();
        uint256 balance = plume.balanceOf(address(staking));
        vm.expectRevert("Cannot withdraw staked/cooling tokens");
        staking.adminWithdraw(address(plume), balance - totalLocked + 1, user1);

        // Can withdraw excess tokens
        uint256 withdrawAmount = balance - totalLocked;
        if (withdrawAmount > 0) {
            staking.adminWithdraw(address(plume), withdrawAmount, user1);
        }
        vm.stopPrank();
    }

    function testStakeWithParked() public {
        uint256 initialStake = 50e18;
        uint256 parkedAmount = 30e18;

        vm.startPrank(user1);

        // First stake and unstake to get some parked tokens
        plume.approve(address(staking), initialStake);
        staking.stake{ value: initialStake }();
        staking.unstake();

        // Wait for cooldown
        vm.warp(block.timestamp + 7 days + 1);

        // Withdraw to parked
        staking.withdraw();

        // Now stake using parked tokens
        uint256 newStakeAmount = 40e18;
        plume.approve(address(staking), newStakeAmount);

        uint256 expectedFromParked = Math.min(parkedAmount, newStakeAmount);
        uint256 expectedFromWallet = newStakeAmount - expectedFromParked;

        vm.expectEmit(true, true, true, true);
        emit PlumeStaking.Staked(user1, newStakeAmount, 0, expectedFromParked, expectedFromWallet);
        staking.stake{ value: newStakeAmount }();

        PlumeStaking.StakeInfo memory info = staking.stakeInfo(user1);
        assertEq(info.parked, parkedAmount - expectedFromParked);
        assertEq(info.staked, newStakeAmount);

        vm.stopPrank();
    }

    function testWithdrawWithParked() public {
        uint256 stakeAmount = 100e18;

        vm.startPrank(user1);
        plume.approve(address(staking), stakeAmount);

        // Test zero amount
        vm.expectRevert(abi.encodeWithSelector(PlumeStaking.InvalidAmount.selector, 0, 1));
        staking.withdraw();

        // Setup some parked balance
        staking.stake{ value: stakeAmount }();
        staking.unstake();
        vm.warp(block.timestamp + 7 days + 1);

        uint256 withdrawAmount = 50e18;
        uint256 initialBalance = plume.balanceOf(user1);

        staking.withdraw();

        // Verify state changes
        PlumeStaking.StakeInfo memory info = staking.stakeInfo(user1);
        assertEq(info.parked, stakeAmount - withdrawAmount);
        assertEq(plume.balanceOf(user1), initialBalance + withdrawAmount);

        vm.stopPrank();
    }

    function testViewFunctionsComprehensive() public {
        uint256 stakeAmount = 100e18;
        uint256 unstakeAmount = 30e18;

        vm.startPrank(user1);
        plume.approve(address(staking), stakeAmount);
        staking.stake{ value: stakeAmount }();

        // Test staked amounts
        assertEq(staking.amountStaked(), stakeAmount);
        assertEq(staking.totalAmountStaked(), stakeAmount);

        // Unstake
        staking.unstake();

        // Test cooling amounts before cooldown ends
        assertEq(staking.amountCooling(), stakeAmount);
        assertEq(staking.totalAmountCooling(), stakeAmount);
        assertEq(staking.amountWithdrawable(), 0); // Nothing withdrawable yet
        assertEq(staking.totalAmountWithdrawable(), 0); // Nothing withdrawable yet

        // Test cooldown date
        uint256 cooldownEnd = staking.cooldownEndDate();
        assertTrue(cooldownEnd > block.timestamp);

        // Wait for cooldown and withdraw some
        vm.warp(block.timestamp + 7 days + 1);

        // After cooldown, cooling amount should be 0 and withdrawable should be full amount
        assertEq(staking.amountCooling(), 0, "Cooling amount should be 0 after cooldown");
        assertEq(staking.totalAmountCooling(), 0, "Total cooling amount should be 0 after cooldown");
        assertEq(staking.amountWithdrawable(), stakeAmount, "Full amount should be withdrawable");
        assertEq(staking.totalAmountWithdrawable(), stakeAmount, "Full amount should be withdrawable");

        // Withdraw part of the amount
        staking.withdraw();

        // Test balances after partial withdrawal
        assertEq(staking.withdrawableBalance(user1), 0, "Remaining withdrawable balance incorrect");
        assertEq(staking.amountWithdrawable(), 0, "Remaining withdrawable amount incorrect");
        assertEq(staking.totalAmountWithdrawable(), 0, "Total withdrawable amount incorrect");

        // Test claimable amounts
        assertEq(staking.claimableBalance(user1, PUSD_TOKEN), 0);
        assertEq(staking.getClaimableReward(user1, PUSD_TOKEN), 0);
        assertEq(staking.totalAmountClaimable(PUSD_TOKEN), 0);

        vm.stopPrank();
    }

    function testUpdateTotalAmounts() public {
        uint256 stakeAmount = 100e18;

        // Setup initial state
        vm.startPrank(user1);
        plume.approve(address(staking), stakeAmount);
        staking.stake{ value: stakeAmount }();

        // Unstake to move to cooling
        staking.unstake();
        vm.stopPrank();

        // Admin updates totals first
        vm.prank(admin);
        staking.updateTotalAmounts();

        // Verify initial state
        assertEq(staking.totalAmountStaked(), 0);
        assertEq(staking.totalAmountCooling(), stakeAmount);
        assertEq(staking.totalAmountWithdrawable(), 0);
        assertEq(staking.amountCooling(), stakeAmount);

        // Move time past cooldown period
        vm.warp(block.timestamp + 7 days + 1);

        // Admin updates totals again after cooldown
        vm.prank(admin);
        vm.expectEmit(false, false, false, true);
        emit PlumeStaking.TotalAmountsUpdated(0, 0, stakeAmount);
        staking.updateTotalAmounts();

        // Now verify the state has been updated
        assertEq(staking.totalAmountStaked(), 0);
        assertEq(staking.totalAmountCooling(), 0, "Cooling amount should be 0 after update");
        assertEq(staking.totalAmountWithdrawable(), stakeAmount, "Amount should be withdrawable");
        assertEq(staking.amountCooling(), 0, "Individual cooling amount should be 0 after update");

        // User can now withdraw
        vm.prank(user1);
        staking.withdraw();

        // Verify final state
        assertEq(staking.totalAmountStaked(), 0);
        assertEq(staking.totalAmountCooling(), 0);
        assertEq(staking.totalAmountWithdrawable(), 0);
    }

    function testStorageSlot() public {
        console2.logBytes32(
            keccak256(abi.encode(uint256(keccak256("plume.storage.pUSDStaking")) - 1)) & ~bytes32(uint256(0xff))
        );
    }

}
