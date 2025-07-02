// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { InternalInconsistency, MaxCommissionCheckpointsExceeded } from "./PlumeErrors.sol";
import { RewardRateCheckpointCreated, ValidatorCommissionCheckpointCreated } from "./PlumeEvents.sol";
import { PlumeStakingStorage } from "./PlumeStakingStorage.sol";
import { PlumeValidatorLogic } from "./PlumeValidatorLogic.sol";

/**
 * @title PlumeRewardLogic
 * @author Eugene Y. Q. Shen, Alp Guneysel
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
            updateRewardsForValidatorAndToken($, user, validatorId, token);
        }
    }

     /**
     * @notice Updates rewards for a specific user, validator, and token by settling pending rewards into storage.
     * @dev This is the granular settlement function. It updates the user's stored rewards and the global
     *      totalClaimableByToken.
     * @param $ The PlumeStaking storage layout.
     * @param user The address of the user whose rewards are being updated.
     * @param validatorId The ID of the validator.
     * @param token The address of the reward token.
     */
    function updateRewardsForValidatorAndToken(
        PlumeStakingStorage.Layout storage $,
        address user,
        uint16 validatorId,
        address token
    ) internal {
        // NOTE: The call to updateRewardPerTokenForValidator was removed from here. It is correctly and
        // conditionally called inside calculateRewardsWithCheckpoints.

        uint256 userStakedAmount = $.userValidatorStakes[user][validatorId].staked;

        if (userStakedAmount == 0) {
            // If user has no stake, there's nothing to calculate. We still need to update the user's "paid" pointers
            // to the latest global state to prevent incorrect future calculations.
            // First, ensure the validator's state is up-to-date.
            if (!$.validators[validatorId].slashed) {
                updateRewardPerTokenForValidator($, token, validatorId);
            }
            $.userValidatorRewardPerTokenPaid[user][validatorId][token] =
                $.validatorRewardPerTokenCumulative[validatorId][token];
            $.userValidatorRewardPerTokenPaidTimestamp[user][validatorId][token] = block.timestamp;
            return;
        }

        if ($.userValidatorStakeStartTime[user][validatorId] == 0) {
            $.userValidatorStakeStartTime[user][validatorId] = block.timestamp;
        }

        (uint256 userRewardDelta,,) =
            calculateRewardsWithCheckpoints($, user, validatorId, token, userStakedAmount);

        if (userRewardDelta > 0) {
            $.userRewards[user][validatorId][token] += userRewardDelta;
            $.totalClaimableByToken[token] += userRewardDelta;
            $.userHasPendingRewards[user][validatorId] = true;
        }

        // Update paid pointers AFTER calculating delta to correctly checkpoint the user's state.
        $.userValidatorRewardPerTokenPaid[user][validatorId][token] =
            $.validatorRewardPerTokenCumulative[validatorId][token];
        $.userValidatorRewardPerTokenPaidTimestamp[user][validatorId][token] = block.timestamp;

        if ($.validatorRewardRateCheckpoints[validatorId][token].length > 0) {
            $.userLastCheckpointIndex[user][validatorId][token] =
                $.validatorRewardRateCheckpoints[validatorId][token].length - 1;
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

        // --- REORDERED SLASHED/INACTIVE CHECKS ---
        // Check for slashed state FIRST since slashed validators are also inactive
        if (validator.slashed) {
            // For slashed validators, no further rewards or commission accrue.
            // We just update the timestamp to the current time to mark that the state is "settled" up to now.
            $.validatorLastUpdateTimes[validatorId][token] = block.timestamp;

            // Add a defensive check: A slashed validator should never have any stake. If it does, something is
            // wrong with the slashing logic itself.
            if ($.validatorTotalStaked[validatorId] > 0) {
                revert InternalInconsistency("Slashed validator has non-zero totalStaked");
            }
            return;
        } else if (!validator.active) {
            // For inactive (but not slashed) validators, no further rewards or commission accrue.
            // We just update the timestamp to the current time to mark that the state is "settled" up to now.
            $.validatorLastUpdateTimes[validatorId][token] = block.timestamp;
            return;
        }
        // --- END REORDERED CHECKS ---

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
     * @notice Core reward calculation logic used by both modifying and view functions
     * @dev Calculates rewards using segmented approach for accurate commission handling
     * @param $ The PlumeStaking storage layout.
     * @param user The user address.
     * @param validatorId The validator ID.
     * @param token The reward token address.
     * @param userStakedAmount The user's current staked amount with this validator.
     * @param currentCumulativeRewardPerToken The current cumulative reward per token to use
     * @return totalUserRewardDelta The calculated reward amount for the user (after commission).
     * @return totalCommissionAmountDelta The calculated commission amount for the validator.
     * @return effectiveTimeDelta The effective time delta for the calculation.
     */
    function _calculateRewardsCore(
        PlumeStakingStorage.Layout storage $,
        address user,
        uint16 validatorId,
        address token,
        uint256 userStakedAmount,
        uint256 currentCumulativeRewardPerToken
    )
        internal
        view
        returns (uint256 totalUserRewardDelta, uint256 totalCommissionAmountDelta, uint256 effectiveTimeDelta)
    {
        uint256 lastUserPaidCumulativeRewardPerToken = $.userValidatorRewardPerTokenPaid[user][validatorId][token];
        uint256 lastUserRewardUpdateTime = $.userValidatorRewardPerTokenPaidTimestamp[user][validatorId][token];

        if (lastUserRewardUpdateTime == 0) {
            // Handle lazy user initialization for token addition
            uint256 tokenAdditionTime = $.tokenAdditionTimestamps[token];
            uint256 userStakeStartTime = $.userValidatorStakeStartTime[user][validatorId];

            if (tokenAdditionTime > 0 && tokenAdditionTime > userStakeStartTime) {
                // User was staking before token was added - start from token addition
                lastUserRewardUpdateTime = tokenAdditionTime;
            } else {
                // Token existed when user started staking - use stake start time
                lastUserRewardUpdateTime = userStakeStartTime;
            }

            if (lastUserRewardUpdateTime == 0 && $.userValidatorStakes[user][validatorId].staked > 0) {
                // Fixed fallback: don't use block.timestamp if it's after slash timestamp
                uint256 fallbackTime = block.timestamp;

                // If validator is slashed, cap fallback time at slash timestamp
                PlumeStakingStorage.ValidatorInfo storage validator = $.validators[validatorId];
                if (validator.slashedAtTimestamp > 0 && validator.slashedAtTimestamp < fallbackTime) {
                    fallbackTime = validator.slashedAtTimestamp;
                }

                lastUserRewardUpdateTime = fallbackTime;
            }
        }

        // CRITICAL FIX: For recently reactivated validators, don't calculate rewards
        // from before the reactivation time to prevent retroactive accrual
        uint256 validatorLastUpdateTime = $.validatorLastUpdateTimes[validatorId][token];

        // CRITICAL FIX: For slashed/inactive validators, cap the calculation period at the timestamp
        PlumeStakingStorage.ValidatorInfo storage validator = $.validators[validatorId];
        uint256 effectiveEndTime = block.timestamp;

        // Check token removal timestamp
        uint256 tokenRemovalTime = $.tokenRemovalTimestamps[token];
        if (tokenRemovalTime > 0 && tokenRemovalTime < effectiveEndTime) {
            effectiveEndTime = tokenRemovalTime;
        }

        // Then check validator slash/inactive timestamp
        if (validator.slashedAtTimestamp > 0) {
            if (validator.slashedAtTimestamp < effectiveEndTime) {
                effectiveEndTime = validator.slashedAtTimestamp;
            }
        }

        // If no time has passed or user hasn't earned anything yet (e.g. paid index is already current)
        if (
            effectiveEndTime <= lastUserRewardUpdateTime
                || currentCumulativeRewardPerToken <= lastUserPaidCumulativeRewardPerToken
        ) {
            return (0, 0, 0);
        }

        effectiveTimeDelta = effectiveEndTime - lastUserRewardUpdateTime; // This is the total duration of interest

        uint256[] memory distinctTimestamps =
            getDistinctTimestamps($, validatorId, token, lastUserRewardUpdateTime, effectiveEndTime);

        // If only start and end (or fewer), means no intermediate checkpoints relevant to this user's period.
        // The simple delta calculation using final - initial cumulative should work, but it's already part of the loop.
        // The loop needs at least two points to form a segment.
        if (distinctTimestamps.length < 2) {
            // This can happen if lastUserRewardUpdateTime == effectiveEndTime or no checkpoints exist.
            // The check above (effectiveEndTime <= lastUserRewardUpdateTime) should catch the first case.
            // If no checkpoints, getDistinctTimestamps returns [lastUserRewardUpdateTime, effectiveEndTime].
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
        PlumeStakingStorage.ValidatorInfo storage validator = $.validators[validatorId];

        if (!validator.slashed) {
            // Normal case: update and use the updated cumulative.
            updateRewardPerTokenForValidator($, token, validatorId);
            uint256 finalCumulativeRewardPerToken = $.validatorRewardPerTokenCumulative[validatorId][token];
            return _calculateRewardsCore($, user, validatorId, token, userStakedAmount, finalCumulativeRewardPerToken);
        } else {
            // Slashed validator case: calculate what cumulative should be up to the slash timestamp.
            // We DO NOT call updateRewardPerTokenForValidator here because its logic is incorrect for slashed validators.
            uint256 currentCumulativeRewardPerToken = $.validatorRewardPerTokenCumulative[validatorId][token];
            uint256 effectiveEndTime = validator.slashedAtTimestamp;

            uint256 tokenRemovalTime = $.tokenRemovalTimestamps[token];
            if (tokenRemovalTime > 0 && tokenRemovalTime < effectiveEndTime) {
                effectiveEndTime = tokenRemovalTime;
            }

            uint256 validatorLastUpdateTime = $.validatorLastUpdateTimes[validatorId][token];

            if (effectiveEndTime > validatorLastUpdateTime) {
                uint256 timeSinceLastUpdate = effectiveEndTime - validatorLastUpdateTime;

                if (userStakedAmount > 0) {
                    PlumeStakingStorage.RateCheckpoint memory effectiveRewardRateChk =
                        getEffectiveRewardRateAt($, token, validatorId, validatorLastUpdateTime); // Use rate at start of segment
                    uint256 effectiveRewardRate = effectiveRewardRateChk.rate;

                    if (effectiveRewardRate > 0) {
                        uint256 rewardPerTokenIncrease = timeSinceLastUpdate * effectiveRewardRate;
                        currentCumulativeRewardPerToken += rewardPerTokenIncrease;
                    }
                }
            }

            return _calculateRewardsCore($, user, validatorId, token, userStakedAmount, currentCumulativeRewardPerToken);
        }
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

        // Skip checkpoints BEFORE periodStart (but include checkpoints AT periodStart)
        // This ensures commission/reward rate changes exactly at period boundary are included
        while (i < len1 && rewardCheckpoints[i].timestamp < periodStart) {
            i++;
        }
        while (j < len2 && commissionCheckpoints[j].timestamp < periodStart) {
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
     * @dev Returns the reward rate that was active at the given timestamp, regardless of current token status
     */
    function getEffectiveRewardRateAt(
        PlumeStakingStorage.Layout storage $,
        address token,
        uint16 validatorId,
        uint256 timestamp
    ) internal view returns (PlumeStakingStorage.RateCheckpoint memory effectiveCheckpoint) {
        // For historical reward calculations, we should use the rate that was active at that time
        // regardless of whether the token is currently valid or the validator is currently slashed

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
                    // Let's reverify findRewardRateCheckpointIndexAtOrBefore.
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
        updateRewardPerTokenForValidator($, token, validatorId); // Settle up to now with old rate
        uint256 currentCumulativeIndex = $.validatorRewardPerTokenCumulative[validatorId][token];

        PlumeStakingStorage.RateCheckpoint[] storage checkpoints = $.validatorRewardRateCheckpoints[validatorId][token];
        uint256 len = checkpoints.length;

        PlumeStakingStorage.RateCheckpoint memory checkpoint = PlumeStakingStorage.RateCheckpoint({
            timestamp: block.timestamp, // New rate effective from now
            rate: rate, // The new rate
            cumulativeIndex: currentCumulativeIndex // Cumulative index *before* this new rate applies
         });

        uint256 checkpointIndex;

        if (len > 0 && checkpoints[len - 1].timestamp == block.timestamp) {
            // Overwrite the last checkpoint if it's from the same block
            checkpoints[len - 1] = checkpoint;
            checkpointIndex = len - 1;
        } else {
            // Otherwise, add a new one
            checkpoints.push(checkpoint);
            checkpointIndex = len;
        }

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
        // This function records the *new* commission rate, effective from block.timestamp.
        // It overwrites any previous checkpoint from the same block to prevent duplicates.
        PlumeStakingStorage.RateCheckpoint[] storage checkpoints = $.validatorCommissionCheckpoints[validatorId];
        uint256 len = checkpoints.length;

        PlumeStakingStorage.RateCheckpoint memory checkpoint = PlumeStakingStorage.RateCheckpoint({
            timestamp: block.timestamp,
            rate: commissionRate,
            cumulativeIndex: 0 // Not used for commission
         });

        if (len > 0 && checkpoints[len - 1].timestamp == block.timestamp) {
            // Overwrite the last checkpoint if it's from the same block
            checkpoints[len - 1] = checkpoint;
        } else {
            // Enforce maximum checkpoint limit before adding a new one.
            if ($.maxCommissionCheckpoints > 0 && len >= $.maxCommissionCheckpoints) {
                revert MaxCommissionCheckpointsExceeded(validatorId, $.maxCommissionCheckpoints);
            }
            // Otherwise, add a new one
            checkpoints.push(checkpoint);
        }

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
     * @notice Clears the pending rewards flag for a user-validator pair if no rewards remain
     * @dev Should be called after claiming rewards to maintain flag accuracy.
     *      This function is conservative about clearing flags to avoid removing user-validator
     *      relationships when there might still be claimable rewards from removed tokens.
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

        // Check if user still has any stored rewards for current active tokens
        address[] memory currentRewardTokens = $.rewardTokens;
        for (uint256 i = 0; i < currentRewardTokens.length; i++) {
            if ($.userRewards[user][validatorId][currentRewardTokens[i]] > 0) {
                return; // Still has pending rewards, don't clear flag
            }
        }

        // Additional check: if user has any staking history with this validator,
        // be conservative and only clear if we can verify no rewards from any source
        uint256 userStakedAmount = $.userValidatorStakes[user][validatorId].staked;
        uint256 userStakeStartTime = $.userValidatorStakeStartTime[user][validatorId];

        if (userStakeStartTime > 0) {
            // User has staking history - check if they might have rewards from removed tokens
            // by verifying with the comprehensive earned calculation for PLUME_NATIVE
            // (most common removed token case)
            address plumeNative = PlumeStakingStorage.PLUME_NATIVE;

            // Check stored rewards for PLUME_NATIVE (might be removed)
            if ($.userRewards[user][validatorId][plumeNative] > 0) {
                return; // Still has PLUME_NATIVE rewards
            }

            // If user still has active stake, check for any calculable rewards
            if (userStakedAmount > 0) {
                (uint256 pendingPlumeRewards,,) =
                    calculateRewardsWithCheckpointsView($, user, validatorId, plumeNative, userStakedAmount);
                if (pendingPlumeRewards > 0) {
                    return; // Still has calculable rewards
                }
            }
        }

        // Safe to clear the flag - no stored rewards found and no significant pending rewards
        $.userHasPendingRewards[user][validatorId] = false;
    }

    /**
     * @notice View-only version of reward calculation that doesn't modify storage
     * @dev Used by earned() and other view functions to calculate rewards without state changes
     * @param $ The PlumeStaking storage layout.
     * @param user The user address.
     * @param validatorId The validator ID.
     * @param token The reward token address.
     * @param userStakedAmount The user's current staked amount with this validator.
     * @return totalUserRewardDelta The calculated reward amount for the user (after commission).
     * @return totalCommissionAmountDelta The calculated commission amount for the validator.
     * @return effectiveTimeDelta The effective time delta for the calculation.
     */
    function calculateRewardsWithCheckpointsView(
        PlumeStakingStorage.Layout storage $,
        address user,
        uint16 validatorId,
        address token,
        uint256 userStakedAmount
    )
        internal
        view
        returns (uint256 totalUserRewardDelta, uint256 totalCommissionAmountDelta, uint256 effectiveTimeDelta)
    {
        // Don't call updateRewardPerTokenForValidator - this is view-only
        // Calculate what the cumulative would be if updated
        uint256 currentCumulativeRewardPerToken = $.validatorRewardPerTokenCumulative[validatorId][token];

        // Calculate effective end time considering all constraints
        PlumeStakingStorage.ValidatorInfo storage validator = $.validators[validatorId];
        uint256 effectiveEndTime = block.timestamp;

        // Check token removal timestamp
        uint256 tokenRemovalTime = $.tokenRemovalTimestamps[token];
        if (tokenRemovalTime > 0 && tokenRemovalTime < effectiveEndTime) {
            effectiveEndTime = tokenRemovalTime;
        }

        // Check validator slash/inactive timestamp
        if (validator.slashedAtTimestamp > 0) {
            if (validator.slashedAtTimestamp < effectiveEndTime) {
                effectiveEndTime = validator.slashedAtTimestamp;
            }
        }

        // Calculate theoretical current cumulative (what it would be if updated)
        uint256 validatorLastUpdateTime = $.validatorLastUpdateTimes[validatorId][token];

        if (effectiveEndTime > validatorLastUpdateTime) {
            uint256 timeSinceLastUpdate = effectiveEndTime - validatorLastUpdateTime;

            // Fix: Reorder logic to check for slashed state FIRST.
            // A slashed validator is also inactive, so the slashed check must come first.
            if (validator.slashed) {
                // Slashed validator: calculate rewards up to slash timestamp if user has stake
                if (userStakedAmount > 0) {
                    PlumeStakingStorage.RateCheckpoint memory effectiveRewardRateChk =
                        getEffectiveRewardRateAt($, token, validatorId, effectiveEndTime);
                    uint256 effectiveRewardRate = effectiveRewardRateChk.rate;

                    if (effectiveRewardRate > 0) {
                        uint256 rewardPerTokenIncrease = timeSinceLastUpdate * effectiveRewardRate;
                        currentCumulativeRewardPerToken += rewardPerTokenIncrease;
                    }
                }
            } else if (!validator.active) {
                // Inactive (but not slashed) validator: no additional rewards should be calculated
                // The cumulative stays at its current value
            } else {
                // Active validator: calculate rewards normally
                uint256 totalStaked = $.validatorTotalStaked[validatorId];

                if (totalStaked > 0) {
                    PlumeStakingStorage.RateCheckpoint memory effectiveRewardRateChk =
                        getEffectiveRewardRateAt($, token, validatorId, effectiveEndTime);
                    uint256 effectiveRewardRate = effectiveRewardRateChk.rate;

                    if (effectiveRewardRate > 0) {
                        uint256 rewardPerTokenIncrease = timeSinceLastUpdate * effectiveRewardRate;
                        currentCumulativeRewardPerToken += rewardPerTokenIncrease;
                    }
                }
            }
        }

        return _calculateRewardsCore($, user, validatorId, token, userStakedAmount, currentCumulativeRewardPerToken);
    }

}

