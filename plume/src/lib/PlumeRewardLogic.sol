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

    uint256 internal constant REWARD_PRECISION = 1e18;

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
        console2.log("updateRewardsForValidator");

        address[] memory rewardTokens = $.rewardTokens;
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            uint256 validatorLastGlobalUpdateTimestampAtLoopStart = $.validatorLastUpdateTimes[validatorId][token]; // CAPTURE HERE

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




            console2.log("User for rewards update:");
            console2.log(user);
            console2.log("Token for rewards update:");
            console2.log(token);
            console2.log("User staked amount:");
            console2.log(userStakedAmount);
            console2.log("Validator commission rate for period:");
            console2.log(validatorCommission);
            console2.log("userRewardDelta", userRewardDelta);
            console2.log("commissionAmountDelta", commissionAmountDelta);
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
        uint256 totalStaked = $.validatorTotalStaked[validatorId];
        uint256 oldLastUpdateTime = $.validatorLastUpdateTimes[validatorId][token]; // Capture before update

        if (block.timestamp > oldLastUpdateTime) {
            if (totalStaked > 0) {
                uint256 timeDelta = block.timestamp - oldLastUpdateTime;
                // Get the reward rate effective for the segment ending at block.timestamp
                PlumeStakingStorage.RateCheckpoint memory effectiveRewardRateChk = getEffectiveRewardRateAt($, token, validatorId, block.timestamp);
                uint256 effectiveRewardRate = effectiveRewardRateChk.rate;

                if (effectiveRewardRate > 0) {
                    uint256 rewardPerTokenIncrease = timeDelta * effectiveRewardRate;
                    $.validatorRewardPerTokenCumulative[validatorId][token] += rewardPerTokenIncrease;

                    // Accrue commission for the validator for this segment
                    // The commission rate should be the one effective at the START of this segment (oldLastUpdateTime)
                    uint256 commissionRateForSegment = getEffectiveCommissionRateAt($, validatorId, oldLastUpdateTime);
                    uint256 grossRewardForValidatorThisSegment = (totalStaked * rewardPerTokenIncrease) / REWARD_PRECISION;
                    uint256 commissionDeltaForValidator = (grossRewardForValidatorThisSegment * commissionRateForSegment) / REWARD_PRECISION;

                    if (commissionDeltaForValidator > 0) {
                        uint256 previousAccrued = $.validatorAccruedCommission[validatorId][token];
                        $.validatorAccruedCommission[validatorId][token] += commissionDeltaForValidator;
                        console2.log("URPTFV LOG - validatorId:", validatorId);
                        console2.log("URPTFV LOG - token:", token);
                        console2.log("URPTFV LOG - oldLastUpdateTime:", oldLastUpdateTime);
                        console2.log("URPTFV LOG - currentTime (block.timestamp):", block.timestamp);
                        console2.log("URPTFV LOG - rewardPerTokenIncrease:", rewardPerTokenIncrease);
                        console2.log("URPTFV LOG - commissionRateForSegment:", commissionRateForSegment);
                        console2.log("URPTFV LOG - grossRewardForValidatorThisSegment:", grossRewardForValidatorThisSegment);
                        console2.log("URPTFV LOG - commissionDeltaForValidator:", commissionDeltaForValidator);
                        console2.log("URPTFV LOG - previousAccrued:", previousAccrued);
                        console2.log("URPTFV LOG - newAccruedCommission:", $.validatorAccruedCommission[validatorId][token]);

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
        // Update global validator-specific cumulative reward per token and last update time.
        // This ensures finalCumulativeRewardPerToken is up-to-date.
        updateRewardPerTokenForValidator($, token, validatorId);

        uint256 lastUserPaidCumulativeRewardPerToken = $.userValidatorRewardPerTokenPaid[user][validatorId][token];
        // finalCumulativeRewardPerToken is the most up-to-date RPT for this validator/token.
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

        uint256[] memory distinctTimestamps = getDistinctTimestamps($, validatorId, token, lastUserRewardUpdateTime, block.timestamp);

        if (distinctTimestamps.length < 2) {
            return (0, 0, 0);
        }
        
        console2.log("calculateRewardsWithCheckpoints: User %s, Val %s, Token %s", user, validatorId, token);
        console2.log("Distinct timestamps for segments: %s. Period: %s to %s", distinctTimestamps.length, lastUserRewardUpdateTime, block.timestamp);
        // for(uint k=0; k<distinctTimestamps.length; ++k) { console2.log("  ts[%s]: %s", k, distinctTimestamps[k]); }

        uint256 currentCumulativeRewardPerToken = lastUserPaidCumulativeRewardPerToken;

        for (uint256 k = 0; k < distinctTimestamps.length - 1; ++k) {
            uint256 segmentStartTime = distinctTimestamps[k];
            uint256 actualSegmentEndTime = distinctTimestamps[k+1];

            if (actualSegmentEndTime <= segmentStartTime) {
                continue;
            }

            uint256 rptAtSegmentStart = currentCumulativeRewardPerToken;
            uint256 rptAtSegmentEnd;

            // Get effective reward RATE at the START of the segment
            PlumeStakingStorage.RateCheckpoint memory rewardRateInfoAtSegmentStart = getEffectiveRewardRateAt($, token, validatorId, segmentStartTime);
            uint256 effectiveRewardRateForSegment = rewardRateInfoAtSegmentStart.rate;
            
            uint256 timeDeltaForSegment = actualSegmentEndTime - segmentStartTime;
            uint256 rewardPerTokenIncreaseForSegment = 0;

            if (effectiveRewardRateForSegment > 0 && timeDeltaForSegment > 0) {
                 rewardPerTokenIncreaseForSegment = timeDeltaForSegment * effectiveRewardRateForSegment;
            }
            rptAtSegmentEnd = rptAtSegmentStart + rewardPerTokenIncreaseForSegment;
            
            // Sanity check: if actualSegmentEndTime is block.timestamp, rptAtSegmentEnd should ideally match finalCumulativeRewardPerToken.
            // This is a good test for consistency.
            if (actualSegmentEndTime == block.timestamp) {
                // Due to potential minor differences in how distinctTimestamps are formed vs. direct updateRewardPerTokenForValidator,
                // using finalCumulativeRewardPerToken ensures consistency for the very last point.
                // However, for calculations across all segments, the per-segment calculation is key.
                // If there's a notable mismatch, it points to issues in rate fetching or distinctTimestamps.
                // For now, we will use the calculated rptAtSegmentEnd.
                // One option: if (actualSegmentEndTime == block.timestamp) rptAtSegmentEnd = finalCumulativeRewardPerToken;
                // Let's stick to the per-segment calculation for its RPT delta for internal consistency.
            }


            uint256 rewardPerTokenDeltaForSegment = 0;
            if (rptAtSegmentEnd > rptAtSegmentStart) { // Ensure positive delta
                rewardPerTokenDeltaForSegment = rptAtSegmentEnd - rptAtSegmentStart;
            }


            if (rewardPerTokenDeltaForSegment > 0 && userStakedAmount > 0) {
                uint256 grossRewardForSegment = (userStakedAmount * rewardPerTokenDeltaForSegment) / REWARD_PRECISION;
                uint256 effectiveCommissionRate = getEffectiveCommissionRateAt($, validatorId, segmentStartTime);
                uint256 commissionForThisSegment = (grossRewardForSegment * effectiveCommissionRate) / REWARD_PRECISION;

                console2.log("  Segment %s: startTime %s, endTime %s", k, segmentStartTime, actualSegmentEndTime);
                console2.log("    RateForSeg: %s, TimeDeltaForSeg: %s, RPT_Incr_Seg: %s", effectiveRewardRateForSegment, timeDeltaForSegment, rewardPerTokenIncreaseForSegment);
                console2.log("    RPT_Start: %s, RPT_End (calc): %s, RPT_Delta_Seg: %s", rptAtSegmentStart, rptAtSegmentEnd, rewardPerTokenDeltaForSegment);
                console2.log("    UserStake: %s, GrossReward_Seg: %s", userStakedAmount, grossRewardForSegment);
                console2.log("    EffectiveCommissionRate (at %s): %s, CommissionForThisSegment: %s", segmentStartTime, effectiveCommissionRate, commissionForThisSegment);

                totalUserRewardDelta += (grossRewardForSegment - commissionForThisSegment);
                totalCommissionAmountDelta += commissionForThisSegment;
                console2.log("    Cumulative totalUserRewardDelta: %s", totalUserRewardDelta);
                console2.log("    Cumulative totalCommissionAmountDelta: %s", totalCommissionAmountDelta);
            } else if (userStakedAmount > 0) {
                 console2.log("  Segment k", k);
                 console2.log("  Segment segmentStartTime",  segmentStartTime );
                 console2.log("  Segment actualSegmentEndTime", actualSegmentEndTime);
                 console2.log("  Segment effectiveRewardRateForSegment", effectiveRewardRateForSegment);
                 console2.log("  Segment timeDeltaForSegment", timeDeltaForSegment);
                 console2.log("  Segment rptAtSegmentStart",  rptAtSegmentStart);
                 console2.log("  Segment rptAtSegmentEnd",  rptAtSegmentEnd);
            }
            
            currentCumulativeRewardPerToken = rptAtSegmentEnd;
        }

        console2.log("calculateRewardsWithCheckpoints USER FINAL: user %s, valId %s, token %s", user, validatorId, token);
        console2.log("calculateRewardsWithCheckpoints USER FINAL: totalUserRewardDelta %s (Expected ~13e18)", totalUserRewardDelta);
        console2.log("calculateRewardsWithCheckpoints USER FINAL: totalCommissionAmountDelta %s (Expected ~2e18)", totalCommissionAmountDelta);
        console2.log("calculateRewardsWithCheckpoints USER FINAL: finalCumulativeRPT from updates %s, final calculated currentRPT %s", finalCumulativeRewardPerToken, currentCumulativeRewardPerToken);


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
        // A more gas-efficient sort (e.g., Timsort if available or off-chain precomputation for known N) would be needed.
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
        
        if (count == 0) return new uint256[](0); // Should not happen if periodStart/End are added

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
        for(uint256 i = 0; i < distinctCount; i++) {
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
        console2.log("GERRA Entry: val %s, token %s, queryTs %s", validatorId, token, timestamp);
        PlumeStakingStorage.RateCheckpoint[] storage checkpoints = $.validatorRewardRateCheckpoints[validatorId][token];
        uint256 chkCount = checkpoints.length;
        console2.log("GERRA: chkCount %s", chkCount);

        if (chkCount > 0) {
            for(uint i=0; i < chkCount; ++i) {
                 console2.log("GERRA - index:", i);
                 console2.log("GERRA - timestamp:", checkpoints[i].timestamp);
                 console2.log("GERRA - rate:", checkpoints[i].rate);
                 console2.log("GERRA - cumulativeIndex:", checkpoints[i].cumulativeIndex);
            }
            uint256 idx = findRewardRateCheckpointIndexAtOrBefore($, validatorId, token, timestamp);
            console2.log("GERRA: findRewardRateCheckpointIndexAtOrBefore returned idx %s", idx);
            
            // Check if checkpoints[idx] is actually valid for this timestamp.
            if (idx < chkCount && checkpoints[idx].timestamp <= timestamp) { 
                console2.log("GERRA: Using checkpoint idx %s: ts %s, rate %s", idx, checkpoints[idx].timestamp, checkpoints[idx].rate);
                return checkpoints[idx];
            } else {
                console2.log("GERRA: Checkpoint at idx %s (ts %s) is not valid for queryTs %s or idx out of bounds.", idx, (idx < chkCount ? checkpoints[idx].timestamp : 9999999999), timestamp);
            }
        }
        // Fallback: No validator-specific checkpoint found that is <= timestamp, or no checkpoints exist.
        effectiveCheckpoint.rate = $.rewardRates[token]; // Global rate
        effectiveCheckpoint.timestamp = timestamp; 
        effectiveCheckpoint.cumulativeIndex = 0; 
        console2.log("GERRA: Fallback to global rate %s", effectiveCheckpoint.rate);
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
            // Similar logic to getEffectiveRewardRateAt:
            // Check if the checkpoint at 'idx' is valid for the given 'timestamp'.
            if (checkpoints[idx].timestamp <= timestamp) {
                return checkpoints[idx].rate;
            }
            // If checkpoints[idx].timestamp > timestamp, fall through to current live commission rate.
        }
        // Fallback to current live commission rate if no historical checkpoint applies or all are future.
        return $.validators[validatorId].commission;
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
        if (len == 0) return 0; // Or handle as error / special value

        uint256 low = 0;
        uint256 high = len - 1;
        uint256 ans = 0; // Stores the index of the latest checkpoint with timestamp <= target_timestamp

        while(low <= high) {
            uint256 mid = low + (high - low) / 2;
            if(checkpoints[mid].timestamp <= timestamp) {
                ans = mid;
                low = mid + 1;
            } else {
                high = mid - 1;
            }
        }
        // If all checkpoints are in the future, ans remains 0. Caller needs to check checkpoints[ans].timestamp.
        // If len > 0 and checkpoints[ans].timestamp > timestamp (only if all are future or ans=0 is future), then no past/current chk.
        // But if ans is correctly found, checkpoints[ans].timestamp <= timestamp is guaranteed by loop.
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
        if (len == 0) return 0;

        uint256 low = 0;
        uint256 high = len - 1;
        uint256 ans = 0; 

        while(low <= high) {
            uint256 mid = low + (high - low) / 2;
            if(checkpoints[mid].timestamp <= timestamp) {
                ans = mid;
                low = mid + 1;
            } else {
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
        console2.log("CRRC_LOGIC_ENTRY: valId ", validatorId);
        console2.log("CRRC_LOGIC_ENTRY: token",  token);
        console2.log("CRRC_LOGIC_ENTRY: newRate", rate);
        console2.log("CRRC_LOGIC_ENTRY: currentTs", block.timestamp);
        
        uint256 len_before = 0;
        len_before = $.validatorRewardRateCheckpoints[validatorId][token].length;
        console2.log("CRRC: valId %s, token %s, len_before_push %s", validatorId, token, len_before);

        updateRewardPerTokenForValidator($, token, validatorId);
        uint256 currentCumulativeIndex = $.validatorRewardPerTokenCumulative[validatorId][token];
        PlumeStakingStorage.RateCheckpoint memory checkpoint = PlumeStakingStorage.RateCheckpoint({
            timestamp: block.timestamp,
            rate: rate,
            cumulativeIndex: currentCumulativeIndex
        });
        $.validatorRewardRateCheckpoints[validatorId][token].push(checkpoint);
        uint256 len_after = $.validatorRewardRateCheckpoints[validatorId][token].length;
console2.log("CRRC - valId:", validatorId);
console2.log("CRRC - token:", token);
console2.log("CRRC - len_after_push:", len_after);
console2.log("CRRC - pushed timestamp:", checkpoint.timestamp);
console2.log("CRRC - pushed rate:", checkpoint.rate);
        uint256 checkpointIndex = len_after - 1;
        emit RewardRateCheckpointCreated(token, validatorId, rate, block.timestamp, checkpointIndex, currentCumulativeIndex);
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
            PlumeStakingStorage.RateCheckpoint({ timestamp: block.timestamp, rate: commissionRate, cumulativeIndex: 0 }); // cumulativeIndex is not strictly used for commission here
        $.validatorCommissionCheckpoints[validatorId].push(checkpoint);
        emit ValidatorCommissionCheckpointCreated(validatorId, commissionRate, block.timestamp);
    }

    /**
     * @notice Settles the accrued commission for a validator for all reward tokens up to the current block.timestamp,
     *         by calling `updateRewardPerTokenForValidator` which now handles commission accrual directly.
     * @param $ The PlumeStaking storage layout.
     * @param validatorId The ID of the validator.
     */
    function _settleCommissionForValidatorUpToNow(
        PlumeStakingStorage.Layout storage $,
        uint16 validatorId
    ) internal {
        console2.log("--- Enter _settleCommissionForValidatorUpToNow (Revised) ---");
        console2.log("SC_R: Timestamp:", block.timestamp);
        console2.log("SC_R: Validator ID:", validatorId);

        address[] memory rewardTokens = $.rewardTokens;

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            console2.log("SC_R: Processing Token:", token);
            // Calling updateRewardPerTokenForValidator will now also handle accruing commission.
            updateRewardPerTokenForValidator($, token, validatorId);
        }
        console2.log("--- Exit _settleCommissionForValidatorUpToNow (Revised) ---");
    }

}
