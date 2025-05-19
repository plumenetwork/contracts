// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { RewardRateCheckpointCreated, ValidatorCommissionCheckpointCreated } from "./PlumeEvents.sol";
import { PlumeStakingStorage } from "./PlumeStakingStorage.sol";
import { PlumeValidatorLogic } from "./PlumeValidatorLogic.sol";
import { console2 } from "forge-std/console2.sol";

/**
 * @title PlumeRewardLogic
 * @notice Internal library containing shared logic for reward calculation and updates.
 */
library PlumeRewardLogic {

    using PlumeStakingStorage for PlumeStakingStorage.Layout;

    /**
     * @notice Finds the index of the checkpoint active at or just before a given timestamp.
     * @dev Uses binary search. Assumes checkpoints are sorted by timestamp.
     * @param checkpoints The array of RateCheckpoint structs.
     * @param timestamp The target timestamp.
     * @return index The index of the relevant checkpoint.
     */
    function findCheckpointIndex(
        PlumeStakingStorage.RateCheckpoint[] storage checkpoints,
        uint64 timestamp
    ) internal view returns (uint256 index) {
        uint256 len = checkpoints.length;
        if (len == 0) {
            return 0; // Or revert, depending on desired behavior for uninitialized rates
        }
        uint256 low = 0;
        uint256 high = len - 1;
        uint256 mid;
        while (low <= high) {
            mid = (low + high) / 2;
            if (checkpoints[mid].timestamp <= timestamp) {
                index = mid;
                // Check if it's the last element or the next element's timestamp is greater
                if (mid == len - 1 || checkpoints[mid + 1].timestamp > timestamp) {
                    return index;
                }
                low = mid + 1; // Search in the right half
            } else {
                // Check if it's the first element
                if (mid == 0) {
                    return 0;
                }
                high = mid - 1; // Search in the left half
            }
        }
        return 0;
    }

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
            uint256 validatorLastGlobalUpdateTimestampAtLoopStart = $.validatorLastUpdateTimes[validatorId][token]; // CAPTURE
                // HERE

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

            (uint256 userRewardDelta, uint256 commissionAmountDelta, uint256 effectiveTimeDelta) =
                calculateRewardsWithCheckpoints($, user, validatorId, token, userStakedAmount);

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
     *      Also calculates and accrues commission for the validator for this segment.
     * @param $ The PlumeStaking storage layout.
     * @param token The reward token address.
     * @param validatorId The ID of the validator.
     */
    function updateRewardPerTokenForValidator(
        PlumeStakingStorage.Layout storage $,
        address token,
        uint16 validatorId
    ) internal {
        PlumeStakingStorage.ValidatorInfo storage validator = $.validators[validatorId]; // Get validator info

        // --- BEGIN SLASH CHECK ---
        if (validator.slashed) {
            uint256 slashTs = validator.slashedAtTimestamp;
            uint256 currentLastUpdateTime = $.validatorLastUpdateTimes[validatorId][token];
            uint256 effectiveTimestampForUpdate = block.timestamp < slashTs ? block.timestamp : slashTs;

            if (currentLastUpdateTime < effectiveTimestampForUpdate) {
                uint256 totalStakedForCalc = $.validatorTotalStaked[validatorId];
                // If slashValidator has run, totalStakedForCalc will be 0, so no rewards/commission here.
                // This is intended, as slashValidator already accounts for removing validator's contribution from
                // global totals.
                // This block primarily ensures that if called *before* slashValidator fully zeroes things but *after*
                // slash flag is set,
                // accrual doesn't go past slashTs.

                if (totalStakedForCalc > 0) {
                    uint256 timeDelta = effectiveTimestampForUpdate - currentLastUpdateTime;
                    PlumeStakingStorage.RateCheckpoint memory effectiveRewardRateChk =
                        getEffectiveRewardRateAt($, token, validatorId, effectiveTimestampForUpdate);
                    uint256 effectiveRewardRate = effectiveRewardRateChk.rate;

                    if (effectiveRewardRate > 0 && timeDelta > 0) {
                        uint256 rewardPerTokenIncrease = timeDelta * effectiveRewardRate;
                        $.validatorRewardPerTokenCumulative[validatorId][token] += rewardPerTokenIncrease;

                        uint256 commissionRateForSegment =
                            getEffectiveCommissionRateAt($, validatorId, currentLastUpdateTime);
                        uint256 grossRewardForValidatorThisSegment =
                            (totalStakedForCalc * rewardPerTokenIncrease) / PlumeStakingStorage.REWARD_PRECISION;
                        uint256 commissionDeltaForValidator = (
                            grossRewardForValidatorThisSegment * commissionRateForSegment
                        ) / PlumeStakingStorage.REWARD_PRECISION;
                        if (commissionDeltaForValidator > 0) {
                            $.validatorAccruedCommission[validatorId][token] += commissionDeltaForValidator;
                        }
                    }
                }
                $.validatorLastUpdateTimes[validatorId][token] = effectiveTimestampForUpdate;
            } else if (block.timestamp > $.validatorLastUpdateTimes[validatorId][token]) {
                // If currentLastUpdateTime >= effectiveTimestampForUpdate (i.e. already at or past slash time, or
                // current processing is before slash time)
                // and block.timestamp has moved forward from last update, ensure last update time moves to
                // block.timestamp
                // to prevent re-processing if called multiple times in same block after slashTs but before time moves.
                // If not slashed, this ensures it always updates to block.timestamp if time has passed.
                $.validatorLastUpdateTimes[validatorId][token] = block.timestamp;
            }

            return;
        }
        // --- END SLASH CHECK ---

        uint256 totalStaked = $.validatorTotalStaked[validatorId];
        uint256 oldLastUpdateTime = $.validatorLastUpdateTimes[validatorId][token];

        if (block.timestamp > oldLastUpdateTime) {
            if (totalStaked > 0) {
                uint256 timeDelta = block.timestamp - oldLastUpdateTime;
                // Get the reward rate effective for the segment ending at block.timestamp
                PlumeStakingStorage.RateCheckpoint memory effectiveRewardRateChk =
                    getEffectiveRewardRateAt($, token, validatorId, block.timestamp);
                uint256 effectiveRewardRate = effectiveRewardRateChk.rate;

                if (effectiveRewardRate > 0) {
                    uint256 rewardPerTokenIncrease = timeDelta * effectiveRewardRate;
                    $.validatorRewardPerTokenCumulative[validatorId][token] += rewardPerTokenIncrease;

                    // Accrue commission for the validator for this segment
                    // The commission rate should be the one effective at the START of this segment (oldLastUpdateTime)
                    uint256 commissionRateForSegment = getEffectiveCommissionRateAt($, validatorId, oldLastUpdateTime);
                    uint256 grossRewardForValidatorThisSegment =
                        (totalStaked * rewardPerTokenIncrease) / PlumeStakingStorage.REWARD_PRECISION;
                    uint256 commissionDeltaForValidator = (
                        grossRewardForValidatorThisSegment * commissionRateForSegment
                    ) / PlumeStakingStorage.REWARD_PRECISION;

                    if (commissionDeltaForValidator > 0) {
                        uint256 previousAccrued = $.validatorAccruedCommission[validatorId][token];
                        $.validatorAccruedCommission[validatorId][token] += commissionDeltaForValidator;
                    }
                }
            }
        }
        // Update last global update time for this validator/token AFTER all calculations for the segment
        $.validatorLastUpdateTimes[validatorId][token] = block.timestamp;
    }

    /**
     * @notice Calculates the reward delta for a user, applying commission rates from checkpoints.
     * @dev This function iterates through time segments defined by reward and commission rate changes.
     * @param $ The PlumeStaking storage layout.
     * @param user The user address.
     * @param validatorId The validator ID.
     * @param token The reward token address.
     * @param userStakedAmount The user's current staked amount with this validator.
     * @return totalUserRewardDelta The calculated reward amount for the user (after commission).
     * @return totalCommissionAmountDelta The calculated commission amount for the validator.
     * @return effectiveTimeDelta The effective time delta for the calculation.
     */
    function calculateRewardsWithCheckpoints(
        PlumeStakingStorage.Layout storage $,
        address user,
        uint16 validatorId,
        address token,
        uint256 userStakedAmount
    ) internal returns (uint256 totalUserRewardDelta, uint256 totalCommissionAmountDelta, uint256 effectiveTimeDelta) {
        updateRewardPerTokenForValidator($, token, validatorId);

        uint256 lastUserPaidCumulativeRewardPerToken = $.userValidatorRewardPerTokenPaid[user][validatorId][token];
        uint256 finalCumulativeRewardPerToken = $.validatorRewardPerTokenCumulative[validatorId][token];
        uint256 lastUserRewardUpdateTime = $.userValidatorRewardPerTokenPaidTimestamp[user][validatorId][token];

        if (lastUserRewardUpdateTime == 0) {
            lastUserRewardUpdateTime = $.userValidatorStakeStartTime[user][validatorId];
            if (lastUserRewardUpdateTime == 0 && $.userValidatorStakes[user][validatorId].staked > 0) {
                lastUserRewardUpdateTime = block.timestamp;
            }
        }

        if (block.timestamp <= lastUserRewardUpdateTime) {
            return (0, 0, 0);
        }

        effectiveTimeDelta = block.timestamp - lastUserRewardUpdateTime;

        uint256[] memory distinctTimestamps =
            getDistinctTimestamps($, validatorId, token, lastUserRewardUpdateTime, block.timestamp);

        if (distinctTimestamps.length < 2) {
            return (0, 0, 0);
        }

        uint256 currentCumulativeRewardPerToken = lastUserPaidCumulativeRewardPerToken;

        for (uint256 k = 0; k < distinctTimestamps.length - 1; ++k) {
            uint256 segmentStartTime = distinctTimestamps[k];
            uint256 actualSegmentEndTime = distinctTimestamps[k + 1];

            if (actualSegmentEndTime <= segmentStartTime) {
                continue;
            }

            uint256 rptAtSegmentStart = currentCumulativeRewardPerToken;
            PlumeStakingStorage.RateCheckpoint memory rewardRateInfoAtSegmentStart =
                getEffectiveRewardRateAt($, token, validatorId, segmentStartTime);
            uint256 effectiveRewardRateForSegment = rewardRateInfoAtSegmentStart.rate;
            uint256 timeDeltaForSegment = actualSegmentEndTime - segmentStartTime;
            uint256 rewardPerTokenIncreaseForSegment = 0;

            if (effectiveRewardRateForSegment > 0 && timeDeltaForSegment > 0) {
                rewardPerTokenIncreaseForSegment = timeDeltaForSegment * effectiveRewardRateForSegment;
            }
            uint256 rptAtSegmentEnd = rptAtSegmentStart + rewardPerTokenIncreaseForSegment;

            uint256 rewardPerTokenDeltaForSegment = 0;
            if (rptAtSegmentEnd > rptAtSegmentStart) {
                rewardPerTokenDeltaForSegment = rptAtSegmentEnd - rptAtSegmentStart;
            }

            if (rewardPerTokenDeltaForSegment > 0 && userStakedAmount > 0) {
                uint256 grossRewardForSegment =
                    (userStakedAmount * rewardPerTokenDeltaForSegment) / PlumeStakingStorage.REWARD_PRECISION;
                uint256 effectiveCommissionRate = getEffectiveCommissionRateAt($, validatorId, segmentStartTime);

                uint256 commissionForThisSegment =
                    (grossRewardForSegment * effectiveCommissionRate) / PlumeStakingStorage.REWARD_PRECISION;
                console2.log("CRWC_LOOP_CALC5 [%s]: commSeg:%s", k, commissionForThisSegment);

                // Check for underflow before subtraction
                if (grossRewardForSegment < commissionForThisSegment) {
                    // This should ideally not happen with commission <= 100%
                    // If it does, it means an issue elsewhere (e.g. commissionRate > REWARD_PRECISION)
                    // For safety, can treat net reward as 0 in this case, or revert explicitly.
                    // Reverting here would give a more specific error than a generic panic 0x11.
                    // revert("Commission exceeds gross reward in segment calculation");
                }
                totalUserRewardDelta += (grossRewardForSegment - commissionForThisSegment);
                totalCommissionAmountDelta += commissionForThisSegment;
            }
            currentCumulativeRewardPerToken = rptAtSegmentEnd;
        }

        return (totalUserRewardDelta, totalCommissionAmountDelta, effectiveTimeDelta);
    }

    /**
     * @notice Helper to get a sorted list of unique timestamps relevant for a claim period.
     * Includes period start, period end, and all reward/commission checkpoints in between.
     */
    function getDistinctTimestamps(
        PlumeStakingStorage.Layout storage $,
        uint16 validatorId,
        address token,
        uint256 periodStart,
        uint256 periodEnd
    ) internal view returns (uint256[] memory) {
        // Max possible points: start, end, all reward checkpoints, all commission checkpoints
        uint256 rewardCheckpointCount = $.validatorRewardRateCheckpoints[validatorId][token].length;
        uint256 commissionCheckpointCount = $.validatorCommissionCheckpoints[validatorId].length;
        uint256[] memory tempTimestamps = new uint256[](2 + rewardCheckpointCount + commissionCheckpointCount);
        uint256 count = 0;

        tempTimestamps[count++] = periodStart;

        for (uint256 i = 0; i < rewardCheckpointCount; i++) {
            uint256 ts = $.validatorRewardRateCheckpoints[validatorId][token][i].timestamp;
            if (ts > periodStart && ts < periodEnd) {
                tempTimestamps[count++] = ts;
            }
        }
        for (uint256 i = 0; i < commissionCheckpointCount; i++) {
            uint256 ts = $.validatorCommissionCheckpoints[validatorId][i].timestamp;
            if (ts > periodStart && ts < periodEnd) {
                tempTimestamps[count++] = ts;
            }
        }

        tempTimestamps[count++] = periodEnd;

        // Sort and unique
        // For simplicity in this draft, basic bubble sort, not for production due to gas.
        // A more gas-efficient sort (e.g., Timsort if available or off-chain precomputation for known N) would be
        // needed.
        // Solidity does not have a built-in sort. For on-chain, if N is small, simple sort is okay.
        // For now, we'll assume these are processed or the number of checkpoints is manageable.
        // This part is critical for correctness and gas.
        // A heap-based approach to build the sorted unique list might be better.

        // Bubble sort for this example (NOT PRODUCTION READY FOR LARGE ARRAYS)
        for (uint256 i = 0; i < count; i++) {
            for (uint256 j = i + 1; j < count; j++) {
                if (tempTimestamps[i] > tempTimestamps[j]) {
                    (tempTimestamps[i], tempTimestamps[j]) = (tempTimestamps[j], tempTimestamps[i]);
                }
            }
        }

        if (count == 0) {
            return new uint256[](0);
        } // Should not happen if periodStart/End are added

        // Remove duplicates
        uint256[] memory distinctSortedTimestamps = new uint256[](count);
        uint256 distinctCount = 0;
        if (count > 0) {
            distinctSortedTimestamps[distinctCount++] = tempTimestamps[0];
            for (uint256 i = 1; i < count; i++) {
                if (tempTimestamps[i] != tempTimestamps[i - 1]) {
                    distinctSortedTimestamps[distinctCount++] = tempTimestamps[i];
                }
            }
        }

        uint256[] memory finalResult = new uint256[](distinctCount);
        for (uint256 i = 0; i < distinctCount; i++) {
            finalResult[i] = distinctSortedTimestamps[i];
        }
        return finalResult;
    }

    /**
     * @notice Gets the effective reward rate for a validator and token at a given timestamp.
     * Looks up the validator-specific reward rate checkpoint. If none, uses global reward rate.
     */
    function getEffectiveRewardRateAt(
        PlumeStakingStorage.Layout storage $,
        address token,
        uint16 validatorId,
        uint256 timestamp
    ) internal view returns (PlumeStakingStorage.RateCheckpoint memory effectiveCheckpoint) {
        PlumeStakingStorage.RateCheckpoint[] storage checkpoints = $.validatorRewardRateCheckpoints[validatorId][token];
        uint256 chkCount = checkpoints.length;

        if (chkCount > 0) {
            uint256 idx = findRewardRateCheckpointIndexAtOrBefore($, validatorId, token, timestamp);

            // Check if checkpoints[idx] is actually valid for this timestamp.
            if (idx < chkCount && checkpoints[idx].timestamp <= timestamp) {
                return checkpoints[idx];
            }
        }
        // Fallback: No validator-specific checkpoint found that is <= timestamp, or no checkpoints exist.
        effectiveCheckpoint.rate = $.rewardRates[token]; // Global rate
        effectiveCheckpoint.timestamp = timestamp;
        effectiveCheckpoint.cumulativeIndex = 0;
        return effectiveCheckpoint;
    }

    /**
     * @notice Gets the effective commission rate for a validator at a given timestamp.
     * Looks up the validator-specific commission rate checkpoint.
     */
    function getEffectiveCommissionRateAt(
        PlumeStakingStorage.Layout storage $,
        uint16 validatorId,
        uint256 timestamp
    ) internal view returns (uint256) {
        PlumeStakingStorage.RateCheckpoint[] storage checkpoints = $.validatorCommissionCheckpoints[validatorId];
        uint256 chkCount = checkpoints.length;

        if (chkCount > 0) {
            uint256 idx = findCommissionCheckpointIndexAtOrBefore($, validatorId, timestamp);
            if (idx < chkCount && checkpoints[idx].timestamp <= timestamp) {
                return checkpoints[idx].rate;
            }
        }
        uint256 fallbackComm = $.validators[validatorId].commission;
        return fallbackComm;
    }

    /**
     * @notice Finds the index of the reward rate checkpoint active at or just before a given timestamp for a validator.
     */
    function findRewardRateCheckpointIndexAtOrBefore(
        PlumeStakingStorage.Layout storage $,
        uint16 validatorId,
        address token,
        uint256 timestamp
    ) internal view returns (uint256) {
        PlumeStakingStorage.RateCheckpoint[] storage checkpoints = $.validatorRewardRateCheckpoints[validatorId][token];
        uint256 len = checkpoints.length;

        if (len == 0) {
            return 0;
        }

        uint256 low = 0;
        uint256 high = len - 1;
        uint256 ans = 0;
        bool foundSuitable = false;

        while (low <= high) {
            uint256 mid = low + (high - low) / 2;
            if (checkpoints[mid].timestamp <= timestamp) {
                ans = mid;
                foundSuitable = true;
                low = mid + 1;
            } else {
                // checkpoints[mid].timestamp > timestamp
                if (mid == 0) {
                    break; // All remaining (or only) elements are in the future
                }
                high = mid - 1;
            }
        }
        // If !foundSuitable, ans is 0. Caller must check checkpoints[0].timestamp against query timestamp.
        // If foundSuitable, ans is the index of the latest checkpoint <= timestamp.
        return ans;
    }

    /**
     * @notice Finds the index of the commission checkpoint active at or just before a given timestamp for a validator.
     */
    function findCommissionCheckpointIndexAtOrBefore(
        PlumeStakingStorage.Layout storage $,
        uint16 validatorId,
        uint256 timestamp
    ) internal view returns (uint256) {
        PlumeStakingStorage.RateCheckpoint[] storage checkpoints = $.validatorCommissionCheckpoints[validatorId];
        uint256 len = checkpoints.length;
        if (len == 0) {
            return 0;
        }

        uint256 low = 0;
        uint256 high = len - 1;
        uint256 ans = 0;
        bool foundSuitable = false;

        while (low <= high) {
            uint256 mid = low + (high - low) / 2;

            if (checkpoints[mid].timestamp <= timestamp) {
                ans = mid;
                foundSuitable = true; // Mark that we found at least one suitable checkpoint
                low = mid + 1;
            } else {
                // checkpoints[mid].timestamp > timestamp
                if (mid == 0) {
                    // If the first element is already too new
                    break;
                }
                high = mid - 1;
            }
        }
        // If !foundSuitable, ans is 0. The caller (getEffectiveCommissionRateAt) must handle this by checking
        // the timestamp of checkpoints[0] if it intends to use it, or fall back.
        // The current `getEffectiveCommissionRateAt` does this: `if (idx < chkCount && checkpoints[idx].timestamp <=
        // timestamp)`
        return ans;
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
        uint256 len_before = 0;
        len_before = $.validatorRewardRateCheckpoints[validatorId][token].length;

        updateRewardPerTokenForValidator($, token, validatorId);
        uint256 currentCumulativeIndex = $.validatorRewardPerTokenCumulative[validatorId][token];
        PlumeStakingStorage.RateCheckpoint memory checkpoint = PlumeStakingStorage.RateCheckpoint({
            timestamp: block.timestamp,
            rate: rate,
            cumulativeIndex: currentCumulativeIndex
        });
        $.validatorRewardRateCheckpoints[validatorId][token].push(checkpoint);
        uint256 len_after = $.validatorRewardRateCheckpoints[validatorId][token].length;

        uint256 checkpointIndex = len_after - 1;
        emit RewardRateCheckpointCreated(
            token, validatorId, rate, block.timestamp, checkpointIndex, currentCumulativeIndex
        );
    }

    /**
     * @notice Creates a new commission rate checkpoint for a specific validator.
     * @dev Analogous to createRewardRateCheckpoint but for commission.
     * @param $ The PlumeStaking storage layout.
     * @param validatorId The validator ID.
     * @param commissionRate The new commission rate.
     */
    function createCommissionRateCheckpoint(
        PlumeStakingStorage.Layout storage $,
        uint16 validatorId,
        uint256 commissionRate
    ) internal {
        // It's important that validatorLastUpdateTimes and validatorRewardPerTokenCumulative
        // are up-to-date before creating any kind of checkpoint that might rely on them
        // or before the rate itself changes.
        // However, for commission checkpoints specifically, the "settling" should happen
        // in setValidatorCommission *before* this is called with the *new* rate.
        // This function's role is just to record the new rate at this timestamp.

        PlumeStakingStorage.RateCheckpoint memory checkpoint =
            PlumeStakingStorage.RateCheckpoint({ timestamp: block.timestamp, rate: commissionRate, cumulativeIndex: 0 }); // cumulativeIndex
            // is not strictly used for commission here

        $.validatorCommissionCheckpoints[validatorId].push(checkpoint);
        emit ValidatorCommissionCheckpointCreated(validatorId, commissionRate, block.timestamp);
    }

    /**
     * @notice Settles the accrued commission for a validator for all reward tokens up to the current block.timestamp,
     *         by calling `updateRewardPerTokenForValidator` which now handles commission accrual directly.
     * @param $ The PlumeStaking storage layout.
     * @param validatorId The ID of the validator.
     */
    function _settleCommissionForValidatorUpToNow(PlumeStakingStorage.Layout storage $, uint16 validatorId) internal {
        address[] memory rewardTokens = $.rewardTokens;

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            // Calling updateRewardPerTokenForValidator will now also handle accruing commission.
            updateRewardPerTokenForValidator($, token, validatorId);
        }
    }

}
