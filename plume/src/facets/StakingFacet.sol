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

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

using PlumeRewardLogic for PlumeStakingStorage.Layout;

interface IRewardsGetter {

    function getPendingRewardForValidator(
        address user,
        uint16 validatorId,
        address token
    ) external returns (uint256 pendingReward);

}

/**
 * @title StakingFacet
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Facet containing core user staking, unstaking, and withdrawal functions.
 */
contract StakingFacet is ReentrancyGuardUpgradeable {

    using SafeERC20 for IERC20;
    using Address for address payable;

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
     * @dev Processes matured cooldowns, moving them to the user's parked balance.
     *      Then allows withdrawal of the total parked balance.
     *      If a validator a user was cooling with has been slashed, only funds whose cooldown
     *      ended *before* the validator was slashed are considered matured and moved to parked.
     */
    function withdraw() external {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        address user = msg.sender;
        PlumeStakingStorage.StakeInfo storage userGlobalStakeInfo = $.stakeInfo[user];
        // console2.log("SF.withdraw ENTRY: user %s, initial parked: %s, initial cooled: %s", user,
        // userGlobalStakeInfo.parked, userGlobalStakeInfo.cooled);

        uint256 amountMovedToParkedThisCall = 0;
        uint16[] storage userAssociatedValidators = $.userValidators[user];
        // console2.log("SF.withdraw: user %s, userStakedValidators.length: %s", user, userAssociatedValidators.length);

        // Iterate through validators the user might have cooling funds with
        // to process any matured cooldowns and move them to the user's parked balance.
        // MODIFIED: Iterate backwards to safely remove items
        for (uint256 i = userAssociatedValidators.length; i > 0; i--) {
            uint256 currentIndex = i - 1;
            uint16 validatorId_iterator = userAssociatedValidators[currentIndex];
            PlumeStakingStorage.CooldownEntry storage cooldownEntry =
                $.userValidatorCooldowns[user][validatorId_iterator];

            if (cooldownEntry.amount == 0) {
                continue; // No active cooldown with this validator for this user
            }

            bool canRecoverFromThisCooldown = false;
            if ($.validatorExists[validatorId_iterator] && $.validators[validatorId_iterator].slashed) {
                // Validator is slashed. Check if cooldown ended BEFORE the slash.
                uint256 slashTs = $.validators[validatorId_iterator].slashedAtTimestamp;
                if (cooldownEntry.cooldownEndTime < slashTs && block.timestamp >= cooldownEntry.cooldownEndTime) {
                    canRecoverFromThisCooldown = true;
                }
            } else if ($.validatorExists[validatorId_iterator] && !$.validators[validatorId_iterator].slashed) {
                // Validator is NOT slashed. Check if cooldown matured normally.
                if (block.timestamp >= cooldownEntry.cooldownEndTime) {
                    canRecoverFromThisCooldown = true;
                }
            }

            // If validator doesn't exist, cooldownEntry.amount should be 0 (or it's stale data we ignore)
            if (canRecoverFromThisCooldown) {
                uint256 amountInThisCooldown = cooldownEntry.amount;
                amountMovedToParkedThisCall += amountInThisCooldown;

                // Decrement from user's global sum of cooled funds
                if (userGlobalStakeInfo.cooled >= amountInThisCooldown) {
                    userGlobalStakeInfo.cooled -= amountInThisCooldown;
                } else {
                    userGlobalStakeInfo.cooled = 0; // Safety
                }

                // Decrement from validator's total cooling (only if not slashed, as slashValidator handles it)
                if (!$.validators[validatorId_iterator].slashed) {
                    if ($.validatorTotalCooling[validatorId_iterator] >= amountInThisCooldown) {
                        $.validatorTotalCooling[validatorId_iterator] -= amountInThisCooldown;
                    } else {
                        $.validatorTotalCooling[validatorId_iterator] = 0;
                    }
                }

                // Note: $.totalCooling is a global sum. If validator was slashed, its contribution was already removed.
                // If not slashed, we remove it here.
                if ($.totalCooling >= amountInThisCooldown) {
                    $.totalCooling -= amountInThisCooldown;
                } else {
                    $.totalCooling = 0;
                }

                delete $.userValidatorCooldowns[user][validatorId_iterator];

                if ($.userValidatorStakes[user][validatorId_iterator].staked == 0) {
                    PlumeValidatorLogic.removeStakerFromValidator($, user, validatorId_iterator);
                }
            }
        }

        if (amountMovedToParkedThisCall > 0) {
            userGlobalStakeInfo.parked += amountMovedToParkedThisCall;
            // $.totalWithdrawable is already tracking $.stakeInfo[user].parked effectively,
            // plus what withdraw() itself makes available. We add the newly parked amount here.
            // This was previously missing direct addition if funds were moved from cooled to parked within this call.
            $.totalWithdrawable += amountMovedToParkedThisCall;
        }

        uint256 amountToActuallyWithdraw = userGlobalStakeInfo.parked;
        if (amountToActuallyWithdraw == 0) {
            revert InvalidAmount(0);
        }

        userGlobalStakeInfo.parked = 0;
        if ($.totalWithdrawable >= amountToActuallyWithdraw) {
            $.totalWithdrawable -= amountToActuallyWithdraw;
        } else {
            $.totalWithdrawable = 0;
        }

        emit Withdrawn(user, amountToActuallyWithdraw);

        (bool success,) = user.call{ value: amountToActuallyWithdraw }("");
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

                    // 4. Set user's last processed checkpoint index for this validator/token.
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
     *         to a specific validator. Also processes any matured cooldowns into the user's parked balance.
     * @param validatorId ID of the validator to stake the rewards to.
     * @return amountRestaked The total amount of pending rewards successfully restaked.
     */
    function restakeRewards(
        uint16 validatorId
    ) external nonReentrant returns (uint256 amountRestaked) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        address user = msg.sender;

        // --- BEGIN: Process Matured Cooldowns (similar to withdraw() beginning) ---
        PlumeStakingStorage.StakeInfo storage userGlobalStakeInfo = $.stakeInfo[user];
        uint256 amountMovedToParkedThisCall = 0;
        uint16[] storage userAssociatedValidatorsLoop = $.userValidators[user];

        for (uint256 i = 0; i < userAssociatedValidatorsLoop.length; i++) {
            uint16 validatorId_iterator = userAssociatedValidatorsLoop[i];
            PlumeStakingStorage.CooldownEntry storage cooldownEntry =
                $.userValidatorCooldowns[user][validatorId_iterator];

            if (cooldownEntry.amount > 0 && block.timestamp >= cooldownEntry.cooldownEndTime) {
                bool canRecoverFromThisCooldown = false;
                if ($.validatorExists[validatorId_iterator] && $.validators[validatorId_iterator].slashed) {
                    uint256 slashTs = $.validators[validatorId_iterator].slashedAtTimestamp;
                    if (cooldownEntry.cooldownEndTime < slashTs) {
                        // Cooldown matured BEFORE slash
                        canRecoverFromThisCooldown = true;
                    }
                } else if ($.validatorExists[validatorId_iterator] && !$.validators[validatorId_iterator].slashed) {
                    canRecoverFromThisCooldown = true; // Not slashed, matured cooldown is recoverable
                }

                if (canRecoverFromThisCooldown) {
                    uint256 amountInThisCooldown = cooldownEntry.amount;
                    amountMovedToParkedThisCall += amountInThisCooldown;

                    if (userGlobalStakeInfo.cooled >= amountInThisCooldown) {
                        userGlobalStakeInfo.cooled -= amountInThisCooldown;
                    } else {
                        userGlobalStakeInfo.cooled = 0;
                    }
                    if (!$.validators[validatorId_iterator].slashed) {
                        if ($.validatorTotalCooling[validatorId_iterator] >= amountInThisCooldown) {
                            $.validatorTotalCooling[validatorId_iterator] -= amountInThisCooldown;
                        } else {
                            $.validatorTotalCooling[validatorId_iterator] = 0;
                        }
                    }
                    if ($.totalCooling >= amountInThisCooldown) {
                        $.totalCooling -= amountInThisCooldown;
                    } else {
                        $.totalCooling = 0;
                    }
                    delete $.userValidatorCooldowns[user][validatorId_iterator];

                    if ($.userValidatorStakes[user][validatorId_iterator].staked == 0) {
                        PlumeValidatorLogic.removeStakerFromValidator($, user, validatorId_iterator);
                    }
                }
            }
        }

        if (amountMovedToParkedThisCall > 0) {
            userGlobalStakeInfo.parked += amountMovedToParkedThisCall;
            $.totalWithdrawable += amountMovedToParkedThisCall;
        }
        // --- END: Process Matured Cooldowns ---

        // Verify target validator exists and is active (for restaking rewards)
        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }
        PlumeStakingStorage.ValidatorInfo storage targetValidator = $.validators[validatorId];
        if (!targetValidator.active || targetValidator.slashed) {
            revert ValidatorInactive(validatorId);
        }

        // Native token is PLUME_NATIVE
        address tokenToRestake = PlumeStakingStorage.PLUME_NATIVE;
        if (!$.isRewardToken[tokenToRestake]) {
            revert TokenDoesNotExist(tokenToRestake);
        }

        amountRestaked = 0;
        // The userValidators array might have been modified by removeStakerFromValidator above,
        // so re-fetch or use a copy if strict iteration order over original set was important.
        // However, for summing rewards, iterating the current set is fine.
        uint16[] memory currentUserValidators = $.userValidators[msg.sender];

        for (uint256 i = 0; i < currentUserValidators.length; i++) {
            uint16 userValidatorIdLoop = currentUserValidators[i];

            uint256 validatorReward = IRewardsGetter(address(this)).getPendingRewardForValidator(
                msg.sender, userValidatorIdLoop, tokenToRestake
            );

            if (validatorReward > 0) {
                amountRestaked += validatorReward;
                PlumeRewardLogic.updateRewardsForValidator($, msg.sender, userValidatorIdLoop);
                $.userRewards[msg.sender][userValidatorIdLoop][tokenToRestake] = 0;
                if ($.totalClaimableByToken[tokenToRestake] >= validatorReward) {
                    $.totalClaimableByToken[tokenToRestake] -= validatorReward;
                } else {
                    $.totalClaimableByToken[tokenToRestake] = 0;
                }
                emit RewardClaimedFromValidator(msg.sender, tokenToRestake, userValidatorIdLoop, validatorReward);
            }
        }

        if (amountRestaked == 0) {
            revert NoRewardsToRestake();
        }
        if (amountRestaked < $.minStakeAmount) {
            revert StakeAmountTooSmall(amountRestaked, $.minStakeAmount);
        }

        // --- Update Stake State for Restaked Rewards ---
        // userGlobalStakeInfo is already defined
        userGlobalStakeInfo.staked += amountRestaked;
        $.userValidatorStakes[user][validatorId].staked += amountRestaked;
        targetValidator.delegatedAmount += amountRestaked;
        $.validatorTotalStaked[validatorId] += amountRestaked;
        $.totalStaked += amountRestaked;

        PlumeValidatorLogic.addStakerToValidator($, user, validatorId);

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

        emit Staked(msg.sender, validatorId, amountRestaked, 0, 0, amountRestaked);
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
     * @notice Returns the amount of PLUME currently in cooling period for the caller.
     * This now dynamically calculates funds in active, non-matured cooldowns.
     */
    function amountCooling() external view returns (uint256 activelyCoolingAmount) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        address user = msg.sender;
        activelyCoolingAmount = 0;

        uint16[] storage userAssociatedValidators = $.userValidators[user];

        for (uint256 i = 0; i < userAssociatedValidators.length; i++) {
            uint16 validatorId_iterator = userAssociatedValidators[i];
            // Only consider non-slashed validators for amounts actively cooling towards withdrawal
            if ($.validatorExists[validatorId_iterator] && !$.validators[validatorId_iterator].slashed) {
                PlumeStakingStorage.CooldownEntry storage cooldownEntry =
                    $.userValidatorCooldowns[user][validatorId_iterator];

                // Only count if it has an amount AND its cooldown period has NOT YET ended
                if (cooldownEntry.amount > 0 && block.timestamp < cooldownEntry.cooldownEndTime) {
                    activelyCoolingAmount += cooldownEntry.amount;
                }
            }
        }
        return activelyCoolingAmount;
    }

    /**
     * @notice Returns the amount of PLUME that is withdrawable for the caller.
     * This includes already parked funds plus any funds in matured cooldowns.
     * For slashed validators, cooled funds are only considered withdrawable if their
     * cooldownEndTime was *before* the validator's slashedAtTimestamp.
     */
    function amountWithdrawable() external view returns (uint256 totalWithdrawableAmount) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        address user = msg.sender;

        totalWithdrawableAmount = $.stakeInfo[user].parked;

        uint16[] storage userAssociatedValidators = $.userValidators[user];

        for (uint256 i = 0; i < userAssociatedValidators.length; i++) {
            uint16 validatorId_iterator = userAssociatedValidators[i];
            PlumeStakingStorage.CooldownEntry storage cooldownEntry =
                $.userValidatorCooldowns[user][validatorId_iterator];

            if (cooldownEntry.amount > 0 && block.timestamp >= cooldownEntry.cooldownEndTime) {
                // Cooldown has matured in terms of time
                if ($.validatorExists[validatorId_iterator] && $.validators[validatorId_iterator].slashed) {
                    // Validator is slashed, check if cooldown ended BEFORE the slash time
                    if (cooldownEntry.cooldownEndTime < $.validators[validatorId_iterator].slashedAtTimestamp) {
                        totalWithdrawableAmount += cooldownEntry.amount;
                    }
                    // If cooldown ended at/after slash, it's not considered user-withdrawable here
                } else if ($.validatorExists[validatorId_iterator] && !$.validators[validatorId_iterator].slashed) {
                    // Validator is not slashed, matured cooldown is withdrawable
                    totalWithdrawableAmount += cooldownEntry.amount;
                }
                // If validator doesn't exist (shouldn't happen if userAssociatedValidators is clean), ignore.
            }
        }
        return totalWithdrawableAmount;
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
