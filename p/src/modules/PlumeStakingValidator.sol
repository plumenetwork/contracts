// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {
    CommissionTooHigh,
    InvalidAmount,
    NativeTransferFailed,
    NoActiveStake,
    NotValidatorAdmin,
    TokenDoesNotExist,
    TooManyStakers,
    ValidatorAlreadyExists,
    ValidatorCapacityExceeded,
    ValidatorDoesNotExist,
    ValidatorInactive,
    ValidatorPercentageExceeded,
    ZeroAddress
} from "../lib/PlumeErrors.sol";
import {
    EmergencyFundsTransferred,
    MaxValidatorCommissionUpdated,
    MaxValidatorPercentageUpdated,
    RewardClaimedFromValidator,
    UnstakedFromValidator,
    ValidatorActivated,
    ValidatorAdded,
    ValidatorCapacityUpdated,
    ValidatorCommissionClaimed,
    ValidatorDeactivated,
    ValidatorEmergencyTransfer,
    ValidatorRemoved,
    ValidatorStakersRewardsUpdated,
    ValidatorUpdated
} from "../lib/PlumeEvents.sol";
import { PlumeStakingStorage } from "../lib/PlumeStakingStorage.sol";
import { PlumeStakingBase } from "./PlumeStakingBase.sol";

/**
 * @title PlumeStakingValidator
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Extension for validator-specific functionality
 */
contract PlumeStakingValidator is PlumeStakingBase {

    using SafeERC20 for IERC20;

    /**
     * @notice Claim validator commission rewards
     * @param validatorId ID of the validator
     * @param token Address of the reward token to claim
     * @return amount Amount of commission claimed
     */
    function claimValidatorCommission(
        uint16 validatorId,
        address token
    ) external nonReentrant returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }

        PlumeStakingStorage.ValidatorInfo storage validator = $.validators[validatorId];

        // Only validator admin can claim commission
        if (msg.sender != validator.l2AdminAddress) {
            revert NotValidatorAdmin(msg.sender);
        }

        // For safety, check if too many stakers
        address[] memory stakers = $.validatorStakers[validatorId];
        if (stakers.length > 100) {
            revert TooManyStakers();
        }

        // Update all rewards to ensure commission is current
        _updateRewardsForAllValidatorStakers(validatorId);

        amount = $.validatorAccruedCommission[validatorId][token];
        if (amount > 0) {
            $.validatorAccruedCommission[validatorId][token] = 0;

            // Transfer to validator's withdraw address
            if (token != PLUME) {
                IERC20(token).safeTransfer(validator.l2WithdrawAddress, amount);
            } else {
                // Check if native transfer was successful
                (bool success,) = payable(validator.l2WithdrawAddress).call{ value: amount }("");
                if (!success) {
                    revert NativeTransferFailed();
                }
            }

            emit ValidatorCommissionClaimed(validatorId, token, amount);
        }

        return amount;
    }

    /**
     * @notice Update rewards for a user on a specific validator
     * @param user Address of the user
     * @param validatorId ID of the validator
     */
    function _updateRewardsForValidator(address user, uint16 validatorId) internal virtual override(PlumeStakingBase) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        address[] memory rewardTokens = $.rewardTokens;

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];

            // Update reward per token for this validator
            _updateRewardPerTokenForValidator(token, validatorId);

            if (user != address(0)) {
                // Get validator commission rate
                PlumeStakingStorage.ValidatorInfo storage validator = $.validators[validatorId];
                uint256 validatorCommission = validator.commission;

                // Get user's stake info
                uint256 userStakedAmount = $.userValidatorStakes[user][validatorId].staked;

                // If this is the first time the user is staking with this validator,
                // set the stake start time
                if (userStakedAmount > 0 && $.userValidatorStakeStartTime[user][validatorId] == 0) {
                    $.userValidatorStakeStartTime[user][validatorId] = block.timestamp;
                }

                // Calculate rewards using the checkpoint system
                (uint256 userRewardAfterCommission, uint256 commissionAmount) =
                    _calculateRewardsWithCheckpoints(user, token, validatorId, userStakedAmount, validatorCommission);

                // Add commission to validator's accrued commission
                if (commissionAmount > 0) {
                    $.validatorAccruedCommission[validatorId][token] += commissionAmount;
                }

                // Add new rewards to user's existing rewards
                $.userRewards[user][validatorId][token] += userRewardAfterCommission;

                // Update user's last checkpoint index
                if ($.validatorRewardRateCheckpoints[validatorId][token].length > 0) {
                    $.userLastCheckpointIndex[user][validatorId][token] =
                        $.validatorRewardRateCheckpoints[validatorId][token].length - 1;
                }

                // Update user's reward per token paid to the current value
                $.userValidatorRewardPerTokenPaid[user][validatorId][token] =
                    $.validatorRewardPerTokenCumulative[validatorId][token];

                // Update the timestamp when the user's rewards were last updated for this validator and token
                $.userValidatorRewardPerTokenPaidTimestamp[user][validatorId][token] = block.timestamp;
            }
        }
    }

    /**
     * @notice Calculate rewards using checkpoints
     * @param user Address of the user
     * @param token Address of the token
     * @param validatorId ID of the validator
     * @param userStakedAmount Amount staked by user for this validator
     * @param validatorCommission Commission rate for this validator
     * @return userReward Reward amount for user after commission
     * @return commissionAmount Commission amount for validator
     */
    function _calculateRewardsWithCheckpoints(
        address user,
        address token,
        uint16 validatorId,
        uint256 userStakedAmount,
        uint256 validatorCommission
    ) internal view returns (uint256 userReward, uint256 commissionAmount) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        // If user has no stake, return 0
        if (userStakedAmount == 0) {
            return (0, 0);
        }

        // Get checkpoints for this validator and token
        PlumeStakingStorage.RateCheckpoint[] storage checkpoints = $.validatorRewardRateCheckpoints[validatorId][token];

        // If no checkpoints, use the traditional method
        if (checkpoints.length == 0) {
            // Get previous reward data
            uint256 oldRewardPerToken = $.userValidatorRewardPerTokenPaid[user][validatorId][token];
            uint256 currentRewardPerToken = $.validatorRewardPerTokenCumulative[validatorId][token];

            // Calculate reward with improved precision
            uint256 rewardDelta = currentRewardPerToken - oldRewardPerToken;

            // Calculate user's portion with commission deducted in a single operation
            userReward = (userStakedAmount * rewardDelta * (REWARD_PRECISION - validatorCommission))
                / (REWARD_PRECISION * REWARD_PRECISION);

            // Calculate commission amount
            commissionAmount =
                (userStakedAmount * rewardDelta * validatorCommission) / (REWARD_PRECISION * REWARD_PRECISION);

            return (userReward, commissionAmount);
        }

        // Calculate start time (when user started staking or last claimed)
        uint256 startTime = $.userValidatorStakeStartTime[user][validatorId];
        if (startTime == 0) {
            // Fall back to reward per token paid timestamp if stake start time isn't set
            startTime = $.userValidatorRewardPerTokenPaidTimestamp[user][validatorId][token];

            // If that's also not set, use the last update timestamp from the validator
            if (startTime == 0) {
                startTime = $.validatorLastUpdateTimes[validatorId][token];
            }
        }

        // Find the first applicable checkpoint
        uint256 startIndex = 0;
        while (startIndex < checkpoints.length && checkpoints[startIndex].timestamp < startTime) {
            startIndex++;
        }

        if (startIndex > 0 && startIndex < checkpoints.length) {
            // Adjust startIndex to include the checkpoint before the start time
            // to properly calculate from startTime to the next checkpoint
            startIndex--;
        }

        userReward = 0;
        commissionAmount = 0;
        uint256 lastTime = startTime;

        // Process all relevant checkpoints
        for (uint256 i = startIndex; i < checkpoints.length; i++) {
            PlumeStakingStorage.RateCheckpoint storage checkpoint = checkpoints[i];

            // Get the rate to use for this period
            uint256 rate = checkpoint.rate;

            // Handle period from lastTime to checkpoint.timestamp (if applicable)
            if (lastTime < checkpoint.timestamp) {
                // Check if this isn't the first checkpoint and we need to use the previous rate
                if (i > 0 && lastTime < checkpoint.timestamp) {
                    rate = checkpoints[i - 1].rate;
                    uint256 duration = checkpoint.timestamp - lastTime;

                    if (duration > 0 && rate > 0 && $.validatorTotalStaked[validatorId] > 0) {
                        uint256 periodReward =
                            (duration * rate * userStakedAmount) / $.validatorTotalStaked[validatorId];
                        uint256 userPeriodReward =
                            (periodReward * (REWARD_PRECISION - validatorCommission)) / REWARD_PRECISION;
                        uint256 periodCommission = (periodReward * validatorCommission) / REWARD_PRECISION;

                        userReward += userPeriodReward;
                        commissionAmount += periodCommission;
                    }
                }

                lastTime = checkpoint.timestamp;
            }

            // Handle period from checkpoint.timestamp to next checkpoint or now
            uint256 endTime = i + 1 < checkpoints.length ? checkpoints[i + 1].timestamp : block.timestamp;

            if (lastTime < endTime) {
                uint256 duration = endTime - lastTime;

                if (duration > 0 && rate > 0 && $.validatorTotalStaked[validatorId] > 0) {
                    uint256 periodReward = (duration * rate * userStakedAmount) / $.validatorTotalStaked[validatorId];
                    uint256 userPeriodReward =
                        (periodReward * (REWARD_PRECISION - validatorCommission)) / REWARD_PRECISION;
                    uint256 periodCommission = (periodReward * validatorCommission) / REWARD_PRECISION;

                    userReward += userPeriodReward;
                    commissionAmount += periodCommission;
                }

                lastTime = endTime;
            }
        }

        // Handle any remaining time using the most recent rate
        if (lastTime < block.timestamp && checkpoints.length > 0) {
            uint256 duration = block.timestamp - lastTime;
            uint256 rate = checkpoints[checkpoints.length - 1].rate;

            if (duration > 0 && rate > 0 && $.validatorTotalStaked[validatorId] > 0) {
                uint256 periodReward = (duration * rate * userStakedAmount) / $.validatorTotalStaked[validatorId];
                uint256 userPeriodReward = (periodReward * (REWARD_PRECISION - validatorCommission)) / REWARD_PRECISION;
                uint256 periodCommission = (periodReward * validatorCommission) / REWARD_PRECISION;

                userReward += userPeriodReward;
                commissionAmount += periodCommission;
            }
        }

        return (userReward, commissionAmount);
    }

    /**
     * @notice Update the reward per token value for a specific validator
     * @param token The address of the reward token
     * @param validatorId The ID of the validator
     */
    function _updateRewardPerTokenForValidator(
        address token,
        uint16 validatorId
    ) internal virtual override(PlumeStakingBase) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        if ($.validatorTotalStaked[validatorId] > 0) {
            uint256 timeDelta = block.timestamp - $.validatorLastUpdateTimes[validatorId][token];
            if (timeDelta > 0 && $.rewardRates[token] > 0) {
                // Calculate reward with proper precision handling
                uint256 reward = timeDelta * $.rewardRates[token];
                reward = (reward * REWARD_PRECISION) / $.validatorTotalStaked[validatorId];
                $.validatorRewardPerTokenCumulative[validatorId][token] += reward;
            }
        }

        $.validatorLastUpdateTimes[validatorId][token] = block.timestamp;
    }

    /**
     * @notice Add a staker to a validator's staker list
     * @param staker Address of the staker
     * @param validatorId ID of the validator
     */
    function _addStakerToValidator(address staker, uint16 validatorId) internal virtual override(PlumeStakingBase) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        // Add validator to user's validator list if not already there
        if (!$.userHasStakedWithValidator[staker][validatorId]) {
            $.userValidators[staker].push(validatorId);
            $.userHasStakedWithValidator[staker][validatorId] = true;
        }

        // Add user to validator's staker list if not already there
        if (!$.isStakerForValidator[validatorId][staker]) {
            $.validatorStakers[validatorId].push(staker);
            $.isStakerForValidator[validatorId][staker] = true;
        }

        // Also add to global stakers list if not already there
        _addStakerIfNew(staker);
    }

    /**
     * @notice Update rewards for all stakers of a validator
     * @param validatorId ID of the validator
     */
    function _updateRewardsForAllValidatorStakers(
        uint16 validatorId
    ) internal virtual override(PlumeStakingBase) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        address[] memory stakers = $.validatorStakers[validatorId];

        // For safety, revert if attempting to update a very large number of stakers at once
        if (stakers.length > 100) {
            revert TooManyStakers();
        }

        for (uint256 i = 0; i < stakers.length; i++) {
            _updateRewardsForValidator(stakers[i], validatorId);
        }
    }

    /**
     * @notice Get the list of validators a user has staked with
     * @param user Address of the user to check
     * @return validatorIds Array of validator IDs the user has staked with
     */
    function getUserValidators(
        address user
    ) external view virtual override returns (uint16[] memory validatorIds) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        return $.userValidators[user];
    }

    /**
     * @notice Add a new validator
     * @param validatorId Fixed UUID for the validator
     * @param commission Commission rate (as fraction of REWARD_PRECISION)
     * @param l2AdminAddress Admin address for the validator
     * @param l2WithdrawAddress Withdrawal address for validator rewards
     * @param l1ValidatorAddress Address of validator on L1 (informational)
     * @param l1AccountAddress Address of account on L1 (informational)
     */
    function addValidator(
        uint16 validatorId,
        uint256 commission,
        address l2AdminAddress,
        address l2WithdrawAddress,
        string calldata l1ValidatorAddress,
        string calldata l1AccountAddress
    ) external onlyRole(ADMIN_ROLE) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        if ($.validatorExists[validatorId]) {
            revert ValidatorAlreadyExists(validatorId);
        }

        if (l2AdminAddress == address(0)) {
            revert ZeroAddress("l2AdminAddress");
        }

        if (l2WithdrawAddress == address(0)) {
            revert ZeroAddress("l2WithdrawAddress");
        }

        if (commission > REWARD_PRECISION) {
            revert CommissionTooHigh();
        }

        // Create new validator
        PlumeStakingStorage.ValidatorInfo storage validator = $.validators[validatorId];
        validator.validatorId = validatorId;
        validator.commission = commission;
        validator.delegatedAmount = 0;
        validator.l2AdminAddress = l2AdminAddress;
        validator.l2WithdrawAddress = l2WithdrawAddress;
        validator.l1ValidatorAddress = l1ValidatorAddress;
        validator.l1AccountAddress = l1AccountAddress;
        validator.active = true;

        // Add to validator registry
        $.validatorIds.push(validatorId);
        $.validatorExists[validatorId] = true;

        // Initialize epoch data if using epochs
        if ($.usingEpochs) {
            $.epochValidatorAmounts[$.currentEpochNumber][validatorId] = 0;
        }

        emit ValidatorAdded(
            validatorId, commission, l2AdminAddress, l2WithdrawAddress, l1ValidatorAddress, l1AccountAddress
        );
    }

    /**
     * @notice Set the maximum capacity for a validator
     * @param validatorId ID of the validator
     * @param maxCapacity New maximum capacity
     */
    function setValidatorCapacity(uint16 validatorId, uint256 maxCapacity) external onlyRole(ADMIN_ROLE) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }

        PlumeStakingStorage.ValidatorInfo storage validator = $.validators[validatorId];
        uint256 oldCapacity = validator.maxCapacity;
        validator.maxCapacity = maxCapacity;

        emit ValidatorCapacityUpdated(validatorId, oldCapacity, maxCapacity);
    }

}
