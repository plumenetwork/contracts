// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {
    ActionOnSlashedValidatorError,
    CooldownNotComplete,
    CooldownPeriodNotEnded,
    ExceedsValidatorCapacity,
    InsufficientCooldownBalance,
    InsufficientCooledAndParkedBalance,
    InsufficientFunds,
    InvalidAmount,
    NativeTransferFailed,
    NoActiveStake,
    NoRewardsToRestake,
    NoWithdrawableBalanceToRestake,
    StakeAmountTooSmall,
    TokenDoesNotExist,
    TooManyStakers,
    TransferError,
    ValidatorCapacityExceeded,
    ValidatorDoesNotExist,
    ValidatorInactive,
    ValidatorPercentageExceeded,
    ZeroAddress,
    ZeroRecipientAddress
} from "../lib/PlumeErrors.sol";

import {
    CooldownStarted,
    RewardClaimedFromValidator,
    RewardsRestaked,
    Staked,
    StakedOnBehalf,
    Unstaked,
    Withdrawn
} from "../lib/PlumeEvents.sol";

import { PlumeRewardLogic } from "../lib/PlumeRewardLogic.sol";
import { PlumeStakingStorage } from "../lib/PlumeStakingStorage.sol";
import { PlumeValidatorLogic } from "../lib/PlumeValidatorLogic.sol";
import { RewardsFacet } from "./RewardsFacet.sol";

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { DiamondBaseStorage } from "@solidstate/proxy/diamond/base/DiamondBaseStorage.sol";

using PlumeRewardLogic for PlumeStakingStorage.Layout;

/**
 * @title StakingFacet
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Facet containing core user staking, unstaking, and withdrawal functions.
 */
contract StakingFacet is ReentrancyGuardUpgradeable {

    using SafeERC20 for IERC20;
    using Address for address payable;

    // Constants moved from Base - needed here
    uint256 internal constant REWARD_PRECISION = 1e18;

    // --- Storage Access ---
    bytes32 internal constant PLUME_STORAGE_POSITION = keccak256("plume.storage.PlumeStaking");

    function _getPlumeStorage() internal pure returns (PlumeStakingStorage.Layout storage $) {
        bytes32 position = PLUME_STORAGE_POSITION;
        assembly {
            $.slot := position
        }
    }

    function _checkValidatorSlashedAndRevert(
        uint16 validatorId
    ) internal view {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        if ($.validatorExists[validatorId] && $.validators[validatorId].slashed) {
            revert ActionOnSlashedValidatorError(validatorId);
        }
    }

    /**
     * @notice Stake PLUME to a specific validator using only wallet funds
     * @param validatorId ID of the validator to stake to
     */
    function stake(
        uint16 validatorId
    ) external payable returns (uint256) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        uint256 stakeAmount = msg.value;

        if (stakeAmount < $.minStakeAmount) {
            revert StakeAmountTooSmall(stakeAmount, $.minStakeAmount);
        }
        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }
        _checkValidatorSlashedAndRevert(validatorId);
        // Check if validator is active and not slashed
        PlumeStakingStorage.ValidatorInfo storage validator = $.validators[validatorId];
        if (!validator.active || validator.slashed) {
            revert ValidatorInactive(validatorId);
        }

        // Check if this is a new stake for this specific validator
        bool isNewStakeForValidator = $.userValidatorStakes[msg.sender][validatorId].staked == 0;

        // If user is adding to an existing stake with this validator, settle their current rewards first.
        if (!isNewStakeForValidator) {
            PlumeRewardLogic.updateRewardsForValidator($, msg.sender, validatorId);
        }

        // Update stake amount
        $.userValidatorStakes[msg.sender][validatorId].staked += stakeAmount;
        $.stakeInfo[msg.sender].staked += stakeAmount;
        $.validators[validatorId].delegatedAmount += stakeAmount;
        $.validatorTotalStaked[validatorId] += stakeAmount;
        $.totalStaked += stakeAmount;

        // Check if exceeding validator capacity
        uint256 newDelegatedAmount = $.validators[validatorId].delegatedAmount;
        uint256 maxCapacity = $.validators[validatorId].maxCapacity;
        if (maxCapacity > 0 && newDelegatedAmount > maxCapacity) {
            revert ExceedsValidatorCapacity(validatorId, newDelegatedAmount, maxCapacity, stakeAmount);
        }

        // Check if exceeding validator percentage limit
        if ($.totalStaked > 0 && $.maxValidatorPercentage > 0) {
            uint256 validatorPercentage = (newDelegatedAmount * 10_000) / $.totalStaked;
            if (validatorPercentage > $.maxValidatorPercentage) {
                revert ValidatorPercentageExceeded();
            }
        }

        // Add user to the list of validators they have staked with
        PlumeValidatorLogic.addStakerToValidator($, msg.sender, validatorId);

        // --- Initialize Reward State for New Stake with Validator ---
        if (isNewStakeForValidator) {
            address[] memory rewardTokens = $.rewardTokens; // Get all system reward tokens
            for (uint256 i = 0; i < rewardTokens.length; i++) {
                address token = rewardTokens[i];
                if ($.isRewardToken[token]) {
                    // Ensure it's still an active reward token
                    // 1. Update the validator's cumulative reward per token to current block.timestamp
                    //    This ensures that the validator's state is current before we use its cumulative values.
                    PlumeRewardLogic.updateRewardPerTokenForValidator($, token, validatorId);

                    // 2. Set the new staker's "paid" marker to the current cumulative value.
                    //    This means they start with a "debt" of all rewards accrued by the validator up to this point.
                    $.userValidatorRewardPerTokenPaid[msg.sender][validatorId][token] =
                        $.validatorRewardPerTokenCumulative[validatorId][token];
                    $.userValidatorRewardPerTokenPaidTimestamp[msg.sender][validatorId][token] = block.timestamp;

                    // 3. Initialize any stored pending rewards for this specific validator/token to zero.
                    $.userRewards[msg.sender][validatorId][token] = 0;

                    // 4. Set user's last processed checkpoint index for this validator/token.
                    if ($.validatorRewardRateCheckpoints[validatorId][token].length > 0) {
                        $.userLastCheckpointIndex[msg.sender][validatorId][token] =
                            $.validatorRewardRateCheckpoints[validatorId][token].length - 1;
                    } else {
                        // If no validator-specific checkpoints, they start from the beginning (index 0 or implicit
                        // global)
                        $.userLastCheckpointIndex[msg.sender][validatorId][token] = 0;
                    }
                }
            }
        }

        // Emit stake event with details
        emit Staked(
            msg.sender,
            validatorId,
            stakeAmount,
            0, // fromCooled
            0, // fromParked
            stakeAmount
        );

        return stakeAmount;
    }

    /**
     * @notice Restake PLUME that is currently in cooldown or parked for a specific validator.
     * @param validatorId ID of the validator to restake to.
     * @param amount Amount of PLUME to restake.
     */
    function restake(uint16 validatorId, uint256 amount) external nonReentrant {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        address user = msg.sender;

        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }
        _checkValidatorSlashedAndRevert(validatorId);
        if (!$.validators[validatorId].active) {
            revert ValidatorInactive(validatorId);
        }
        if (amount == 0) {
            revert InvalidAmount(0);
        }
        if (amount < $.minStakeAmount) {
            revert StakeAmountTooSmall(amount, $.minStakeAmount);
        }

        PlumeRewardLogic.updateRewardsForValidator($, user, validatorId);

        PlumeStakingStorage.CooldownEntry storage cooldownEntry = $.userValidatorCooldowns[user][validatorId];
        PlumeStakingStorage.StakeInfo storage userGlobalStakeInfo = $.stakeInfo[user];
        PlumeStakingStorage.StakeInfo storage userValidatorStake = $.userValidatorStakes[user][validatorId];

        if (cooldownEntry.amount < amount) {
            revert InsufficientCooldownBalance(cooldownEntry.amount, amount);
        }

        // --- Funds sourced from userValidatorCooldowns[user][validatorId] ---
        cooldownEntry.amount -= amount;

        // Update user's global sum of cooled funds
        userGlobalStakeInfo.cooled -= amount;
        // Update validator's total cooling for this specific validator
        $.validatorTotalCooling[validatorId] -= amount;
        // Update system's total cooling
        $.totalCooling -= amount;

        if (cooldownEntry.amount == 0) {
            delete $.userValidatorCooldowns[user][validatorId];
        }

        // --- Add to staked ---
        userValidatorStake.staked += amount;
        userGlobalStakeInfo.staked += amount;
        $.validators[validatorId].delegatedAmount += amount;
        $.validatorTotalStaked[validatorId] += amount;
        $.totalStaked += amount;

        // Ensure staker is properly listed for the validator
        PlumeValidatorLogic.addStakerToValidator($, user, validatorId);

        // Emit Staked event: fromCooled = amount, fromParked = 0, pendingRewards = 0 (for this direct restake)
        emit Staked(user, validatorId, amount, amount, 0, 0);
    }

    /**
     * @notice Unstake PLUME from a specific validator (full amount)
     * @param validatorId ID of the validator to unstake from
     * @return amount Amount of PLUME unstaked
     */
    function unstake(
        uint16 validatorId
    ) external returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        PlumeStakingStorage.StakeInfo storage info = $.userValidatorStakes[msg.sender][validatorId];

        if (info.staked > 0) {
            // Call internal _unstake
            return _unstake(validatorId, info.staked);
        }
        revert NoActiveStake();
    }

    /**
     * @notice Unstake a specific amount of PLUME from a specific validator
     * @param validatorId ID of the validator to unstake from
     * @param amount Amount of PLUME to unstake
     * @return amountUnstaked The amount actually unstaked
     */
    function unstake(uint16 validatorId, uint256 amount) external returns (uint256 amountUnstaked) {
        if (amount == 0) {
            revert InvalidAmount(0);
        }
        return _unstake(validatorId, amount);
    }

    /**
     * @notice Internal logic for unstaking, handles moving stake to cooling or parked.
     * @param validatorId ID of the validator to unstake from.
     * @param amount The amount of PLUME to unstake. If 0, unstakes all.
     * @return amountToUnstake The actual amount that was unstaked.
     */
    function _unstake(uint16 validatorId, uint256 amount) internal returns (uint256 amountToUnstake) {
        PlumeStakingStorage.Layout storage $s = PlumeStakingStorage.layout();

        if (!$s.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }
        _checkValidatorSlashedAndRevert(validatorId);
        if (amount == 0) {
            revert InvalidAmount(amount);
        }
        if ($s.userValidatorStakes[msg.sender][validatorId].staked < amount) {
            revert InsufficientFunds($s.userValidatorStakes[msg.sender][validatorId].staked, amount);
        }

        PlumeRewardLogic.updateRewardsForValidator($s, msg.sender, validatorId);

        // Update user's active stake and totals
        $s.userValidatorStakes[msg.sender][validatorId].staked -= amount;
        $s.stakeInfo[msg.sender].staked -= amount;
        $s.validators[validatorId].delegatedAmount -= amount;
        $s.validatorTotalStaked[validatorId] -= amount; // Ensure this is decremented
        $s.totalStaked -= amount;

        PlumeStakingStorage.CooldownEntry storage cooldownEntrySlot = $s.userValidatorCooldowns[msg.sender][validatorId];
        uint256 currentCooledAmountInSlot = cooldownEntrySlot.amount;
        uint256 currentCooldownEndTimeInSlot = cooldownEntrySlot.cooldownEndTime;

        uint256 finalNewCooledAmountForSlot;
        uint256 newCooldownEndTimestamp = block.timestamp + $s.cooldownInterval;

        if (currentCooledAmountInSlot > 0 && block.timestamp >= currentCooldownEndTimeInSlot) {
            // Previous cooldown for this slot has matured.
            // Move this matured amount to parked directly.
            $s.stakeInfo[msg.sender].parked += currentCooledAmountInSlot;
            $s.totalWithdrawable += currentCooledAmountInSlot;

            // It's no longer cooling, so remove from cooling totals.
            $s.stakeInfo[msg.sender].cooled -= currentCooledAmountInSlot;
            $s.totalCooling -= currentCooledAmountInSlot;
            $s.validatorTotalCooling[validatorId] -= currentCooledAmountInSlot;

            // Now, the new 'amount' starts cooling.
            $s.stakeInfo[msg.sender].cooled += amount;
            $s.totalCooling += amount;
            $s.validatorTotalCooling[validatorId] += amount;
            finalNewCooledAmountForSlot = amount; // The slot now cools only the new amount.
        } else {
            // No prior cooldown in this slot was matured (either no prior cooldown, or it's still active).
            // Add the newly unstaked 'amountToUnstake' to whatever is already cooling in this slot.

            // Adjust total cooling and validator-specific total cooling:
            $s.totalCooling += amount;
            $s.validatorTotalCooling[validatorId] += amount;
            $s.stakeInfo[msg.sender].cooled += amount; // Update user's global cooled amount

            finalNewCooledAmountForSlot = currentCooledAmountInSlot + amount;
        }

        cooldownEntrySlot.amount = finalNewCooledAmountForSlot;
        cooldownEntrySlot.cooldownEndTime = newCooldownEndTimestamp;

        // If user's active stake for this validator is now zero,
        // PlumeValidatorLogic.removeStakerFromValidator will be called.
        // Its internal logic (checking both active stake and current cooldown amount for this validator)
        // will determine if the staker is fully disassociated from the validator.
        if ($s.userValidatorStakes[msg.sender][validatorId].staked == 0) {
            PlumeValidatorLogic.removeStakerFromValidator($s, msg.sender, validatorId);
        }

        emit CooldownStarted(msg.sender, validatorId, amount, newCooldownEndTimestamp);

        return amount;
    }

    /**
     * @notice Withdraw PLUME that has completed the cooldown period.
     */
    function withdraw() external {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        address user = msg.sender;
        PlumeStakingStorage.StakeInfo storage userGlobalStakeInfo = $.stakeInfo[user];

        uint256 amountReadyToPark = 0;
        uint16[] storage userStakedValidators = $.userValidators[user];

        // Iterate through validators the user might have cooling funds with
        for (uint256 i = 0; i < userStakedValidators.length; i++) {
            uint16 validatorId_iterator = userStakedValidators[i];

            if ($.validators[validatorId_iterator].slashed) {
                continue; // Skip slashed validators
            }

            PlumeStakingStorage.CooldownEntry storage cooldownEntry =
                $.userValidatorCooldowns[user][validatorId_iterator];

            if (cooldownEntry.amount > 0 && block.timestamp >= cooldownEntry.cooldownEndTime) {
                uint256 amountInThisCooldown = cooldownEntry.amount;
                amountReadyToPark += amountInThisCooldown;

                // Decrement from user's global sum of cooled funds
                if (userGlobalStakeInfo.cooled >= amountInThisCooldown) {
                    userGlobalStakeInfo.cooled -= amountInThisCooldown;
                } else {
                    userGlobalStakeInfo.cooled = 0;
                }

                // Decrement from validator's total cooling
                if ($.validatorTotalCooling[validatorId_iterator] >= amountInThisCooldown) {
                    $.validatorTotalCooling[validatorId_iterator] -= amountInThisCooldown;
                } else {
                    $.validatorTotalCooling[validatorId_iterator] = 0; // Should not happen
                }

                // Decrement from system's total cooling
                if ($.totalCooling >= amountInThisCooldown) {
                    $.totalCooling -= amountInThisCooldown;
                } else {
                    $.totalCooling = 0; // Should not happen
                }

                delete $.userValidatorCooldowns[user][validatorId_iterator];

                // Now that the cooldown for this validator is cleared, attempt to fully remove
                // the staker's association with this validator if no active stake remains.
                // The active stake for this specific validator should be 0 if a cooldown was being processed.
                if ($.userValidatorStakes[user][validatorId_iterator].staked == 0) {
                    PlumeValidatorLogic.removeStakerFromValidator($, user, validatorId_iterator);
                }
                // --- END ADDED SECTION ---
            }
        }

        if (amountReadyToPark > 0) {
            userGlobalStakeInfo.parked += amountReadyToPark;
            $.totalWithdrawable += amountReadyToPark;
        }

        uint256 amountToWithdraw = userGlobalStakeInfo.parked;

        if (amountToWithdraw == 0) {
            revert InvalidAmount(0);
        }

        userGlobalStakeInfo.parked = 0;
        if ($.totalWithdrawable >= amountToWithdraw) {
            $.totalWithdrawable -= amountToWithdraw;
        } else {
            $.totalWithdrawable = 0; // Should not happen if totals are managed correctly
        }

        emit Withdrawn(user, amountToWithdraw);

        // Transfer PLUME to user
        (bool success,) = user.call{ value: amountToWithdraw }("");
        if (!success) {
            revert NativeTransferFailed();
        }
    }

    /**
     * @notice Stake PLUME to a specific validator on behalf of another user
     * @param validatorId ID of the validator to stake to
     * @param staker Address of the staker to stake on behalf of
     * @return Amount of PLUME staked
     */
    function stakeOnBehalf(uint16 validatorId, address staker) external payable returns (uint256) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        uint256 stakeAmount = msg.value;

        if (stakeAmount < $.minStakeAmount) {
            revert StakeAmountTooSmall(stakeAmount, $.minStakeAmount);
        }
        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }
        // Check if validator is active and not slashed
        PlumeStakingStorage.ValidatorInfo storage validator = $.validators[validatorId];
        if (!validator.active || validator.slashed) {
            revert ValidatorInactive(validatorId);
        }
        if (staker == address(0)) {
            revert ZeroRecipientAddress();
        }

        //  Check if this is a new stake for the staker with this specific validator
        bool isNewStakeForValidator = $.userValidatorStakes[staker][validatorId].staked == 0;

        // If staking on behalf of a user who is adding to an existing stake, settle their current rewards first.
        if (!isNewStakeForValidator) {
            PlumeRewardLogic.updateRewardsForValidator($, staker, validatorId);
        }

        // Update stake amount
        $.userValidatorStakes[staker][validatorId].staked += stakeAmount;
        $.stakeInfo[staker].staked += stakeAmount;
        $.validators[validatorId].delegatedAmount += stakeAmount;
        $.validatorTotalStaked[validatorId] += stakeAmount;
        $.totalStaked += stakeAmount;

        // Check if exceeding validator capacity
        uint256 newDelegatedAmount = $.validators[validatorId].delegatedAmount;
        uint256 maxCapacity = $.validators[validatorId].maxCapacity;
        if (maxCapacity > 0 && newDelegatedAmount > maxCapacity) {
            revert ExceedsValidatorCapacity(validatorId, newDelegatedAmount, maxCapacity, stakeAmount);
        }

        // Check if exceeding validator percentage limit
        if ($.totalStaked > 0 && $.maxValidatorPercentage > 0) {
            uint256 validatorPercentage = (newDelegatedAmount * 10_000) / $.totalStaked;
            if (validatorPercentage > $.maxValidatorPercentage) {
                revert ValidatorPercentageExceeded();
            }
        }

        // Add user to the list of validators they have staked with
        PlumeValidatorLogic.addStakerToValidator($, staker, validatorId);

        // Applied to the `staker` address, not msg.sender
        if (isNewStakeForValidator) {
            address[] memory rewardTokens = $.rewardTokens;
            for (uint256 i = 0; i < rewardTokens.length; i++) {
                address token = rewardTokens[i];
                if ($.isRewardToken[token]) {
                    PlumeRewardLogic.updateRewardPerTokenForValidator($, token, validatorId);

                    $.userValidatorRewardPerTokenPaid[staker][validatorId][token] =
                        $.validatorRewardPerTokenCumulative[validatorId][token];
                    $.userValidatorRewardPerTokenPaidTimestamp[staker][validatorId][token] = block.timestamp;
                    $.userRewards[staker][validatorId][token] = 0;

                    if ($.validatorRewardRateCheckpoints[validatorId][token].length > 0) {
                        $.userLastCheckpointIndex[staker][validatorId][token] =
                            $.validatorRewardRateCheckpoints[validatorId][token].length - 1;
                    } else {
                        $.userLastCheckpointIndex[staker][validatorId][token] = 0;
                    }
                }
            }
        }

        // Emit stake event with details
        emit Staked(
            staker,
            validatorId,
            stakeAmount,
            0, // fromCooled
            0, // fromParked
            stakeAmount
        );

        emit StakedOnBehalf(msg.sender, staker, validatorId, stakeAmount);

        return stakeAmount;
    }

    /**
     * @notice Restakes the user's entire *pending native PLUME rewards* (accrued across all validators)
     *         to a specific validator.
     * @param validatorId ID of the validator to stake the rewards to.
     * @return amountRestaked The total amount of pending rewards successfully restaked.
     */
    function restakeRewards(
        uint16 validatorId
    ) external nonReentrant returns (uint256 amountRestaked) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        // Verify target validator exists and is active
        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }
        PlumeStakingStorage.ValidatorInfo storage targetValidator = $.validators[validatorId];
        if (!targetValidator.active || targetValidator.slashed) {
            revert ValidatorInactive(validatorId);
        }

        // Native token is represented by PLUME_NATIVE constant
        address token = PlumeStakingStorage.PLUME_NATIVE;

        // Check if PLUME_NATIVE is actually configured as a reward token
        if (!$.isRewardToken[token]) {
            revert TokenDoesNotExist(token);
        }

        amountRestaked = 0;
        uint16[] memory userValidators = $.userValidators[msg.sender];

        for (uint256 i = 0; i < userValidators.length; i++) {
            uint16 userValidatorIdLoop = userValidators[i]; // Renamed to avoid confusion

            uint256 validatorReward = RewardsFacet(payable(address(this))).getPendingRewardForValidator(
                msg.sender, userValidatorIdLoop, token
            );

            if (validatorReward > 0) {
                amountRestaked += validatorReward;

                PlumeRewardLogic.updateRewardsForValidator($, msg.sender, userValidatorIdLoop);
                $.userRewards[msg.sender][userValidatorIdLoop][token] = 0;
                if ($.totalClaimableByToken[token] >= validatorReward) {
                    $.totalClaimableByToken[token] -= validatorReward;
                } else {
                    $.totalClaimableByToken[token] = 0;
                }
                emit RewardClaimedFromValidator(msg.sender, token, userValidatorIdLoop, validatorReward);
            }
        }

        if (amountRestaked == 0) {
            revert NoRewardsToRestake();
        }

        // Check if the total reward amount meets the minimum stake threshold
        if (amountRestaked < $.minStakeAmount) {
            revert StakeAmountTooSmall(amountRestaked, $.minStakeAmount);
        }

        // --- Update Stake State ---
        PlumeStakingStorage.StakeInfo storage info = $.stakeInfo[msg.sender]; // Global info

        // Increase staked amounts
        info.staked += amountRestaked; // User's global staked

        uint256 userValStakeBefore = $.userValidatorStakes[msg.sender][validatorId].staked;
        $.userValidatorStakes[msg.sender][validatorId].staked += amountRestaked; // User's stake FOR THIS VALIDATOR

        targetValidator.delegatedAmount += amountRestaked; // Validator's delegated amount
        $.validatorTotalStaked[validatorId] += amountRestaked; // Validator's total staked
        $.totalStaked += amountRestaked; // Global total staked

        // Add staker relationship if needed
        PlumeValidatorLogic.addStakerToValidator($, msg.sender, validatorId);

        // --- Checks (copied from stake) ---
        uint256 newDelegatedAmount = targetValidator.delegatedAmount;
        uint256 maxCapacity = targetValidator.maxCapacity;
        if (maxCapacity > 0 && newDelegatedAmount > maxCapacity) {
            revert ExceedsValidatorCapacity(validatorId, newDelegatedAmount, maxCapacity, amountRestaked);
        }
        if ($.totalStaked > 0 && $.maxValidatorPercentage > 0) {
            uint256 validatorPercentage = (newDelegatedAmount * 10_000) / $.totalStaked;
            if (validatorPercentage > $.maxValidatorPercentage) {
                revert ValidatorPercentageExceeded();
            }
        }

        // --- Events ---
        // Emit stake event - specifying that the amount came from pending rewards
        emit Staked(
            msg.sender,
            validatorId,
            amountRestaked, // Total amount added to stake
            0, // fromCooled
            0, // fromParked
            amountRestaked // Amount came from pending rewards
        );

        // Emit the specific restake event
        emit RewardsRestaked(msg.sender, validatorId, amountRestaked);

        return amountRestaked;
    }

    // --- View Functions ---

    /**
     * @notice Returns the amount of PLUME currently staked by the caller
     */
    function amountStaked() external view returns (uint256 amount) {
        return PlumeStakingStorage.layout().stakeInfo[msg.sender].staked;
    }

    /**
     * @notice Returns the amount of PLUME currently in cooling period for the caller
     */
    function amountCooling() external view returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        PlumeStakingStorage.StakeInfo storage info = $.stakeInfo[msg.sender];

        // info.cooled already represents the sum of all active cooling entries for the user
        return info.cooled;
    }

    /**
     * @notice Returns the amount of PLUME that is withdrawable for the caller
     */
    function amountWithdrawable() external view returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        PlumeStakingStorage.StakeInfo storage info = $.stakeInfo[msg.sender];
        // info.parked represents funds that have completed cooldown and are ready for withdrawal.
        // The withdraw() function moves amounts from completed cooldowns to parked.
        return info.parked;
    }

    /**
     * @notice Get staking information for a user (global stake info)
     */
    function stakeInfo(
        address user
    ) external view returns (PlumeStakingStorage.StakeInfo memory) {
        return PlumeStakingStorage.layout().stakeInfo[user];
    }

    /**
     * @notice Get the total amount of PLUME staked in the contract.
     * @return amount Total amount of PLUME staked.
     */
    function totalAmountStaked() external view returns (uint256 amount) {
        return PlumeStakingStorage.layout().totalStaked;
    }

    /**
     * @notice Get the total amount of PLUME cooling in the contract.
     * @return amount Total amount of PLUME cooling.
     */
    function totalAmountCooling() external view returns (uint256 amount) {
        return PlumeStakingStorage.layout().totalCooling;
    }

    /**
     * @notice Get the total amount of PLUME withdrawable in the contract.
     * @return amount Total amount of PLUME withdrawable.
     */
    function totalAmountWithdrawable() external view returns (uint256 amount) {
        return PlumeStakingStorage.layout().totalWithdrawable;
    }

    /**
     * @notice Get the total amount of a specific token claimable across all users.
     * @param token Address of the token to check.
     * @return amount Total amount of the token claimable.
     */
    function totalAmountClaimable(
        address token
    ) external view returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        // Check if token is a reward token using the mapping
        require($.isRewardToken[token], "Token is not a reward token");

        // Return the total claimable amount
        return $.totalClaimableByToken[token];
    }

    /**
     * @notice Get the staked amount for a specific user on a specific validator.
     * @param user The address of the user.
     * @param validatorId The ID of the validator.
     * @return The staked amount.
     */
    function getUserValidatorStake(address user, uint16 validatorId) external view returns (uint256) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        return $.userValidatorStakes[user][validatorId].staked;
    }

    struct CooldownView {
        // Define struct for the return type
        uint16 validatorId;
        uint256 amount;
        uint256 cooldownEndTime;
    }

    /**
     * @notice Get all active cooldown entries for a specific user.
     * @param user The address of the user.
     * @return An array of CooldownView structs.
     */
    function getUserCooldowns(
        address user
    ) external view returns (CooldownView[] memory) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        uint16[] storage userAssociatedValidators = $.userValidators[user]; // This list might contain slashed validator
            // IDs

        uint256 activeCooldownCount = 0;
        // First pass: count active, non-slashed cooldowns
        for (uint256 i = 0; i < userAssociatedValidators.length; i++) {
            uint16 validatorId_iterator = userAssociatedValidators[i];
            // <<< ADDED SLASH CHECK and validatorExists check >>>
            if (
                $.validatorExists[validatorId_iterator] && !$.validators[validatorId_iterator].slashed
                    && $.userValidatorCooldowns[user][validatorId_iterator].amount > 0
            ) {
                activeCooldownCount++;
            }
        }

        CooldownView[] memory cooldowns = new CooldownView[](activeCooldownCount);
        uint256 currentIndex = 0;
        // Second pass: populate the array
        for (uint256 i = 0; i < userAssociatedValidators.length; i++) {
            uint16 validatorId_iterator = userAssociatedValidators[i];
            // <<< ADDED SLASH CHECK and validatorExists check >>>
            if ($.validatorExists[validatorId_iterator] && !$.validators[validatorId_iterator].slashed) {
                PlumeStakingStorage.CooldownEntry storage entry = $.userValidatorCooldowns[user][validatorId_iterator];
                if (entry.amount > 0) {
                    cooldowns[currentIndex] = CooldownView({
                        validatorId: validatorId_iterator,
                        amount: entry.amount,
                        cooldownEndTime: entry.cooldownEndTime
                    });
                    currentIndex++;
                }
            }
        }
        return cooldowns;
    }

}
