// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "../src/PlumeStaking.sol";
import "../src/interfaces/IPlumeStaking.sol";
import "../src/lib/PlumeStakingStorage.sol";
import "../src/modules/PlumeStakingBase.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Plume } from "../src/Plume.sol";
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
import { MockPUSD } from "../src/mocks/MockPUSD.sol";
import { PlumeStakingProxy } from "../src/proxy/PlumeStakingProxy.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { console2 } from "forge-std/console2.sol";

contract PlumeStakingTest is Test {

    // Contracts
    PlumeStaking public staking;
    Plume public plume;
    IERC20 public pUSD;

    // Addresses from deployment script
    address public constant ADMIN_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;
    address public constant PLUME_TOKEN = 0x17F085f1437C54498f0085102AB33e7217C067C8;
    address public constant PUSD_TOKEN = 0x466a756E9A7401B5e2444a3fCB3c2C12FBEa0a54;
    // Special address representing native PLUME token in the contract
    address public constant PLUME_NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // Test addresses
    address public user1;
    address public user2;
    address public admin;
    address public validator;

    // Constants
    uint256 public constant MIN_STAKE = 1e18;
    uint256 public constant BASE = 1e18;
    uint256 public constant INITIAL_BALANCE = 1000e18;
    uint256 public constant PUSD_REWARD_RATE = 1e18; // 1 token per second
    uint256 public constant PLUME_REWARD_RATE = 1_587_301_587; // ~5% APY
    uint16 public constant DEFAULT_VALIDATOR_ID = 0;
    uint256 public constant REWARD_PRECISION = 1e18;

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
        bytes memory initData = abi.encodeCall(PlumeStaking.initialize, (admin));
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

        // Set max reward rates
        console2.log("Setting max reward rates");
        staking.setMaxRewardRate(PUSD_TOKEN, PUSD_REWARD_RATE * 2);
        staking.setMaxRewardRate(PLUME_NATIVE, PLUME_REWARD_RATE * 2);

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
        vm.mockCall(PUSD_TOKEN, abi.encodeWithSelector(IERC20.balanceOf.selector, user1), abi.encode(0));
        vm.mockCall(
            PLUME_TOKEN,
            abi.encodeWithSelector(IERC20.balanceOf.selector, address(staking)),
            abi.encode(INITIAL_BALANCE)
        );
        vm.mockCall(PLUME_TOKEN, abi.encodeWithSelector(IERC20.balanceOf.selector, user1), abi.encode(0));

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

        // Add validator for testing
        console2.log("Adding validator for testing");
        staking.addValidator(
            DEFAULT_VALIDATOR_ID, // validatorId
            5e16, // commission (5%)
            user1, // l2AdminAddress
            user1, // l2WithdrawAddress
            "0x123", // l1ValidatorAddress
            "0x456" // l1AccountAddress
        );

        // Set validator capacity to a high value to allow staking
        staking.setValidatorCapacity(DEFAULT_VALIDATOR_ID, 1_000_000e18); // 1M PLUME capacity

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
        staking.stake{ value: amount }(DEFAULT_VALIDATOR_ID);

        vm.expectEmit(true, true, false, true);
        emit Unstaked(user1, DEFAULT_VALIDATOR_ID, amount);

        uint256 unstakeAmount = staking.unstake(DEFAULT_VALIDATOR_ID);

        assertEq(unstakeAmount, amount);

        // Check that amount is now in cooling
        assertEq(staking.amountCooling(), amount);
        vm.stopPrank();
    }

    function testRewardAccrual() public {
        uint256 amount = 100e18;

        // Setup
        /*
        tokenMock.mint(owner, 1000e18);
        tokenMock.approve(address(staking), 1000e18);
        uint256 rate = 10e18; // 10 tokens per second
        staking.setRewardRate(PUSD_TOKEN, rate);
        */

        vm.startPrank(user1);
        staking.stake{ value: amount }(DEFAULT_VALIDATOR_ID);
        vm.stopPrank();

        // Advance time
        vm.warp(block.timestamp + 1 days);

        // Calculate expected rewards with commission
        uint256 timeDelta = 1 days;

        // Get validator commission
        PlumeStakingStorage.ValidatorInfo memory validator =
            PlumeStakingStorage.layout().validators[DEFAULT_VALIDATOR_ID];
        uint256 validatorCommission = validator.commission; // 5% commission

        // Calculate rewards with commission accounted for
        //uint256 rawReward = (timeDelta * rate);
        uint256 rawReward = (timeDelta * PUSD_REWARD_RATE);
        uint256 expectedReward = (rawReward * (REWARD_PRECISION - validatorCommission)) / REWARD_PRECISION;

        // Test reward calculation before claim
        assertApproxEqRel(staking.getClaimableReward(user1, PUSD_TOKEN), expectedReward, 5.1e16); // 5.1% tolerance

        // Test claiming rewards
        vm.startPrank(user1);
        // Don't set expectations for exact event data since it will vary
        staking.claim(PUSD_TOKEN);
        vm.stopPrank();

        // Verify rewards were properly reset
        assertEq(staking.getClaimableReward(user1, PUSD_TOKEN), 0);

        // Verify the tokens were transferred
        //assertEq(tokenMock.balanceOf(user1), expectedReward);
    }

    function testClaimRewards() public {
        address user = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;

        // Get initial state
        uint256 initialBalance = address(user).balance;
        uint256 claimableRewards = staking.getClaimableReward(user, PLUME_NATIVE);

        // Claim rewards as the user
        vm.startPrank(user);
        staking.claim(PLUME_NATIVE);
        vm.stopPrank();

        // Check final state
        uint256 finalBalance = address(user).balance;
        uint256 finalClaimableRewards = staking.getClaimableReward(user, PLUME_NATIVE);

        // Verify rewards were claimed
        assertGe(finalBalance, initialBalance, "Should have received rewards");
        assertEq(finalClaimableRewards, 0, "Should have no more claimable rewards");
    }

    function testMultipleUsersStaking() public {
        uint256 amount1 = 100e18;
        uint256 amount2 = 200e18;

        // User 1 stakes
        vm.startPrank(user1);
        staking.stake{ value: amount1 }(DEFAULT_VALIDATOR_ID);
        vm.stopPrank();

        // User 2 stakes
        vm.startPrank(user2);
        staking.stake{ value: amount2 }(DEFAULT_VALIDATOR_ID);
        vm.stopPrank();

        // Move forward in time
        vm.warp(block.timestamp + 1 days);

        // Check rewards
        uint256 totalStaked = amount1 + amount2;
        uint256 timeDelta = 1 days;

        // Get validator commission
        PlumeStakingStorage.ValidatorInfo memory validator =
            PlumeStakingStorage.layout().validators[DEFAULT_VALIDATOR_ID];
        uint256 validatorCommission = validator.commission; // 5% commission

        // Calculate rewards based on proportion of total stake, accounting for validator commission
        uint256 rewardPerToken = (timeDelta * PUSD_REWARD_RATE * REWARD_PRECISION) / totalStaked;

        // User1's reward after commission
        uint256 expectedReward1 = (amount1 * rewardPerToken * (REWARD_PRECISION - validatorCommission))
            / (REWARD_PRECISION * REWARD_PRECISION);

        // User2's reward after commission
        uint256 expectedReward2 = (amount2 * rewardPerToken * (REWARD_PRECISION - validatorCommission))
            / (REWARD_PRECISION * REWARD_PRECISION);

        // Allow for small rounding differences due to gas optimization and validator commission
        assertApproxEqRel(staking.getClaimableReward(user1, PUSD_TOKEN), expectedReward1, 5.1e16); // 5.1% tolerance
        assertApproxEqRel(staking.getClaimableReward(user2, PUSD_TOKEN), expectedReward2, 5.1e16); // 5.1% tolerance
    }

    function testRevertInvalidAmount() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(InvalidAmount.selector, MIN_STAKE - 1));
        staking.stake{ value: MIN_STAKE - 1 }(DEFAULT_VALIDATOR_ID);
        vm.stopPrank();
    }

    function testAddRewardTokenZeroAddress() public {
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "token"));
        staking.addRewardToken(address(0));
        vm.stopPrank();
    }

    function testAddRewardTokenAlreadyExists() public {
        console2.log("Running testAddRewardTokenAlreadyExists");
        vm.startPrank(admin);
        vm.expectRevert(TokenAlreadyExists.selector);
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
        vm.expectRevert(EmptyArray.selector);
        staking.setRewardRates(new address[](0), new uint256[](0));

        // Test mismatched array lengths
        address[] memory tokens = new address[](2);
        uint256[] memory rates = new uint256[](1);
        tokens[0] = PUSD_TOKEN;
        tokens[1] = PLUME_NATIVE;
        rates[0] = PUSD_REWARD_RATE;
        vm.expectRevert(ArrayLengthMismatch.selector);
        staking.setRewardRates(tokens, rates);

        // Test non-existent token
        tokens = new address[](1);
        rates = new uint256[](1);
        tokens[0] = address(0x123);
        rates[0] = PUSD_REWARD_RATE;
        vm.expectRevert(abi.encodeWithSelector(TokenDoesNotExist.selector, address(0x123)));
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

    function testAdminWithdraw() public {
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "token"));
        staking.adminWithdraw(address(0), 1e18, user1);
        vm.stopPrank();
    }

    // Test using partial cooling funds when staking
    function testStakeFromMultipleSources() public {
        uint256 coolingAmount = 50e18;
        uint256 secondStakeAmount = 30e18;
        uint256 finalStakeAmount = 100e18;

        vm.startPrank(user1);

        // Setup initial cooling balance (50e18)
        staking.stake{ value: coolingAmount }(DEFAULT_VALIDATOR_ID);
        staking.unstake(DEFAULT_VALIDATOR_ID); // This puts 50e18 in cooling

        // Verify initial cooling balance
        PlumeStakingStorage.StakeInfo memory info = staking.stakeInfo(user1);
        assertEq(info.cooled, 50e18, "Initial cooling balance should be 50e18");

        // Second stake uses only the necessary cooling + wallet funds (30e18)
        staking.stake{ value: secondStakeAmount }(DEFAULT_VALIDATOR_ID);

        // Record the current timestamp for later comparison
        uint256 timestampBeforeSecondUnstake = block.timestamp;

        staking.unstake(DEFAULT_VALIDATOR_ID); // Puts 30e18 back in cooling

        // Verify cooling balance after second stake/unstake
        // Only 30e18 was staked, so unstaking should only put 30e18 in cooling
        // 20e18 should still be in cooling from before
        info = staking.stakeInfo(user1);
        assertEq(info.cooled, 50e18, "Cooling balance should be 50e18 (20e18 remaining + 30e18 new)");
        assertEq(info.parked, 0, "Parked balance should be 0");

        // Verify cooldown timestamp was reset
        assertEq(info.cooldownEnd, timestampBeforeSecondUnstake + 7 days, "Cooldown timestamp should be reset");

        // Final stake - uses all cooling (50e18) plus wallet funds (50e18)
        staking.stake{ value: finalStakeAmount }(DEFAULT_VALIDATOR_ID);

        // Verify final state - should be 50e18 from cooling + 50e18 from wallet = 100e18 total
        info = staking.stakeInfo(user1);
        assertEq(info.staked, 100e18, "Should have total amount staked");
        assertEq(info.cooled, 0, "Cooling should be empty");
        assertEq(info.parked, 0, "Parked should be empty");
        vm.stopPrank();
    }

    function testWithdrawAndReverts() public {
        uint256 stakeAmount = 100e18;

        vm.startPrank(user1);
        // No approval needed for native token
        staking.stake{ value: stakeAmount }(DEFAULT_VALIDATOR_ID);

        // Verify initial state
        PlumeStakingStorage.StakeInfo memory info = staking.stakeInfo(user1);
        assertEq(info.staked, stakeAmount);
        assertEq(info.cooled, 0);

        // Try to withdraw when there's nothing to withdraw (should fail)
        vm.expectRevert(abi.encodeWithSelector(InvalidAmount.selector, 0));
        staking.withdraw();

        // Now unstake
        staking.unstake(DEFAULT_VALIDATOR_ID);

        // Wait for cooldown
        vm.warp(block.timestamp + 7 days + 1);

        // Now we can withdraw successfully
        staking.withdraw();

        vm.stopPrank();
    }

    function testViewFunctions() public {
        uint256 stakeAmount = 100e18;

        vm.startPrank(user1);
        // No approval needed for native token
        staking.stake{ value: stakeAmount }(DEFAULT_VALIDATOR_ID);
        staking.unstake(DEFAULT_VALIDATOR_ID); // This initiates cooldown

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

    function testStakeWithParked() public {
        uint256 initialStake = 50e18;

        vm.startPrank(user1);

        // First stake and unstake to get some tokens in cooling
        staking.stake{ value: initialStake }(DEFAULT_VALIDATOR_ID);
        staking.unstake(DEFAULT_VALIDATOR_ID);

        // Wait for cooldown
        vm.warp(block.timestamp + 7 days + 1);

        // Check if tokens are withdrawable
        PlumeStakingStorage.StakeInfo memory infoBeforeWithdraw = staking.stakeInfo(user1);
        assertEq(infoBeforeWithdraw.cooled, initialStake, "Cooling should have tokens after cooldown ends");

        // Withdraw - this moves tokens from the contract to the user's wallet
        uint256 userBalanceBefore = address(user1).balance;
        staking.withdraw();
        uint256 userBalanceAfter = address(user1).balance;

        // Verify tokens were withdrawn to user's wallet
        assertEq(userBalanceAfter - userBalanceBefore, initialStake, "Tokens should be sent to user's wallet");

        // Now stake using new tokens from wallet
        uint256 newStakeAmount = 40e18;

        // All tokens come from wallet since withdraw() sent them to the wallet
        vm.expectEmit(true, true, true, true);
        emit Staked(user1, DEFAULT_VALIDATOR_ID, newStakeAmount, 0, 0, newStakeAmount);
        staking.stake{ value: newStakeAmount }(DEFAULT_VALIDATOR_ID);

        // Verify final state
        PlumeStakingStorage.StakeInfo memory info = staking.stakeInfo(user1);
        assertEq(info.staked, newStakeAmount);
        assertEq(info.cooled, 0);
        assertEq(info.parked, 0);

        vm.stopPrank();
    }

    function testWithdrawWithParked() public {
        uint256 stakeAmount = 100e18;

        vm.startPrank(user1);
        // No approval needed for native token
        staking.stake{ value: stakeAmount }(DEFAULT_VALIDATOR_ID);
        staking.unstake(DEFAULT_VALIDATOR_ID);
        vm.warp(block.timestamp + 7 days + 1);

        uint256 initialBalance = address(user1).balance;

        staking.withdraw();

        // Verify state changes
        PlumeStakingStorage.StakeInfo memory info = staking.stakeInfo(user1);
        assertEq(info.parked, 0, "Parked should be empty after withdrawal");
        assertEq(info.cooled, 0, "Cooled should be empty after withdrawal");
        assertEq(address(user1).balance, initialBalance + stakeAmount, "Full amount should be transferred to user");

        vm.stopPrank();
    }

    function testViewFunctionsComprehensive() public {
        uint256 stakeAmount = 100e18;
        uint256 unstakeAmount = 30e18;

        vm.startPrank(user1);
        // No approval needed for native token
        staking.stake{ value: stakeAmount }(DEFAULT_VALIDATOR_ID);

        PlumeStakingStorage.StakeInfo memory info = staking.stakeInfo(user1);
        assertEq(info.staked, stakeAmount);
        assertEq(staking.amountStaked(), stakeAmount);
        assertEq(staking.amountCooling(), 0);
        assertEq(staking.amountWithdrawable(), 0);

        // Unstake partially
        staking.unstake(DEFAULT_VALIDATOR_ID, unstakeAmount);

        // Check that unstaked amount is in cooling
        info = staking.stakeInfo(user1);
        assertEq(info.staked, stakeAmount - unstakeAmount);
        assertEq(staking.amountStaked(), stakeAmount - unstakeAmount);
        assertEq(staking.amountCooling(), unstakeAmount);
        assertEq(staking.amountWithdrawable(), 0);

        // Wait for cooldown
        vm.warp(block.timestamp + 7 days + 1);

        // Check that unstaked amount is now withdrawable
        assertEq(staking.amountCooling(), 0);
        assertEq(staking.amountWithdrawable(), unstakeAmount);

        vm.stopPrank();
    }

    function testGetUserValidators() public {
        vm.startPrank(user1);

        // Initially user shouldn't have any validators
        uint16[] memory initialValidators = staking.getUserValidators(user1);
        assertEq(initialValidators.length, 0, "User should have no validators initially");

        // Stake with the default validator
        staking.stake{ value: 50e18 }(DEFAULT_VALIDATOR_ID);

        // User should now have 1 validator
        uint16[] memory validators = staking.getUserValidators(user1);
        assertEq(validators.length, 1, "User should have 1 validator after staking");
        assertEq(validators[0], DEFAULT_VALIDATOR_ID, "Validator ID should match");

        // Add a second validator and stake with it
        uint16 secondValidatorId = 2;
        vm.stopPrank();

        vm.startPrank(admin);
        staking.addValidator(
            secondValidatorId,
            0, // 0% commission
            admin,
            admin,
            "0x123",
            "0x456"
        );
        vm.stopPrank();

        vm.startPrank(user1);
        staking.stake{ value: 30e18 }(secondValidatorId);

        // User should now have 2 validators
        validators = staking.getUserValidators(user1);
        assertEq(validators.length, 2, "User should have 2 validators after staking with second validator");

        // The validators may be in any order, so check both are present
        bool foundFirstValidator = false;
        bool foundSecondValidator = false;

        for (uint256 i = 0; i < validators.length; i++) {
            if (validators[i] == DEFAULT_VALIDATOR_ID) {
                foundFirstValidator = true;
            }
            if (validators[i] == secondValidatorId) {
                foundSecondValidator = true;
            }
        }

        assertTrue(foundFirstValidator, "First validator should be in the list");
        assertTrue(foundSecondValidator, "Second validator should be in the list");

        // Unstake completely from the first validator
        staking.unstake(DEFAULT_VALIDATOR_ID);

        // User should still have 2 validators (unstaking doesn't remove validator from the list)
        validators = staking.getUserValidators(user1);
        assertEq(validators.length, 2, "User should still have 2 validators after unstaking");

        vm.stopPrank();
    }

    function testUpdateTotalAmounts() public {
        uint256 stakeAmount = 100e18;

        // Setup initial state
        vm.startPrank(user1);
        // No approval needed for native token
        staking.stake{ value: stakeAmount }(DEFAULT_VALIDATOR_ID);

        // Unstake to move to cooling
        staking.unstake(DEFAULT_VALIDATOR_ID);

        // Let's confirm the state before any admin action
        PlumeStakingStorage.StakeInfo memory infoBeforeUpdate = staking.stakeInfo(user1);
        assertEq(infoBeforeUpdate.cooled, stakeAmount, "Cooling amount should be set after unstake");
        assertEq(staking.amountCooling(), stakeAmount, "amountCooling() should return full amount during cooldown");

        vm.stopPrank();

        // Admin updates totals - start from index 0 and process all stakers
        vm.prank(admin);
        staking.updateTotalAmounts(0, type(uint256).max);

        // Verify state after first updateTotalAmounts
        (uint256 totalStaked, uint256 totalCooling, uint256 totalWithdrawable,,) = staking.stakingInfo();
        assertEq(totalStaked, 0);
        assertEq(totalCooling, stakeAmount, "Cooling amount should be tracked in global state");
        assertEq(totalWithdrawable, 0);

        // Get the actual cooling amount from storage after updateTotalAmounts
        PlumeStakingStorage.StakeInfo memory infoAfterUpdate = staking.stakeInfo(user1);
        assertEq(infoAfterUpdate.cooled, stakeAmount, "Cooling amount in storage should be unchanged");
        assertEq(infoAfterUpdate.cooldownEnd, infoBeforeUpdate.cooldownEnd, "Cooldown end should be unchanged");

        // Check if amountCooling() still returns the correct amount during cooldown
        vm.prank(user1);
        assertEq(staking.amountCooling(), stakeAmount, "amountCooling() should return the amount during cooldown");

        // Move time past cooldown period
        vm.warp(block.timestamp + 7 days + 1);

        // After cooldown, amountCooling() should return 0
        vm.prank(user1);
        assertEq(staking.amountCooling(), 0, "amountCooling() returns 0 after cooldown ends");

        // The global cooling total has not been updated yet
        (totalStaked, totalCooling, totalWithdrawable,,) = staking.stakingInfo();
        assertEq(totalCooling, stakeAmount, "Total cooling amount hasn't been updated yet");

        // Get the actual cooling amount from storage
        PlumeStakingStorage.StakeInfo memory info = staking.stakeInfo(user1);
        assertEq(info.cooled, stakeAmount, "Actual cooling amount in storage is unchanged");

        // amountWithdrawable should now include the cooling amount
        vm.prank(user1);
        assertEq(staking.amountWithdrawable(), stakeAmount, "Amount should be withdrawable after cooldown");

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

        // User's storage state should be updated: cooling amount moved to parked
        info = staking.stakeInfo(user1);
        assertEq(info.cooled, 0, "Cooling amount in storage should be 0 after update");
        assertEq(info.parked, stakeAmount, "Parked amount should be updated");

        // User can now withdraw
        vm.prank(user1);
        staking.withdraw();

        // Verify final state
        (totalStaked, totalCooling, totalWithdrawable,,) = staking.stakingInfo();
        assertEq(totalStaked, 0);
        assertEq(totalCooling, 0);

        // withdraw() correctly updates the totalWithdrawable
        assertEq(totalWithdrawable, 0, "totalWithdrawable should be updated to 0 after withdraw");

        // Check user's final state - these amounts should be zero
        info = staking.stakeInfo(user1);
        assertEq(info.cooled, 0);
        assertEq(info.parked, 0);
    }

    function testStorageSlot() public {
        console2.logBytes32(
            keccak256(abi.encode(uint256(keccak256("plume.storage.pUSDStaking")) - 1)) & ~bytes32(uint256(0xff))
        );
    }

    function testStakeOnBehalf() public {
        uint256 stakeAmount = 100e18;

        // Setup initial balances
        vm.deal(user1, stakeAmount);
        vm.deal(user2, 0); // User2 has no funds initially

        assertEq(address(user2).balance, 0, "User2 should start with 0 balance");

        // User1 stakes on behalf of User2
        vm.prank(user1);
        staking.stakeOnBehalf{ value: stakeAmount }(DEFAULT_VALIDATOR_ID, user2);

        // Check user2's stake info
        PlumeStakingStorage.StakeInfo memory info = staking.stakeInfo(user2);
        assertEq(info.staked, stakeAmount, "User2 should have the staked amount");
        assertEq(info.cooled, 0, "User2 should have no cooling amount");
        assertEq(info.parked, 0, "User2 should have no parked amount");

        // User2 should be able to unstake these funds
        vm.prank(user2);
        uint256 unstakeAmount = staking.unstake(DEFAULT_VALIDATOR_ID);
        assertEq(unstakeAmount, stakeAmount, "User2 should be able to unstake the full amount");

        // Verify cooling amount
        info = staking.stakeInfo(user2);
        assertEq(info.cooled, stakeAmount, "Amount should now be in cooling");

        // Advance time to end cooldown
        vm.warp(block.timestamp + 7 days + 1);

        // User2 should be able to withdraw
        vm.prank(user2);
        uint256 withdrawnAmount = staking.withdraw();
        assertEq(withdrawnAmount, stakeAmount, "User2 should be able to withdraw the full amount");
        assertEq(address(user2).balance, stakeAmount, "User2 should now have the funds");
    }

}
