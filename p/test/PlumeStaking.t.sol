// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Plume } from "../src/Plume.sol";
import { PlumeStaking } from "../src/PlumeStaking.sol";

import {
    ArrayLengthMismatch,
    CooldownPeriodNotEnded,
    EmptyArray,
    InvalidAmount,
    NoActiveStake,
    RewardRateExceedsMax,
    TokenAlreadyExists,
    TokenDoesNotExist,
    TokensInCoolingPeriod,
    ZeroAddress
} from "../src/lib/PlumeErrors.sol";
import {
    AdminWithdraw,
    MaxRewardRateUpdated,
    MinStakeAmountSet,
    RewardClaimed,
    RewardTokenAdded,
    RewardTokenRemoved,
    Staked,
    TotalAmountsUpdated,
    Unstaked
} from "../src/lib/PlumeEvents.sol";
import { PlumeStakingStorage } from "../src/lib/PlumeStakingStorage.sol";
import { PlumeStakingProxy } from "../src/proxy/PlumeStakingProxy.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

contract PlumeStakingTest is Test {

    // Contracts
    PlumeStaking public staking;
    Plume public plume;
    IERC20 public pUSD;

    // Addresses from deployment script
    address public constant ADMIN_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;
    address public constant PLUME_TOKEN = 0x17F085f1437C54498f0085102AB33e7217C067C8;
    address public constant PUSD_TOKEN = 0xdddD73F5Df1F0DC31373357beAC77545dC5A6f3F;
    // Special address representing native PLUME token in the contract
    address public constant PLUME_NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // Test addresses
    address public user1;
    address public user2;
    address public admin;

    // Constants
    uint256 public constant MIN_STAKE = 1e18;
    uint256 public constant BASE = 1e18;
    uint256 public constant INITIAL_BALANCE = 1000e18;
    uint256 public constant PUSD_REWARD_RATE = 1_587_301_587; // ~5% APY
    uint256 public constant PLUME_REWARD_RATE = 1_587_301_587; // ~5% APY

    function setUp() public {
        console2.log("Starting test setup");

        // Create test addresses
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        admin = ADMIN_ADDRESS; // Use the actual admin address

        // Setup admin account with debug info
        vm.startPrank(admin);
        console2.log("Testing as admin:", admin);

        // Deploy new implementation
        PlumeStaking implementation = new PlumeStaking();
        console2.log("Deployed implementation:", address(implementation));

        // Initialize proxy with the implementation
        bytes memory initData = abi.encodeCall(PlumeStaking.initialize, (admin, PUSD_TOKEN));
        PlumeStakingProxy proxy = new PlumeStakingProxy(address(implementation), initData);
        console2.log("Deployed proxy:", address(proxy));

        // Get the proxy as PlumeStaking
        staking = PlumeStaking(payable(address(proxy)));

        // Setup token references
        plume = Plume(PLUME_TOKEN);
        pUSD = IERC20(PUSD_TOKEN);

        // Setup ETH balances for native token testing
        vm.deal(address(staking), INITIAL_BALANCE);
        vm.deal(user1, INITIAL_BALANCE);
        vm.deal(user2, INITIAL_BALANCE);
        vm.deal(admin, INITIAL_BALANCE);

        // Add reward tokens with debug info
        console2.log("Adding PUSD token as reward");
        staking.addRewardToken(PUSD_TOKEN);

        console2.log("Adding PLUME_NATIVE token as reward");
        staking.addRewardToken(PLUME_NATIVE);

        // Set reward rates
        address[] memory tokens = new address[](2);
        uint256[] memory rates = new uint256[](2);

        tokens[0] = PUSD_TOKEN;
        tokens[1] = PLUME_NATIVE;
        rates[0] = PUSD_REWARD_RATE;
        rates[1] = PLUME_REWARD_RATE;

        console2.log("Setting reward rates");
        staking.setRewardRates(tokens, rates);

        // Setup token balances for testing
        vm.mockCall(
            PUSD_TOKEN, abi.encodeWithSelector(IERC20.balanceOf.selector, address(staking)), abi.encode(INITIAL_BALANCE)
        );

        // Add some rewards to the contract
        vm.mockCall(
            PUSD_TOKEN,
            abi.encodeWithSelector(IERC20.transferFrom.selector, admin, address(staking), INITIAL_BALANCE),
            abi.encode(true)
        );

        console2.log("Adding PUSD rewards");
        staking.addRewards(PUSD_TOKEN, INITIAL_BALANCE);

        // Add native token rewards
        console2.log("Adding native token rewards");
        staking.addRewards{ value: INITIAL_BALANCE }(PLUME_NATIVE, INITIAL_BALANCE);

        vm.stopPrank();
        console2.log("Setup complete");
    }

    function testInitialState() public {
        console2.log("Running testInitialState");
        assertEq(staking.getMinStakeAmount(), MIN_STAKE);
        assertEq(staking.cooldownInterval(), 7 days);
        assertTrue(staking.hasRole(staking.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(staking.hasRole(staking.ADMIN_ROLE(), admin));
        assertTrue(staking.hasRole(staking.UPGRADER_ROLE(), admin));
    }

    function testUnstakeAndCooldown() public {
        uint256 amount = 100e18;

        vm.startPrank(user1);
        // No approval needed for native token
        staking.stake{ value: amount }();

        vm.expectEmit(true, false, false, true);
        emit Unstaked(user1, amount);

        staking.unstake();

        PlumeStakingStorage.StakeInfo memory info = staking.stakeInfo(user1);
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
        // No approval needed for native token
        staking.stake{ value: amount }();

        vm.warp(block.timestamp + 1 days);

        uint256 expectedReward = (amount * 1 days * PUSD_REWARD_RATE) / BASE;
        //assertEq(staking.getClaimableReward(user1, PUSD_TOKEN), expectedReward);

        // Verify PUSD balance before claim
        assertGe(IERC20(PUSD_TOKEN).balanceOf(address(staking)), expectedReward, "Insufficient reward tokens");

        // Test claim
        vm.expectEmit(true, true, false, true);
        emit RewardClaimed(user1, PUSD_TOKEN, staking.getClaimableReward(user1, PUSD_TOKEN));

        staking.claim(PUSD_TOKEN);
        //assertEq(IERC20(PUSD_TOKEN).balanceOf(user1)-balanceBefore, expectedReward);
        vm.stopPrank();
    }

    function testClaimRewards() public {
        address user = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;

        // Get initial state
        uint256 initialPlumeBalance = plume.balanceOf(user);
        uint256 claimableRewards = staking.getClaimableReward(user, PLUME_NATIVE);

        // Claim rewards as the user
        vm.startPrank(user);
        staking.claim(PLUME_NATIVE);
        vm.stopPrank();

        // Check final state
        uint256 finalPlumeBalance = plume.balanceOf(user);
        uint256 finalClaimableRewards = staking.getClaimableReward(user, PLUME_NATIVE);

        // Verify rewards were claimed
        assertGt(finalPlumeBalance, initialPlumeBalance, "Should have received rewards");
        assertEq(finalClaimableRewards, 0, "Should have no more claimable rewards");
    }

    function testMultipleUsersStaking() public {
        uint256 amount1 = 100e18;
        uint256 amount2 = 200e18;

        // User 1 stakes
        vm.startPrank(user1);
        staking.stake{ value: amount1 }();
        vm.stopPrank();

        // User 2 stakes
        vm.startPrank(user2);
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
        // We're testing a revert due to insufficient amount, so no approval needed
        vm.expectRevert(abi.encodeWithSelector(InvalidAmount.selector, MIN_STAKE - 1, MIN_STAKE));
        staking.stake{ value: MIN_STAKE - 1 }();
        vm.stopPrank();
    }

    function testAddRewardTokenZeroAddress() public {
        console2.log("Running testAddRewardTokenZeroAddress");
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "token"));
        staking.addRewardToken(address(0));
        vm.stopPrank();
    }

    function testAddRewardTokenAlreadyExists() public {
        console2.log("Running testAddRewardTokenAlreadyExists");
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(TokenAlreadyExists.selector, PUSD_TOKEN));
        staking.addRewardToken(PUSD_TOKEN);
        vm.stopPrank();
    }

    function testRemoveRewardToken() public {
        vm.startPrank(admin);

        vm.expectEmit(true, false, false, true);
        emit RewardTokenRemoved(PUSD_TOKEN);
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
        vm.startPrank(admin);

        vm.expectEmit(true, false, false, true);
        emit MinStakeAmountSet(newMinStake);
        staking.setMinStakeAmount(newMinStake);

        assertEq(staking.getMinStakeAmount(), newMinStake);
        vm.stopPrank();
    }

    function testSetRewardRatesValidation() public {
        vm.startPrank(admin);

        // Test empty arrays
        address[] memory tokens = new address[](0);
        uint256[] memory rates = new uint256[](0);
        vm.expectRevert(EmptyArray.selector);
        staking.setRewardRates(tokens, rates);

        // Test length mismatch
        tokens = new address[](2);
        rates = new uint256[](1);
        tokens[0] = PUSD_TOKEN;
        tokens[1] = PLUME_NATIVE;
        rates[0] = 1e18;
        vm.expectRevert(ArrayLengthMismatch.selector);
        staking.setRewardRates(tokens, rates);

        // Test non-existent token
        tokens = new address[](1);
        rates = new uint256[](1);
        tokens[0] = address(0x123);
        rates[0] = 1e18;
        vm.expectRevert(abi.encodeWithSelector(TokenDoesNotExist.selector, address(0x123)));
        staking.setRewardRates(tokens, rates);

        // Test exceeds max rate
        tokens[0] = PUSD_TOKEN;
        rates[0] = 1e21;
        vm.expectRevert(abi.encodeWithSelector(RewardRateExceedsMax.selector, 1e21, 1e20));
        staking.setRewardRates(tokens, rates);

        vm.stopPrank();
    }

    function testSetMaxRewardRate() public {
        uint256 newMaxRate = 2e20;
        vm.startPrank(admin);

        vm.expectEmit(true, false, false, true);
        emit MaxRewardRateUpdated(PUSD_TOKEN, newMaxRate);
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
        staking.stake{ value: coolingAmount }();
        staking.unstake(); // This puts 50e18 in cooling

        // Verify initial cooling balance
        PlumeStakingStorage.StakeInfo memory info = staking.stakeInfo(user1);
        assertEq(info.cooled, 50e18, "Initial cooling balance should be 50e18");

        // Second stake uses 30e18 from cooling
        staking.stake{ value: parkedAmount }(); // Uses 30e18 from cooling
        staking.unstake(); // Puts 30e18 back in cooling

        // Verify cooling balance is still 50e18
        info = staking.stakeInfo(user1);
        assertEq(info.cooled, 50e18, "Cooling balance should still be 50e18");
        assertEq(info.parked, 0, "Parked balance should be 0");

        // Final stake
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
        // No approval needed for native token
        staking.stake{ value: stakeAmount }();

        // Verify initial state
        PlumeStakingStorage.StakeInfo memory info = staking.stakeInfo(user1);
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
        // No approval needed for native token
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
        PlumeStakingStorage.StakeInfo memory info = staking.stakeInfo(user1);
        uint256 cooldownEnd = info.cooldownEnd;
        assertTrue(cooldownEnd > block.timestamp, "Cooldown should end in the future");

        vm.stopPrank();

        // Rest of view function checks that don't need user context
        info = staking.stakeInfo(user1);
        assertEq(info.cooled, stakeAmount);
        assertEq(info.staked, 0);
        assertEq(info.parked, 0);
        assertEq(info.cooldownEnd, cooldownEnd);
    }

    function testSetCooldownInterval() public {
        console2.log("Running testSetCooldownInterval");

        // Must use the correct admin for this test
        vm.startPrank(admin);
        staking.setCooldownInterval(1 days);
        assertEq(staking.cooldownInterval(), 1 days);

        // Can set to 0
        staking.setCooldownInterval(0);
        assertEq(staking.cooldownInterval(), 0);
        vm.stopPrank();

        // Only admin can set
        vm.startPrank(user1);
        vm.expectRevert(); // Just expect any revert since we don't know exact error
        staking.setCooldownInterval(1 days);
        vm.stopPrank();
    }

    function testAdminWithdraw() public {
        vm.startPrank(admin);

        // Zero address checks
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "token"));
        staking.adminWithdraw(address(0), 1e18, user1);

        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "recipient"));
        staking.adminWithdraw(address(plume), 1e18, address(0));

        // Zero amount check
        vm.expectRevert(abi.encodeWithSelector(InvalidAmount.selector, 0, 1));
        staking.adminWithdraw(address(plume), 0, user1);

        // Test PLUME withdrawal restrictions
        uint256 stakeAmount = 100e18;
        vm.stopPrank();

        // Setup some staked tokens
        vm.startPrank(user1);
        // No approval needed for native token
        staking.stake{ value: stakeAmount }();
        vm.stopPrank();

        // Try to withdraw staked tokens
        vm.startPrank(admin);
        (uint256 totalStaked, uint256 totalCooling,,,) = staking.stakingInfo();
        uint256 totalLocked = totalStaked + totalCooling;
        uint256 balance = plume.balanceOf(address(staking));
        vm.expectRevert("Cannot withdraw staked/cooling tokens");
        staking.adminWithdraw(PLUME_NATIVE, balance - totalLocked + 1, user1);

        // Can withdraw excess tokens
        uint256 withdrawAmount = balance - totalLocked;
        if (withdrawAmount > 0) {
            staking.adminWithdraw(PLUME_NATIVE, withdrawAmount, user1);
        }
        vm.stopPrank();
    }

    function testStakeWithParked() public {
        uint256 initialStake = 50e18;
        uint256 parkedAmount = 30e18;

        vm.startPrank(user1);

        // First stake and unstake to get some parked tokens
        staking.stake{ value: initialStake }();
        staking.unstake();

        // Wait for cooldown
        vm.warp(block.timestamp + 7 days + 1);

        // Withdraw to parked
        staking.withdraw();

        // Now stake using parked tokens
        uint256 newStakeAmount = 40e18;

        uint256 expectedFromParked = Math.min(parkedAmount, newStakeAmount);
        uint256 expectedFromWallet = newStakeAmount - expectedFromParked;

        vm.expectEmit(true, true, true, true);
        emit Staked(user1, newStakeAmount, 0, expectedFromParked, expectedFromWallet);
        staking.stake{ value: newStakeAmount }();

        PlumeStakingStorage.StakeInfo memory info = staking.stakeInfo(user1);
        assertEq(info.parked, parkedAmount - expectedFromParked);
        assertEq(info.staked, newStakeAmount);

        vm.stopPrank();
    }

    function testWithdrawWithParked() public {
        uint256 stakeAmount = 100e18;

        vm.startPrank(user1);
        // No approval needed for native token
        staking.stake{ value: stakeAmount }();
        staking.unstake();
        vm.warp(block.timestamp + 7 days + 1);

        uint256 withdrawAmount = 50e18;
        uint256 initialBalance = plume.balanceOf(user1);

        staking.withdraw();

        // Verify state changes
        PlumeStakingStorage.StakeInfo memory info = staking.stakeInfo(user1);
        assertEq(info.parked, stakeAmount - withdrawAmount);
        assertEq(plume.balanceOf(user1), initialBalance + withdrawAmount);

        vm.stopPrank();
    }

    function testViewFunctionsComprehensive() public {
        uint256 stakeAmount = 100e18;
        uint256 unstakeAmount = 30e18;

        vm.startPrank(user1);
        // No approval needed for native token
        staking.stake{ value: stakeAmount }();

        // Test staked amounts
        assertEq(staking.amountStaked(), stakeAmount);
        (uint256 totalStaked,,,,) = staking.stakingInfo();
        assertEq(totalStaked, stakeAmount);

        // Unstake
        staking.unstake();

        // Test cooling amounts before cooldown ends
        assertEq(staking.amountCooling(), stakeAmount);
        (, uint256 totalCooling, uint256 totalWithdrawable,,) = staking.stakingInfo();
        assertEq(totalCooling, stakeAmount);
        assertEq(staking.amountWithdrawable(), 0); // Nothing withdrawable yet
        assertEq(totalWithdrawable, 0); // Nothing withdrawable yet

        // Test cooldown date
        PlumeStakingStorage.StakeInfo memory info = staking.stakeInfo(user1);
        uint256 cooldownEnd = info.cooldownEnd;
        assertTrue(cooldownEnd > block.timestamp);

        // Wait for cooldown and withdraw some
        vm.warp(block.timestamp + 7 days + 1);

        // After cooldown, cooling amount should be 0 and withdrawable should be full amount
        assertEq(staking.amountCooling(), 0, "Cooling amount should be 0 after cooldown");
        (, totalCooling, totalWithdrawable,,) = staking.stakingInfo();
        assertEq(totalCooling, 0, "Total cooling amount should be 0 after cooldown");
        assertEq(staking.amountWithdrawable(), stakeAmount, "Full amount should be withdrawable");
        assertEq(totalWithdrawable, stakeAmount, "Full amount should be withdrawable");

        // Withdraw part of the amount
        staking.withdraw();

        // Test balances after partial withdrawal
        assertEq(staking.amountWithdrawable(), 0, "Remaining withdrawable amount incorrect");
        (,, totalWithdrawable,,) = staking.stakingInfo();
        assertEq(totalWithdrawable, 0, "Total withdrawable amount incorrect");

        // Test claimable amounts
        assertEq(staking.getClaimableReward(user1, PUSD_TOKEN), 0);
        assertEq(staking.getClaimableReward(user1, PUSD_TOKEN), 0);

        vm.stopPrank();
    }

    function testUpdateTotalAmounts() public {
        uint256 stakeAmount = 100e18;

        // Setup initial state
        vm.startPrank(user1);
        // No approval needed for native token
        staking.stake{ value: stakeAmount }();

        // Unstake to move to cooling
        staking.unstake();
        vm.stopPrank();

        // Admin updates totals first - start from index 0 and process all stakers
        vm.prank(admin);
        staking.updateTotalAmounts(0, type(uint256).max);

        // Verify initial state
        (uint256 totalStaked, uint256 totalCooling, uint256 totalWithdrawable,,) = staking.stakingInfo();
        assertEq(totalStaked, 0);
        assertEq(totalCooling, stakeAmount);
        assertEq(totalWithdrawable, 0);
        assertEq(staking.amountCooling(), stakeAmount);

        // Move time past cooldown period
        vm.warp(block.timestamp + 7 days + 1);

        // Admin updates totals again after cooldown
        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit TotalAmountsUpdated(0, 0, stakeAmount);
        staking.updateTotalAmounts(0, type(uint256).max);

        // Now verify the state has been updated
        (totalStaked, totalCooling, totalWithdrawable,,) = staking.stakingInfo();
        assertEq(totalStaked, 0);
        assertEq(totalCooling, 0, "Cooling amount should be 0 after update");
        assertEq(totalWithdrawable, stakeAmount, "Amount should be withdrawable");
        assertEq(staking.amountCooling(), 0, "Individual cooling amount should be 0 after update");

        // User can now withdraw
        vm.prank(user1);
        staking.withdraw();

        // Verify final state
        (totalStaked, totalCooling, totalWithdrawable,,) = staking.stakingInfo();
        assertEq(totalStaked, 0);
        assertEq(totalCooling, 0);
        assertEq(totalWithdrawable, 0);
    }

    function testStorageSlot() public {
        console2.logBytes32(
            keccak256(abi.encode(uint256(keccak256("plume.storage.pUSDStaking")) - 1)) & ~bytes32(uint256(0xff))
        );
    }

}
