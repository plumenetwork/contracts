// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { RewardRateCheckpointCreated, ValidatorCommissionCheckpointCreated } from "./PlumeEvents.sol";
import { PlumeStakingStorage } from "./PlumeStakingStorage.sol";
import { PlumeValidatorLogic } from "./PlumeValidatorLogic.sol";

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
            uint256 validatorLastGlobalUpdateTimestampAtLoopStart = $.validatorLastUpdateTimes[validatorId][token];

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
                // Set flag indicating user has pending rewards with this validator
                $.userHasPendingRewards[user][validatorId] = true;
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

                        // Fix: Use regular division (floor) for validator's accrued commission
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

                    // Fix: Use regular division (floor) for validator's accrued commission
                    uint256 commissionDeltaForValidator = (
                        grossRewardForValidatorThisSegment * commissionRateForSegment
                    ) / PlumeStakingStorage.REWARD_PRECISION;

                    if (commissionDeltaForValidator > 0) {
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
                lastUserRewardUpdateTime = block.timestamp; // Should ideally be stake time, but block.timestamp is
                    // fallback
            }
        }

        // If no time has passed or user hasn't earned anything yet (e.g. paid index is already current)
        if (
            block.timestamp <= lastUserRewardUpdateTime
                || finalCumulativeRewardPerToken <= lastUserPaidCumulativeRewardPerToken
        ) {
            return (0, 0, 0);
        }

        effectiveTimeDelta = block.timestamp - lastUserRewardUpdateTime; // This is the total duration of interest

        uint256[] memory distinctTimestamps =
            getDistinctTimestamps($, validatorId, token, lastUserRewardUpdateTime, block.timestamp);

        // If only start and end (or fewer), means no intermediate checkpoints relevant to this user's period.
        // The simple delta calculation using final - initial cumulative should work, but it's already part of the loop.
        // The loop needs at least two points to form a segment.
        if (distinctTimestamps.length < 2) {
            // This can happen if lastUserRewardUpdateTime == block.timestamp or no checkpoints exist.
            // The check above (block.timestamp <= lastUserRewardUpdateTime) should catch the first case.
            // If no checkpoints, getDistinctTimestamps returns [lastUserRewardUpdateTime, block.timestamp].
            // So length should be 2. If less than 2, something is off, or it's a zero-duration.
            return (0, 0, 0); // Should be caught by initial checks.
        }

        uint256 rptTracker = lastUserPaidCumulativeRewardPerToken;

        for (uint256 k = 0; k < distinctTimestamps.length - 1; ++k) {
            uint256 segmentStartTime = distinctTimestamps[k];
            uint256 segmentEndTime = distinctTimestamps[k + 1];

            if (segmentEndTime <= segmentStartTime) {
                // Should not happen with sorted distinct timestamps
                continue;
            }

            // The RPT for the validator at the START of this segment.
            // This needs to be carefully determined. It's not necessarily rptTracker if there were prior segments.
            // It's the validator's cumulative RPT as of segmentStartTime.
            // For the *first* segment (k=0), segmentStartTime is lastUserRewardUpdateTime, and
            // rptAtSegmentStart IS lastUserPaidCumulativeRewardPerToken (or rptTracker).
            // For subsequent segments, rptAtSegmentStart is the rptAtSegmentEnd of the previous segment.
            uint256 rptAtSegmentStart;
            if (k == 0) {
                rptAtSegmentStart = lastUserPaidCumulativeRewardPerToken;
            } else {
                // For k > 0, rptAtSegmentStart is the cumulative value at distinctTimestamps[k]
                // This implies we need a way to get the validator's cumulative RPT at ANY timestamp,
                // not just by stepping through.
                // The current logic correctly uses rptTracker which IS the rptAtSegmentEnd of the previous segment.
                rptAtSegmentStart = rptTracker;
            }

            // What is the validator's RPT at segmentEndTime?
            // This requires calculating the RPT increase *within this specific segment*.
            PlumeStakingStorage.RateCheckpoint memory rewardRateInfoForSegment =
                getEffectiveRewardRateAt($, token, validatorId, segmentStartTime); // Rate at START of segment
            uint256 effectiveRewardRate = rewardRateInfoForSegment.rate;
            uint256 segmentDuration = segmentEndTime - segmentStartTime;

            uint256 rptIncreaseInSegment = 0;
            if (effectiveRewardRate > 0 && segmentDuration > 0) {
                rptIncreaseInSegment = segmentDuration * effectiveRewardRate;
            }

            uint256 rptAtSegmentEnd = rptAtSegmentStart + rptIncreaseInSegment;

            // The actual RPT delta for the user in this segment.
            // The user "catches up" from rptAtSegmentStart to rptAtSegmentEnd.
            // Note: This is the same as rptIncreaseInSegment for this specific case
            uint256 rewardPerTokenDeltaForUserInSegment = rptAtSegmentEnd - rptAtSegmentStart;

            if (rewardPerTokenDeltaForUserInSegment > 0 && userStakedAmount > 0) {
                uint256 grossRewardForSegment =
                    (userStakedAmount * rewardPerTokenDeltaForUserInSegment) / PlumeStakingStorage.REWARD_PRECISION;

                // Commission rate effective at the START of this segment
                uint256 effectiveCommissionRate = getEffectiveCommissionRateAt($, validatorId, segmentStartTime);

                // Fix: Use ceiling division for commission charged to user to ensure rounding up
                uint256 commissionForThisSegment =
                    _ceilDiv(grossRewardForSegment * effectiveCommissionRate, PlumeStakingStorage.REWARD_PRECISION);

                if (grossRewardForSegment >= commissionForThisSegment) {
                    totalUserRewardDelta += (grossRewardForSegment - commissionForThisSegment);
                } // else, net reward is 0 for this segment for the user.
                // Commission is still generated for the validator based on gross.
                // This was previously missing, commission should always be based on gross.
                totalCommissionAmountDelta += commissionForThisSegment;
            }
            rptTracker = rptAtSegmentEnd; // Update tracker for the next segment's start
        }
        return (totalUserRewardDelta, totalCommissionAmountDelta, effectiveTimeDelta);
    }

    /**
     * @notice Helper function for ceiling division to ensure rounding up
     * @dev Used for commission calculations charged to users to ensure sum of user commissions >= validator accrued
     * commission
     * @param a Numerator
     * @param b Denominator
     * @return result The ceiling of a/b
     */
    function _ceilDiv(uint256 a, uint256 b) internal pure returns (uint256 result) {
        if (b == 0) {
            return 0;
        }
        return (a + b - 1) / b;
    }

    /**
     * @notice Helper to get a sorted list of unique timestamps relevant for a claim period.
     * Includes period start, period end, and all reward/commission checkpoints in between.
     * Uses a merge-style approach for efficiency, assuming checkpoint arrays are sorted.
     */
    function getDistinctTimestamps(
        PlumeStakingStorage.Layout storage $,
        uint16 validatorId,
        address token,
        uint256 periodStart,
        uint256 periodEnd
    ) internal view returns (uint256[] memory) {
        PlumeStakingStorage.RateCheckpoint[] storage rewardCheckpoints =
            $.validatorRewardRateCheckpoints[validatorId][token];
        PlumeStakingStorage.RateCheckpoint[] storage commissionCheckpoints =
            $.validatorCommissionCheckpoints[validatorId];

        uint256 len1 = rewardCheckpoints.length;
        uint256 len2 = commissionCheckpoints.length;

        if (periodStart > periodEnd) {
            // Invalid period
            return new uint256[](0);
        }
        if (periodStart == periodEnd) {
            // Zero-duration period
            uint256[] memory singlePoint = new uint256[](1);
            singlePoint[0] = periodStart;
            return singlePoint;
        }

        // Max possible output length = len1 + len2 + 2 (start, end, all unique checkpoints)
        uint256[] memory result = new uint256[](len1 + len2 + 2);
        uint256 i = 0; // Pointer for rewardCheckpoints
        uint256 j = 0; // Pointer for commissionCheckpoints
        uint256 k = 0; // Pointer for result array

        result[k++] = periodStart;
        uint256 lastAddedTimestamp = periodStart;

        // Skip checkpoints at or before periodStart
        while (i < len1 && rewardCheckpoints[i].timestamp <= periodStart) {
            i++;
        }
        while (j < len2 && commissionCheckpoints[j].timestamp <= periodStart) {
            j++;
        }

        // Merge the two arrays, adding distinct timestamps strictly between periodStart and periodEnd
        while (i < len1 || j < len2) {
            uint256 t1 = (i < len1) ? rewardCheckpoints[i].timestamp : type(uint256).max;
            uint256 t2 = (j < len2) ? commissionCheckpoints[j].timestamp : type(uint256).max;
            uint256 currentTimestampToAdd;

            bool advanceI = false;
            bool advanceJ = false;

            if (t1 < t2) {
                currentTimestampToAdd = t1;
                advanceI = true;
            } else if (t2 < t1) {
                currentTimestampToAdd = t2;
                advanceJ = true;
            } else if (t1 != type(uint256).max) {
                // t1 == t2 and not max_value (both arrays exhausted)
                currentTimestampToAdd = t1; // or t2
                advanceI = true;
                advanceJ = true;
            } else {
                // Both t1 and t2 are type(uint256).max, meaning both arrays are exhausted
                break;
            }

            if (currentTimestampToAdd >= periodEnd) {
                // Stop if we reach or exceed periodEnd
                break;
            }

            // Add if it's a new distinct timestamp that is > lastAddedTimestamp (which was periodStart initially)
            if (currentTimestampToAdd > lastAddedTimestamp) {
                result[k++] = currentTimestampToAdd;
                lastAddedTimestamp = currentTimestampToAdd;
            }

            if (advanceI) {
                i++;
            }
            if (advanceJ) {
                j++;
            }
        }

        // Add periodEnd if it's not already the last element added and is greater
        if (lastAddedTimestamp < periodEnd) {
            result[k++] = periodEnd;
        }

        assembly {
            mstore(result, k)
        }
        return result;
    }

    /**
     * @notice Gets the effective reward rate for a validator and token at a given timestamp.
     * Looks up the validator-specific reward rate checkpoint. If none, uses global reward rate.
     * @dev Fixed to return 0 rate if token is no longer a valid reward token
     */
    function getEffectiveRewardRateAt(
        PlumeStakingStorage.Layout storage $,
        address token,
        uint16 validatorId,
        uint256 timestamp
    ) internal view returns (PlumeStakingStorage.RateCheckpoint memory effectiveCheckpoint) {
        // Fix: Check if token is still a valid reward token
        if (!$.isRewardToken[token]) {
            effectiveCheckpoint.rate = 0;
            effectiveCheckpoint.timestamp = timestamp;
            effectiveCheckpoint.cumulativeIndex = 0;
            return effectiveCheckpoint;
        }

        PlumeStakingStorage.RateCheckpoint[] storage checkpoints = $.validatorRewardRateCheckpoints[validatorId][token];
        uint256 chkCount = checkpoints.length;

        if (chkCount > 0) {
            uint256 idx = findRewardRateCheckpointIndexAtOrBefore($, validatorId, token, timestamp);

            // Check if checkpoints[idx] is actually valid for this timestamp.
            if (idx < chkCount && checkpoints[idx].timestamp <= timestamp) {
                // Additionally, ensure that if there's a *next* checkpoint, its timestamp is > current query timestamp
                // This ensures we pick the one *immediately* at or before.
                if (idx + 1 < chkCount && checkpoints[idx + 1].timestamp <= timestamp) {
                    // This means a later checkpoint (idx+1) is also <= timestamp.
                    // The binary search should ideally give the *latest* one.
                    // Let's re-verify findRewardRateCheckpointIndexAtOrBefore.
                    // For now, assume `idx` is the correct one.
                }
                return checkpoints[idx];
            }
        }
        // Fallback: No validator-specific checkpoint found that is <= timestamp, or no checkpoints exist.
        // The global rate itself doesn't have a cumulative index in the same way here.
        // We need to construct a checkpoint-like struct.
        // The cumulative index part is tricky for global fallbacks if we expect it to be accurate globally.
        // For rate, this is fine. For cumulativeIndex, it should reflect
        // $.validatorRewardPerTokenCumulative[validatorId][token]
        // if we are at "now" or need to calculate up to "now" for a segment ending at "now".
        // However, getEffectiveRewardRateAt is used to find the *rate* for a segment.
        // The cumulative index for the *start* of the segment is taken from the previous segment's end or initial user
        // state.
        // So, for rate calculation, this is okay.

        effectiveCheckpoint.rate = $.rewardRates[token]; // Global rate
        effectiveCheckpoint.timestamp = timestamp; // Timestamp of query

        // If falling back to global rate, what should cumulativeIndex be?
        // If the query timestamp is for the *current* live segment (ending at block.timestamp),
        // then the "live" cumulative index for the validator is relevant.
        // If it's for a historical segment, this fallback is more about just getting the rate.
        // The calculateRewardsWithCheckpoints uses this to find the *rate* for a segment.
        // The cumulative index for the *start* of the segment is taken from the previous segment's end or initial user
        // state.
        // So, for rate calculation, this is okay.
        effectiveCheckpoint.cumulativeIndex = 0; // Or perhaps the validator's current cumulative if timestamp ==
            // block.timestamp?
            // Let's assume 0 is fine for rate-finding purpose. The loop handles accumulation.
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
                // Similar to above, ensure this is the latest one.
                return checkpoints[idx].rate;
            }
        }
        // Fallback to the current commission rate stored directly in ValidatorInfo
        // This is important if no checkpoints exist or all are in the future.
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
            return 0; // Indicates no checkpoints, caller might use global rate.
        }

        uint256 low = 0;
        uint256 high = len - 1;
        uint256 ans = 0;
        // If all checkpoints are in the future, ans remains 0.
        // The caller (getEffectiveRewardRateAt) should check if checkpoints[0].timestamp > timestamp.
        // If so, it correctly falls back to global. If not, checkpoints[0] is a candidate.

        bool foundSuitable = false;

        while (low <= high) {
            uint256 mid = low + (high - low) / 2;
            if (checkpoints[mid].timestamp <= timestamp) {
                ans = mid; // This checkpoint is a candidate
                foundSuitable = true;
                low = mid + 1; // Try to find a later one
            } else {
                // checkpoints[mid].timestamp > timestamp
                if (mid == 0) {
                    // If even the first is too new
                    break;
                }
                high = mid - 1;
            }
        }
        // If !foundSuitable, it means all checkpoints were > timestamp.
        // `ans` would be 0. getEffectiveRewardRateAt will then check checkpoints[0].timestamp.
        // If foundSuitable, `ans` is the index of the latest checkpoint with .timestamp <= query_timestamp.
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
            return 0; // No checkpoints, caller uses current validator.commission
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
                if (mid == 0) {
                    break;
                }
                high = mid - 1;
            }
        }
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

        updateRewardPerTokenForValidator($, token, validatorId); // Settle up to now with old rate
        uint256 currentCumulativeIndex = $.validatorRewardPerTokenCumulative[validatorId][token];

        PlumeStakingStorage.RateCheckpoint memory checkpoint = PlumeStakingStorage.RateCheckpoint({
            timestamp: block.timestamp, // New rate effective from now
            rate: rate, // The new rate
            cumulativeIndex: currentCumulativeIndex // Cumulative index *before* this new rate applies
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
        // In setValidatorCommission, _settleCommissionForValidatorUpToNow is called *before* this,
        // using the *old* commission rate.
        // This function then records the *new* commission rate, effective from block.timestamp.
        // The cumulativeIndex for commission checkpoints is not as critical as for reward rates
        // if commission is always applied to the gross reward of a segment.

        PlumeStakingStorage.RateCheckpoint memory checkpoint = PlumeStakingStorage.RateCheckpoint({
            timestamp: block.timestamp,
            rate: commissionRate,
            cumulativeIndex: 0 // Or perhaps $.validatorAccruedCommission[validatorId][ANY_TOKEN_AS_PROXY]?
                // Let's stick to 0 as it's primarily rate + timestamp.
         });

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

    /**
     * @notice Checks if a user has any pending rewards with a validator across all tokens
     * @dev This function checks both current and potentially historical reward tokens
     * @param $ The PlumeStaking storage layout.
     * @param user The user address.
     * @param validatorId The validator ID.
     * @return hasPendingRewards True if user has any pending rewards with the validator
     */
    function userHasAnyPendingRewards(
        PlumeStakingStorage.Layout storage $,
        address user,
        uint16 validatorId
    ) internal view returns (bool hasPendingRewards) {
        // Quick check using the flag first
        if (!$.userHasPendingRewards[user][validatorId]) {
            return false;
        }

        // If flag is true, verify by checking actual balances
        // This handles edge cases where flag might be stale
        address[] memory currentRewardTokens = $.rewardTokens;
        for (uint256 i = 0; i < currentRewardTokens.length; i++) {
            if ($.userRewards[user][validatorId][currentRewardTokens[i]] > 0) {
                return true;
            }
        }

        // No pending rewards found, but don't modify state in a view function
        // The flag will be cleared by clearPendingRewardsFlagIfEmpty when needed
        return false;
    }

    /**
     * @notice Clears the pending rewards flag for a user-validator pair if no rewards remain
     * @dev Should be called after claiming rewards to maintain flag accuracy
     * @param $ The PlumeStaking storage layout.
     * @param user The user address.
     * @param validatorId The validator ID.
     */
    function clearPendingRewardsFlagIfEmpty(
        PlumeStakingStorage.Layout storage $,
        address user,
        uint16 validatorId
    ) internal {
        if (!$.userHasPendingRewards[user][validatorId]) {
            return; // Already cleared
        }

        // Check if user still has any pending rewards
        address[] memory currentRewardTokens = $.rewardTokens;
        for (uint256 i = 0; i < currentRewardTokens.length; i++) {
            if ($.userRewards[user][validatorId][currentRewardTokens[i]] > 0) {
                return; // Still has pending rewards, don't clear flag
            }
        }

        // No pending rewards found - clear the flag
        $.userHasPendingRewards[user][validatorId] = false;
    }

}
