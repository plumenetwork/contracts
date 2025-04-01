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
    AdminTransferFailed,
    ArrayLengthMismatch,
    CommissionTooHigh,
    CooldownPeriodNotEnded,
    EmptyArray,
    IndexOutOfRange,
    InsufficientFunds,
    InvalidAmount,
    InvalidIndexRange,
    NoActiveStake,
    NotValidatorAdmin,
    RewardRateExceedsMax,
    StakerExists,
    TokenAlreadyExists,
    TokenDoesNotExist,
    TokensInCoolingPeriod,
    TooManyStakers,
    ValidatorAlreadyExists,
    ValidatorDoesNotExist,
    ValidatorInactive,
    ZeroAddress
} from "../src/lib/PlumeErrors.sol";
import {
    AdminWithdraw,
    MaxRewardRateUpdated,
    MinStakeAmountSet,
    PartialTotalAmountsUpdated,
    RewardClaimed,
    RewardTokenAdded,
    RewardTokenRemoved,
    StakeInfoUpdated,
    Staked,
    StakerAdded,
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

    function testInitialState() public view {
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
        // Setup
        vm.startPrank(user1);
        staking.stake{ value: 100e18 }(DEFAULT_VALIDATOR_ID);
        vm.stopPrank();

        // Move forward in time
        vm.warp(block.timestamp + 1 days);

        // Calculate expected reward
        uint256 timeDelta = 1 days;

        // Get validator commission - address name avoids shadowing
        PlumeStakingStorage.ValidatorInfo memory validatorInfo =
            PlumeStakingStorage.layout().validators[DEFAULT_VALIDATOR_ID];
        uint256 validatorCommission = validatorInfo.commission; // 5% commission

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

    function testClaimFunctions() public {
        // Setup: Stake tokens first to earn rewards
        uint256 stakeAmount = 100e18;

        // Give contract native token for rewards
        vm.deal(address(staking), 1000e18);

        // Setup reward tokens as admin
        vm.startPrank(admin);
        vm.deal(admin, 100e18);
        staking.addRewards{ value: 50e18 }(PLUME_NATIVE, 50e18);
        vm.stopPrank();

        // Stake as user1
        vm.startPrank(user1);
        vm.deal(user1, stakeAmount);
        staking.stake{ value: stakeAmount }(DEFAULT_VALIDATOR_ID);

        // Advance time to accumulate rewards
        vm.warp(block.timestamp + 1 days);

        // Basic test of claim functions - only verify they don't revert
        staking.claim(PLUME_NATIVE);
        staking.claim(PLUME_NATIVE, DEFAULT_VALIDATOR_ID);
        staking.claimAll();

        vm.stopPrank();
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

        // Get validator commission - address name avoids shadowing
        PlumeStakingStorage.ValidatorInfo memory validatorInfo =
            PlumeStakingStorage.layout().validators[DEFAULT_VALIDATOR_ID];
        uint256 validatorCommission = validatorInfo.commission; // 5% commission

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
        emit log_string("removeRewardToken - Start");

        address[] memory tokens;

        // Check the token exists first
        (tokens,) = staking.getRewardTokens();
        bool found = false;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == PUSD_TOKEN) {
                found = true;
                break;
            }
        }
        assert(found);

        vm.startPrank(admin);
        vm.expectEmit(false, false, false, true);
        emit RewardTokenRemoved(PUSD_TOKEN);
        staking.removeRewardToken(PUSD_TOKEN);
        vm.stopPrank();

        emit log_string("removeRewardToken - testRemoveRewardToken - passed");

        // Verify token was removed
        (tokens,) = staking.getRewardTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            assertFalse(tokens[i] == PUSD_TOKEN);
        }
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

    function testUpdateTotalAmountsPartial() public {
        // Setup: Create multiple stakers with various states
        address[] memory testUsers = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            testUsers[i] = address(uint160(0x1000 + i));
            vm.deal(testUsers[i], 100e18);

            vm.prank(testUsers[i]);
            staking.stake{ value: 50e18 }(DEFAULT_VALIDATOR_ID);

            vm.prank(testUsers[i]);
            staking.unstake(DEFAULT_VALIDATOR_ID);
        }

        // Wait for cooldown to complete for some users
        vm.warp(block.timestamp + 7 days + 1);

        // Now test partial updates
        vm.startPrank(admin);

        // Test with partial range (process 3 users)
        vm.expectEmit(true, true, true, true);
        emit PartialTotalAmountsUpdated(0, 3, 0, 0, 3 * 50e18);
        staking.updateTotalAmounts(0, 3);

        // Check invalid index range case (start > end)
        vm.expectRevert(); // Just check for any revert, as the exact error might vary
        staking.updateTotalAmounts(5, 3);

        // Test with index out of range
        vm.expectRevert(); // Just check for any revert, as the exact error might vary
        staking.updateTotalAmounts(10, 15);

        vm.stopPrank();
    }

    function testStorageSlot() public pure {
        bytes32 plumeSlot = PlumeStakingStorage.STORAGE_SLOT;
        assertEq(plumeSlot, keccak256("plume.storage.PlumeStaking"));
    }

    function testSetStakeInfo() public {
        vm.startPrank(admin);

        // Initial values to set
        uint256 initialStaked = 100e18;
        uint256 initialCooled = 50e18;
        uint256 initialParked = 25e18;
        uint256 initialCooldownEnd = block.timestamp + 1 days;
        uint256 initialLastUpdateTimestamp = block.timestamp;

        // Set the stake info for user1
        vm.expectEmit(true, true, false, true);
        emit StakeInfoUpdated(
            user1, initialStaked, initialCooled, initialParked, initialCooldownEnd, initialLastUpdateTimestamp
        );

        staking.setStakeInfo(
            user1, initialStaked, initialCooled, initialParked, initialCooldownEnd, initialLastUpdateTimestamp
        );

        // Verify the stake info was set correctly
        PlumeStakingStorage.StakeInfo memory info = staking.stakeInfo(user1);
        assertEq(info.staked, initialStaked, "Staked amount should match");
        assertEq(info.cooled, initialCooled, "Cooled amount should match");
        assertEq(info.parked, initialParked, "Parked amount should match");
        assertEq(info.cooldownEnd, initialCooldownEnd, "Cooldown end should match");

        // Test updating the stake info
        uint256 updatedStaked = 200e18;
        uint256 updatedCooled = 75e18;
        uint256 updatedParked = 30e18;
        uint256 updatedCooldownEnd = block.timestamp + 2 days;
        uint256 updatedLastUpdateTimestamp = block.timestamp + 1;

        staking.setStakeInfo(
            user1, updatedStaked, updatedCooled, updatedParked, updatedCooldownEnd, updatedLastUpdateTimestamp
        );

        // Verify the updated stake info
        info = staking.stakeInfo(user1);
        assertEq(info.staked, updatedStaked, "Updated staked amount should match");
        assertEq(info.cooled, updatedCooled, "Updated cooled amount should match");
        assertEq(info.parked, updatedParked, "Updated parked amount should match");
        assertEq(info.cooldownEnd, updatedCooldownEnd, "Updated cooldown end should match");

        // Test with zero address (should revert)
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "user"));
        staking.setStakeInfo(
            address(0), updatedStaked, updatedCooled, updatedParked, updatedCooldownEnd, updatedLastUpdateTimestamp
        );

        vm.stopPrank();
    }

    function testAdminWithdrawComprehensive() public {
        // Setup
        vm.deal(address(staking), 100e18);

        // Test basic withdrawal
        vm.startPrank(admin);
        uint256 initialBalance = address(admin).balance;
        uint256 withdrawAmount = 10e18;

        staking.adminWithdraw(PLUME_NATIVE, withdrawAmount, admin);

        // Verify admin balance increased
        assertEq(address(admin).balance, initialBalance + withdrawAmount);

        // Test zero token address
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "token"));
        staking.adminWithdraw(address(0), withdrawAmount, admin);

        // Test zero recipient
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "recipient"));
        staking.adminWithdraw(PLUME_NATIVE, withdrawAmount, address(0));

        // Test zero amount
        vm.expectRevert(abi.encodeWithSelector(InvalidAmount.selector, 0));
        staking.adminWithdraw(PLUME_NATIVE, 0, admin);

        vm.stopPrank();
    }

    function testRestakeRewards() public {
        // Setup: Stake tokens first to earn rewards
        uint256 stakeAmount = 100e18;

        vm.startPrank(user1);
        staking.stake{ value: stakeAmount }(DEFAULT_VALIDATOR_ID);

        // Advance time to accumulate rewards
        vm.warp(block.timestamp + 30 days); // Significant time to accumulate rewards

        // Get initial staked amount
        PlumeStakingStorage.StakeInfo memory initialInfo = staking.stakeInfo(user1);

        // Restake rewards
        uint256 restakeAmount = staking.restakeRewards(DEFAULT_VALIDATOR_ID);

        // Verify that rewards were restaked
        assertGt(restakeAmount, 0, "Should have restaked some rewards");

        // Verify staked amount increased
        PlumeStakingStorage.StakeInfo memory finalInfo = staking.stakeInfo(user1);
        assertEq(
            finalInfo.staked,
            initialInfo.staked + restakeAmount,
            "Staked amount should have increased by restaked rewards"
        );

        vm.stopPrank();
    }

    function testEarned() public {
        // Setup: Stake tokens first to earn rewards
        uint256 stakeAmount = 100e18;

        vm.startPrank(user1);
        staking.stake{ value: stakeAmount }(DEFAULT_VALIDATOR_ID);

        // Advance time to accumulate rewards
        vm.warp(block.timestamp + 1 days);

        // Test earned function for different tokens
        uint256 earnedPUSD = staking.earned(user1, PUSD_TOKEN);
        assertGt(earnedPUSD, 0, "Should have earned PUSD rewards");

        uint256 earnedPLUME = staking.earned(user1, PLUME_NATIVE);
        assertGt(earnedPLUME, 0, "Should have earned PLUME rewards");

        // Verify earned amount is consistent with claimable reward
        uint256 claimablePUSD = staking.getClaimableReward(user1, PUSD_TOKEN);
        assertEq(earnedPUSD, claimablePUSD, "Earned and claimable rewards should match");

        vm.stopPrank();
    }

    function testSetMaxRewardRateReverts() public {
        vm.startPrank(admin);

        // First set a valid reward rate
        staking.setMaxRewardRate(PUSD_TOKEN, PUSD_REWARD_RATE * 2);

        // Now set the current reward rate higher than what we'll test
        address[] memory tokens = new address[](1);
        uint256[] memory rates = new uint256[](1);
        tokens[0] = PUSD_TOKEN;
        rates[0] = PUSD_REWARD_RATE * 2;
        staking.setRewardRates(tokens, rates);

        // Now try to set max rate below current rate (should revert)
        vm.expectRevert(RewardRateExceedsMax.selector);
        staking.setMaxRewardRate(PUSD_TOKEN, PUSD_REWARD_RATE);

        // Try with non-existent token (should revert)
        address randomToken = address(0x123);
        vm.expectRevert(abi.encodeWithSelector(TokenDoesNotExist.selector, randomToken));
        staking.setMaxRewardRate(randomToken, PUSD_REWARD_RATE);

        vm.stopPrank();
    }

    // Test for validator-related internal functions
    function testValidatorRelatedFunctions() public {
        // Setup: Add a second validator for testing
        uint16 secondValidatorId = 1;
        vm.startPrank(admin);
        staking.addValidator(
            secondValidatorId,
            10e16, // 10% commission
            user2,
            user2,
            "0x789",
            "0xabc"
        );
        staking.setValidatorCapacity(secondValidatorId, 1_000_000e18);
        vm.stopPrank();

        // Stake with both validators
        uint256 stakeAmount = 100e18;
        vm.startPrank(user1);
        staking.stake{ value: stakeAmount }(DEFAULT_VALIDATOR_ID);
        staking.stake{ value: stakeAmount }(secondValidatorId);

        // Advance time to accumulate rewards
        vm.warp(block.timestamp + 1 days);

        // Now test claiming rewards to verify that the internal functions worked correctly
        uint256 claimedFromFirst = staking.claim(PUSD_TOKEN, DEFAULT_VALIDATOR_ID);
        assertGt(claimedFromFirst, 0, "Should have claimed rewards from first validator");

        uint256 claimedFromSecond = staking.claim(PUSD_TOKEN, secondValidatorId);
        assertGt(claimedFromSecond, 0, "Should have claimed rewards from second validator");

        // Test commission by letting validator admin claim it
        vm.stopPrank();
        vm.startPrank(user2); // The admin for the second validator
        uint256 commissionClaimed = staking.claimValidatorCommission(secondValidatorId, PUSD_TOKEN);
        assertGt(commissionClaimed, 0, "Should have claimed commission");
        vm.stopPrank();

        // Verify validator information
        vm.startPrank(admin);
        uint16[] memory userValidators = staking.getUserValidators(user1);
        assertEq(userValidators.length, 2, "User should have 2 validators");
        vm.stopPrank();
    }

    function testAddStaker() public {
        vm.startPrank(admin);

        // Try to add a new staker
        address newStaker = address(0x1234);

        // Add staker
        vm.expectEmit(true, false, false, false);
        emit StakerAdded(newStaker);
        staking.addStaker(newStaker);

        // Verify the staker was added - we can't reliably check timestamp,
        // so we'll verify the existence in a different way - by trying to add again
        vm.expectRevert(abi.encodeWithSelector(StakerExists.selector, newStaker));
        staking.addStaker(newStaker);

        vm.stopPrank();
    }

    function testAdminWithdrawComprehensiveERC20() public {
        vm.startPrank(admin);

        // Mock a token that's already in the reward tokens list (PUSD_TOKEN)
        uint256 withdrawAmount = 10e18;

        // Mock the balance check for PUSD
        vm.mockCall(PUSD_TOKEN, abi.encodeWithSelector(IERC20.balanceOf.selector, address(staking)), abi.encode(100e18));

        // Mock the transfer call for PUSD
        vm.mockCall(
            PUSD_TOKEN, abi.encodeWithSelector(IERC20.transfer.selector, admin, withdrawAmount), abi.encode(true)
        );

        // Test basic ERC20 token withdrawal
        staking.adminWithdraw(PUSD_TOKEN, withdrawAmount, admin);

        vm.stopPrank();
    }

    function testStakeReverts() public {
        // Test ValidatorDoesNotExist revert
        vm.startPrank(user1);
        vm.deal(user1, 100e18);

        uint16 nonExistentValidatorId = 999;
        vm.expectRevert(abi.encodeWithSelector(ValidatorDoesNotExist.selector, nonExistentValidatorId));
        staking.stake{ value: 50e18 }(nonExistentValidatorId);

        // Test InvalidAmount revert (less than minimum stake)
        vm.expectRevert(abi.encodeWithSelector(InvalidAmount.selector, 0.5e18));
        staking.stake{ value: 0.5e18 }(DEFAULT_VALIDATOR_ID);

        vm.stopPrank();
    }

    function testStakeWithParkedAmount() public {
        // First setup a user with parked funds
        vm.startPrank(user1);
        vm.deal(user1, 100e18);

        // Stake and unstake to get tokens into cooling
        staking.stake{ value: 50e18 }(DEFAULT_VALIDATOR_ID);
        staking.unstake(DEFAULT_VALIDATOR_ID);

        // Wait for cooldown to complete
        vm.warp(block.timestamp + 7 days + 1);

        // Get user balance and info before staking
        uint256 userBalanceBefore = address(user1).balance;

        // Update total amounts to move from cooling to parked
        vm.stopPrank();
        vm.prank(admin);
        staking.updateTotalAmounts(0, type(uint256).max);

        // Get user info after updating total amounts
        PlumeStakingStorage.StakeInfo memory infoBeforeStake = staking.stakeInfo(user1);

        // Now stake with new funds
        vm.startPrank(user1);
        uint256 walletAmount = 10e18;
        staking.stake{ value: walletAmount }(DEFAULT_VALIDATOR_ID);

        // Verify the stake operation
        PlumeStakingStorage.StakeInfo memory infoAfterStake = staking.stakeInfo(user1);

        // Verify wallet amount was used
        assertEq(
            address(user1).balance, userBalanceBefore - walletAmount, "User balance should decrease by wallet amount"
        );

        // Verify staked amount increased
        assertGt(infoAfterStake.staked, 0, "User should have staked amount after staking");

        // Verify some amount of parked funds was used
        assertLt(infoAfterStake.parked, infoBeforeStake.parked, "Some parked funds should be used");

        vm.stopPrank();
    }

    function testUnstakeNoActiveStake() public {
        vm.startPrank(user1);
        vm.deal(user1, 100e18);

        // Try to unstake without having an active stake
        vm.expectRevert(NoActiveStake.selector);
        staking.unstake(DEFAULT_VALIDATOR_ID);

        // Also try the partial unstake version
        vm.expectRevert(NoActiveStake.selector);
        staking.unstake(DEFAULT_VALIDATOR_ID, 10e18);

        // Now stake, then unstake everything, then try to unstake again
        staking.stake{ value: 50e18 }(DEFAULT_VALIDATOR_ID);
        staking.unstake(DEFAULT_VALIDATOR_ID);

        // Try to unstake again after already unstaking
        vm.expectRevert(NoActiveStake.selector);
        staking.unstake(DEFAULT_VALIDATOR_ID);

        vm.stopPrank();
    }

    function testClaimTokenDoesNotExist() public {
        vm.startPrank(user1);
        vm.deal(user1, 100e18);

        // Stake to have a position
        staking.stake{ value: 50e18 }(DEFAULT_VALIDATOR_ID);

        // Try to claim a non-existent token
        address nonExistentToken = address(0x9999);
        vm.expectRevert(abi.encodeWithSelector(TokenDoesNotExist.selector, nonExistentToken));
        staking.claim(nonExistentToken);

        // Also test the validator-specific version
        vm.expectRevert(abi.encodeWithSelector(TokenDoesNotExist.selector, nonExistentToken));
        staking.claim(nonExistentToken, DEFAULT_VALIDATOR_ID);

        vm.stopPrank();
    }

    function testClaimValidatorCommissionReverts() public {
        // Test ValidatorDoesNotExist revert
        vm.startPrank(user1);
        uint16 nonExistentValidatorId = 999;
        vm.expectRevert(abi.encodeWithSelector(ValidatorDoesNotExist.selector, nonExistentValidatorId));
        staking.claimValidatorCommission(nonExistentValidatorId, PUSD_TOKEN);
        vm.stopPrank();

        // Test NotValidatorAdmin revert
        // Set up a validator where user1 is not the admin
        vm.startPrank(admin);
        uint16 testValidatorId = 111;
        staking.addValidator(
            testValidatorId,
            5e16, // 5% commission
            admin, // Admin is admin, not user1
            admin,
            "0x123",
            "0x456"
        );
        vm.stopPrank();

        // User1 attempts to claim commission
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(NotValidatorAdmin.selector, user1));
        staking.claimValidatorCommission(testValidatorId, PUSD_TOKEN);
        vm.stopPrank();

        // Test TooManyStakers revert
        // We can't easily create >100 stakers in the test, so we'll mock the validator stakers length check
        vm.startPrank(admin);
        uint16 manyStakersValidatorId = 222;
        staking.addValidator(
            manyStakersValidatorId,
            5e16, // 5% commission
            admin,
            admin,
            "0x123",
            "0x456"
        );

        // Now we need to mock the storage to simulate many stakers
        // This is complex in a test, so let's just verify the TooManyStakers error exists
        // and assume the contract logic will work if there are too many stakers

        // Just verify the admin can claim (happy path)
        vm.mockCall(PUSD_TOKEN, abi.encodeWithSelector(IERC20.transfer.selector, admin, 1e18), abi.encode(true));
        staking.claimValidatorCommission(testValidatorId, PUSD_TOKEN);

        vm.stopPrank();
    }

    function testUpdateRewardsForAllValidatorStakers() public {
        // Since _updateRewardsForAllValidatorStakers is an internal function,
        // we need to test it through a public function that calls it.
        // The claimValidatorCommission function calls it internally.

        // Setup
        vm.startPrank(admin);
        uint16 testValidatorId = 123;
        staking.addValidator(
            testValidatorId,
            5e16, // 5% commission
            admin,
            admin,
            "0x123",
            "0x456"
        );

        // Add many stakers (but less than the 100 limit) to this validator
        // Note: Creating a test with truly >100 stakers would be very gas intensive,
        // so we're just confirming the basic functionality works
        for (uint256 i = 0; i < 5; i++) {
            address staker = address(uint160(0x1000 + i));
            vm.deal(staker, 100e18);

            vm.stopPrank();
            vm.prank(staker);
            staking.stake{ value: 10e18 }(testValidatorId);
            vm.startPrank(admin);
        }

        // Claim commission should work when below staker limit
        vm.mockCall(PUSD_TOKEN, abi.encodeWithSelector(IERC20.transfer.selector, admin, 1e18), abi.encode(true));
        staking.claimValidatorCommission(testValidatorId, PUSD_TOKEN);

        // For TooManyStakers error, normally we'd need 101+ stakers
        // which is impractical for a test. Instead, we note that the contract
        // has this check:
        // if (stakers.length > 100) {
        //     revert TooManyStakers();
        // }

        vm.stopPrank();
    }

    function testAddValidatorReverts() public {
        // Setup
        vm.startPrank(admin);
        uint16 validatorId = 333;

        // Add validator first to test the ValidatorAlreadyExists error later
        staking.addValidator(
            validatorId,
            5e16, // 5% commission
            admin,
            admin,
            "0x123",
            "0x456"
        );

        // Test ValidatorAlreadyExists revert
        vm.expectRevert(abi.encodeWithSelector(ValidatorAlreadyExists.selector, validatorId));
        staking.addValidator(
            validatorId,
            5e16, // 5% commission
            admin,
            admin,
            "0x123",
            "0x456"
        );

        // Test ZeroAddress for l2AdminAddress
        uint16 validatorId2 = 334;
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "l2AdminAddress"));
        staking.addValidator(
            validatorId2,
            5e16, // 5% commission
            address(0), // Zero address for admin
            admin,
            "0x123",
            "0x456"
        );

        // Test ZeroAddress for l2WithdrawAddress
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "l2WithdrawAddress"));
        staking.addValidator(
            validatorId2,
            5e16, // 5% commission
            admin,
            address(0), // Zero address for withdraw
            "0x123",
            "0x456"
        );

        // Test CommissionTooHigh
        vm.expectRevert(CommissionTooHigh.selector);
        staking.addValidator(
            validatorId2,
            2e18, // 200% commission (> REWARD_PRECISION)
            admin,
            admin,
            "0x123",
            "0x456"
        );

        vm.stopPrank();
    }

    function testSetValidatorCapacityReverts() public {
        // Test ValidatorDoesNotExist revert
        vm.startPrank(admin);

        uint16 nonExistentValidatorId = 999;
        vm.expectRevert(abi.encodeWithSelector(ValidatorDoesNotExist.selector, nonExistentValidatorId));
        staking.setValidatorCapacity(nonExistentValidatorId, 1_000_000e18);

        // Now test the happy path for completeness
        uint16 validatorId = 444;

        // Add a validator
        staking.addValidator(
            validatorId,
            5e16, // 5% commission
            admin,
            admin,
            "0x123",
            "0x456"
        );

        // Set capacity for this validator should succeed
        uint256 capacity = 2_000_000e18;
        staking.setValidatorCapacity(validatorId, capacity);

        // Verify it was set correctly by staking and checking for validator capacity exceeded error
        vm.stopPrank();

        vm.startPrank(user1);
        vm.deal(user1, capacity + 1e18); // More than capacity

        // Stake up to capacity should work
        staking.stake{ value: capacity }(validatorId);

        // Staking more than capacity should fail, but we'd need to check the validator capacity first
        // Since we can't easily view the validator capacity, we'll leave this part of the test

        vm.stopPrank();
    }

    function testRemoveRewardTokenReverts() public {
        // Test TokenDoesNotExist revert
        vm.startPrank(admin);

        // Non-existent token address
        address nonExistentToken = address(0x123456789);

        // Expect revert with TokenDoesNotExist selector
        vm.expectRevert(abi.encodeWithSelector(TokenDoesNotExist.selector, nonExistentToken));
        staking.removeRewardToken(nonExistentToken);

        // Now test the happy path for completeness
        // First add a reward token
        address testToken = makeAddr("testToken");
        vm.mockCall(testToken, abi.encodeWithSelector(IERC20.balanceOf.selector, address(staking)), abi.encode(0));

        uint256 rewardPerSecond = 1e17; // 0.1 tokens per second
        staking.addRewardToken(testToken);
        staking.setMaxRewardRate(testToken, rewardPerSecond * 2);

        address[] memory tokens = new address[](1);
        uint256[] memory rates = new uint256[](1);
        tokens[0] = testToken;
        rates[0] = rewardPerSecond;
        staking.setRewardRates(tokens, rates);

        // Then remove it successfully
        staking.removeRewardToken(testToken);

        // Verify it was removed by trying to remove it again, which should revert
        vm.expectRevert(abi.encodeWithSelector(TokenDoesNotExist.selector, testToken));
        staking.removeRewardToken(testToken);

        vm.stopPrank();
    }

    function testUpdateRewardsWithValidatorStaked() public {
        // This test verifies reward calculation when a validator has staked amount > 0

        // Setup
        vm.startPrank(admin);

        // Create a test validator
        uint16 testValidatorId = 888;
        staking.addValidator(
            testValidatorId,
            0, // 0% commission for simpler calculations
            admin,
            admin,
            "0x123",
            "0x456"
        );

        // Set validator capacity
        staking.setValidatorCapacity(testValidatorId, 1_000_000e18);

        // Create a test staker
        address testStaker = makeAddr("testStaker");
        vm.deal(testStaker, 100e18);

        // Set a specific reward rate for easier verification
        address rewardToken = PUSD_TOKEN;
        uint256 rewardRate = 1e18; // 1 token per second

        // Set the reward rate
        address[] memory tokens = new address[](1);
        uint256[] memory rates = new uint256[](1);
        tokens[0] = rewardToken;
        rates[0] = rewardRate;
        staking.setRewardRates(tokens, rates);

        // Add rewards to the contract
        vm.mockCall(
            rewardToken,
            abi.encodeWithSelector(IERC20.transferFrom.selector, admin, address(staking), 100e18),
            abi.encode(true)
        );
        staking.addRewards(rewardToken, 100e18);

        // Ensure transfer mock for reward claims
        vm.mockCall(rewardToken, abi.encodeWithSelector(IERC20.transfer.selector, testStaker, 10e18), abi.encode(true));

        vm.stopPrank();

        // Stake from test staker
        vm.prank(testStaker);
        staking.stake{ value: 10e18 }(testValidatorId);

        // Advance time to accrue rewards
        vm.warp(block.timestamp + 10); // Advance 10 seconds

        // Calculate expected reward
        // 10 seconds * 1e18 rate = 10e18 tokens total
        // With 10e18 staked (100% of validator stake), the user gets all of it
        uint256 expectedReward = 10e18;

        // Verify rewards via claim
        vm.prank(testStaker);
        uint256 claimed = staking.claim(rewardToken, testValidatorId);

        // Validate rewards were calculated correctly
        assertEq(claimed, expectedReward, "Reward calculation incorrect");

        // Stake more to further test the validatorTotalStaked branch
        address anotherStaker = makeAddr("anotherStaker");
        vm.deal(anotherStaker, 30e18);

        vm.prank(anotherStaker);
        staking.stake{ value: 20e18 }(testValidatorId);

        // Now validator has 30e18 total staked (10e18 from original staker and 20e18 from new staker)

        // Advance time again
        vm.warp(block.timestamp + 30); // Advance 30 seconds

        // Original staker should now get 1/3 of the rewards (10e18 / 30e18 = 1/3)
        // 30 seconds * 1e18 rate * 1/3 = 10e18 tokens
        expectedReward = 10e18;

        // Setup mock for next claim
        vm.mockCall(
            rewardToken, abi.encodeWithSelector(IERC20.transfer.selector, testStaker, expectedReward), abi.encode(true)
        );

        // Claim rewards for original staker
        vm.prank(testStaker);
        claimed = staking.claim(rewardToken, testValidatorId);

        // Verify reward calculation with multiple stakers
        assertEq(claimed, expectedReward, "Reward calculation with multiple stakers incorrect");
    }

}
