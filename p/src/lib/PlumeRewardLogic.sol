// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { RewardRateCheckpointCreated } from "./PlumeEvents.sol";
import { PlumeStakingStorage } from "./PlumeStakingStorage.sol";

/**
 * @title PlumeRewardLogic
 * @notice Internal library containing shared logic for reward calculation and updates.
 */
library PlumeRewardLogic {

    using PlumeStakingStorage for PlumeStakingStorage.Layout;

    uint256 internal constant REWARD_PRECISION = 1e18;

    /**
     * @notice Updates rewards for a specific user on a specific validator by iterating through all reward tokens.
     * @dev Calculates pending rewards since the last update and stores them.
     * @param $ The PlumeStaking storage layout.
     * @param user The address of the user whose rewards are being updated.
     * @param validatorId The ID of the validator.
     */
    function updateRewardsForValidator(
        PlumeStakingStorage.Layout storage $,
        address user,
        uint16 validatorId
    ) internal {
        address[] memory rewardTokens = $.rewardTokens;
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            updateRewardPerTokenForValidator($, token, validatorId);
            PlumeStakingStorage.ValidatorInfo storage validator = $.validators[validatorId];
            uint256 validatorCommission = validator.commission;
            uint256 userStakedAmount = $.userValidatorStakes[user][validatorId].staked;

            if (userStakedAmount == 0) {
                continue;
            }

            if ($.userValidatorStakeStartTime[user][validatorId] == 0) {
                $.userValidatorStakeStartTime[user][validatorId] = block.timestamp;
            }

            (uint256 userRewardDelta, uint256 commissionDelta) =
                calculateRewardsWithCheckpoints($, user, token, validatorId, userStakedAmount, validatorCommission);

            if (commissionDelta > 0) {
                $.validatorAccruedCommission[validatorId][token] += commissionDelta;
            }
            if (userRewardDelta > 0) {
                $.userRewards[user][validatorId][token] += userRewardDelta;
                $.totalClaimableByToken[token] += userRewardDelta;
            }

            $.userValidatorRewardPerTokenPaid[user][validatorId][token] =
                $.validatorRewardPerTokenCumulative[validatorId][token];
            $.userValidatorRewardPerTokenPaidTimestamp[user][validatorId][token] = block.timestamp;

            if ($.validatorRewardRateCheckpoints[validatorId][token].length > 0) {
                $.userLastCheckpointIndex[user][validatorId][token] =
                    $.validatorRewardRateCheckpoints[validatorId][token].length - 1;
            }
        }
    }

    /**
     * @notice Updates the cumulative reward per token for a specific token and validator.
     * @dev Calculates reward accrued since the last update based on time delta and rate.
     * @param $ The PlumeStaking storage layout.
     * @param token The reward token address.
     * @param validatorId The ID of the validator.
     */
    function updateRewardPerTokenForValidator(
        PlumeStakingStorage.Layout storage $,
        address token,
        uint16 validatorId
    ) internal {
        uint256 totalStaked = $.validatorTotalStaked[validatorId];
        if (totalStaked > 0) {
            uint256 lastUpdate = $.validatorLastUpdateTimes[validatorId][token];
            if (block.timestamp > lastUpdate) {
                uint256 timeDelta = block.timestamp - lastUpdate;
                uint256 effectiveRate = $.rewardRates[token];
                if (effectiveRate > 0) {
                    uint256 reward = timeDelta * effectiveRate;
                    reward = (reward * REWARD_PRECISION) / totalStaked;
                    $.validatorRewardPerTokenCumulative[validatorId][token] += reward;
                }
            }
        }
        $.validatorLastUpdateTimes[validatorId][token] = block.timestamp;
    }

    /**
     * @notice Calculates the reward delta for a user based on checkpoints and commission.
     * @dev This is a view function, primarily calculates the difference since the last paid update.
     * @param $ The PlumeStaking storage layout.
     * @param user The user address.
     * @param token The reward token address.
     * @param validatorId The validator ID.
     * @param userStakedAmount The user's current staked amount with this validator.
     * @param validatorCommission The validator's commission rate.
     * @return userRewardDelta The calculated reward amount for the user (after commission).
     * @return commissionAmountDelta The calculated commission amount for the validator.
     */
    function calculateRewardsWithCheckpoints(
        PlumeStakingStorage.Layout storage $,
        address user,
        address token,
        uint16 validatorId,
        uint256 userStakedAmount,
        uint256 validatorCommission
    ) internal view returns (uint256 userRewardDelta, uint256 commissionAmountDelta) {
        if (userStakedAmount == 0) {
            return (0, 0);
        }

        uint256 currentCumulativeIndex = $.validatorRewardPerTokenCumulative[validatorId][token];
        uint256 lastUpdateTime = $.validatorLastUpdateTimes[validatorId][token];
        if (block.timestamp > lastUpdateTime && $.validatorTotalStaked[validatorId] > 0) {
            uint256 timeDelta = block.timestamp - lastUpdateTime;
            uint256 effectiveRate = $.rewardRates[token];
            if (effectiveRate > 0) {
                currentCumulativeIndex +=
                    (timeDelta * effectiveRate * REWARD_PRECISION) / $.validatorTotalStaked[validatorId];
            }
        }

        uint256 lastPaidCumulativeIndex = $.userValidatorRewardPerTokenPaid[user][validatorId][token];

        if (currentCumulativeIndex <= lastPaidCumulativeIndex) {
            return (0, 0);
        }
        uint256 rewardPerTokenDelta = currentCumulativeIndex - lastPaidCumulativeIndex;

        uint256 totalRewardDelta = (userStakedAmount * rewardPerTokenDelta) / REWARD_PRECISION;
        commissionAmountDelta = (totalRewardDelta * validatorCommission) / REWARD_PRECISION;
        userRewardDelta = totalRewardDelta - commissionAmountDelta;

        return (userRewardDelta, commissionAmountDelta);
    }

    /**
     * @notice Creates a new reward rate checkpoint for a specific validator and token.
     * @param $ The PlumeStaking storage layout.
     * @param token The reward token address.
     * @param validatorId The validator ID.
     * @param rate The new reward rate.
     */
    function createRewardRateCheckpoint(
        PlumeStakingStorage.Layout storage $,
        address token,
        uint16 validatorId,
        uint256 rate
    ) internal {
        updateRewardPerTokenForValidator($, token, validatorId);

        uint256 currentCumulativeIndex = $.validatorRewardPerTokenCumulative[validatorId][token];
        PlumeStakingStorage.RateCheckpoint memory checkpoint = PlumeStakingStorage.RateCheckpoint({
            timestamp: block.timestamp,
            rate: rate,
            cumulativeIndex: currentCumulativeIndex
        });

        $.validatorRewardRateCheckpoints[validatorId][token].push(checkpoint);
        uint256 checkpointIndex = $.validatorRewardRateCheckpoints[validatorId][token].length - 1;

        emit RewardRateCheckpointCreated(token, rate, block.timestamp, checkpointIndex, currentCumulativeIndex);
    }

}
