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
        console2.log("URPTFV_ENTRY: v:%s t:%s now:%s", validatorId, token, block.timestamp);
        uint256 totalStaked = $.validatorTotalStaked[validatorId];
        uint256 oldLastUpdateTime = $.validatorLastUpdateTimes[validatorId][token]; // Capture before update

        console2.log("URPTFV_STATE - validatorId:", validatorId);
        console2.log("URPTFV_STATE - token:", token);
        console2.log("URPTFV_STATE - oldLastUpdTime:", oldLastUpdateTime);
        console2.log("URPTFV_STATE - totalStaked:", totalStaked);

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
                        (totalStaked * rewardPerTokenIncrease) / REWARD_PRECISION;
                    uint256 commissionDeltaForValidator =
                        (grossRewardForValidatorThisSegment * commissionRateForSegment) / REWARD_PRECISION;

                    if (commissionDeltaForValidator > 0) {
                        uint256 previousAccrued = $.validatorAccruedCommission[validatorId][token];
                        $.validatorAccruedCommission[validatorId][token] += commissionDeltaForValidator;
                        console2.log("URPTFV LOG - validatorId:", validatorId);
                        console2.log("URPTFV LOG - token:", token);
                        console2.log("URPTFV LOG - oldLastUpdateTime:", oldLastUpdateTime);
                        console2.log("URPTFV LOG - currentTime (block.timestamp):", block.timestamp);
                        console2.log("URPTFV LOG - rewardPerTokenIncrease:", rewardPerTokenIncrease);
                        console2.log("URPTFV LOG - commissionRateForSegment:", commissionRateForSegment);
                        console2.log(
                            "URPTFV LOG - grossRewardForValidatorThisSegment:", grossRewardForValidatorThisSegment
                        );
                        console2.log("URPTFV LOG - commissionDeltaForValidator:", commissionDeltaForValidator);
                        console2.log("URPTFV LOG - previousAccrued:", previousAccrued);
                        console2.log(
                            "URPTFV LOG - newAccruedCommission:", $.validatorAccruedCommission[validatorId][token]
                        );
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
        console2.log("CRWC_ENTRY - user:", user);
        console2.log("CRWC_ENTRY - validatorId:", validatorId);
        console2.log("CRWC_ENTRY - token:", token);
        console2.log("CRWC_ENTRY - userStakedAmount:", userStakedAmount);
        updateRewardPerTokenForValidator($, token, validatorId);

        uint256 lastUserPaidCumulativeRewardPerToken = $.userValidatorRewardPerTokenPaid[user][validatorId][token];
        uint256 finalCumulativeRewardPerToken = $.validatorRewardPerTokenCumulative[validatorId][token];
        uint256 lastUserRewardUpdateTime = $.userValidatorRewardPerTokenPaidTimestamp[user][validatorId][token];

        console2.log("CRWC_STATE1 - lastPaidRPT:", lastUserPaidCumulativeRewardPerToken);
        console2.log("CRWC_STATE1 - finalRPT:", finalCumulativeRewardPerToken);
        console2.log("CRWC_STATE1 - lastUpdTime:", lastUserRewardUpdateTime);
        console2.log("CRWC_STATE1 - now:", block.timestamp);

        if (lastUserRewardUpdateTime == 0) {
            lastUserRewardUpdateTime = $.userValidatorStakeStartTime[user][validatorId];
            console2.log("CRWC_STATE2: lastUpdTime (from stake start):%s", lastUserRewardUpdateTime);
            if (lastUserRewardUpdateTime == 0 && $.userValidatorStakes[user][validatorId].staked > 0) {
                lastUserRewardUpdateTime = block.timestamp;
                console2.log("CRWC_STATE3: lastUpdTime (from current block):%s", lastUserRewardUpdateTime);
            }
        }

        if (block.timestamp <= lastUserRewardUpdateTime) {
            console2.log("CRWC_EXIT_NO_DELTA: now <= lastUpdTime");
            return (0, 0, 0);
        }

        effectiveTimeDelta = block.timestamp - lastUserRewardUpdateTime;
        console2.log("CRWC_STATE4: effectiveTimeDelta:%s", effectiveTimeDelta);

        uint256[] memory distinctTimestamps =
            getDistinctTimestamps($, validatorId, token, lastUserRewardUpdateTime, block.timestamp);
        console2.log("CRWC_STATE5: distinctTimestamps.length:%s", distinctTimestamps.length);

        if (distinctTimestamps.length < 2) {
            console2.log("CRWC_EXIT_NO_SEGMENTS: distinctTimestamps.length < 2");
            return (0, 0, 0);
        }

        uint256 currentCumulativeRewardPerToken = lastUserPaidCumulativeRewardPerToken;

        for (uint256 k = 0; k < distinctTimestamps.length - 1; ++k) {
            uint256 segmentStartTime = distinctTimestamps[k];
            uint256 actualSegmentEndTime = distinctTimestamps[k + 1];
            console2.log("CRWC_LOOP_START - index:", k);
            console2.log("CRWC_LOOP_START - segStart:", segmentStartTime);
            console2.log("CRWC_LOOP_START - segEnd:", actualSegmentEndTime);
            console2.log("CRWC_LOOP_START - currentRPT:", currentCumulativeRewardPerToken);

            if (actualSegmentEndTime <= segmentStartTime) {
                console2.log("CRWC_LOOP_SKIP [%s]: segEnd <= segStart", k);
                continue;
            }

            uint256 rptAtSegmentStart = currentCumulativeRewardPerToken;
            PlumeStakingStorage.RateCheckpoint memory rewardRateInfoAtSegmentStart =
                getEffectiveRewardRateAt($, token, validatorId, segmentStartTime);
            uint256 effectiveRewardRateForSegment = rewardRateInfoAtSegmentStart.rate;
            uint256 timeDeltaForSegment = actualSegmentEndTime - segmentStartTime;
            uint256 rewardPerTokenIncreaseForSegment = 0;
            console2.log(
                "CRWC_LOOP_CALC1 [%s]: effRate:%s, timeDeltaSeg:%s",
                k,
                effectiveRewardRateForSegment,
                timeDeltaForSegment
            );

            if (effectiveRewardRateForSegment > 0 && timeDeltaForSegment > 0) {
                rewardPerTokenIncreaseForSegment = timeDeltaForSegment * effectiveRewardRateForSegment;
            }
            uint256 rptAtSegmentEnd = rptAtSegmentStart + rewardPerTokenIncreaseForSegment;
            console2.log(
                "CRWC_LOOP_CALC2 [%s]: rptIncrSeg:%s, rptAtEnd:%s", k, rewardPerTokenIncreaseForSegment, rptAtSegmentEnd
            );

            uint256 rewardPerTokenDeltaForSegment = 0;
            if (rptAtSegmentEnd > rptAtSegmentStart) {
                rewardPerTokenDeltaForSegment = rptAtSegmentEnd - rptAtSegmentStart;
            }
            console2.log("CRWC_LOOP_CALC3 [%s]: rptDeltaSeg:%s", k, rewardPerTokenDeltaForSegment);

            if (rewardPerTokenDeltaForSegment > 0 && userStakedAmount > 0) {
                uint256 grossRewardForSegment = (userStakedAmount * rewardPerTokenDeltaForSegment) / REWARD_PRECISION;
                uint256 effectiveCommissionRate = getEffectiveCommissionRateAt($, validatorId, segmentStartTime);
                console2.log(
                    "CRWC_LOOP_CALC4 [%s]: grossRwdSeg:%s, effCommRate:%s",
                    k,
                    grossRewardForSegment,
                    effectiveCommissionRate
                );
                uint256 commissionForThisSegment = (grossRewardForSegment * effectiveCommissionRate) / REWARD_PRECISION;
                console2.log("CRWC_LOOP_CALC5 [%s]: commSeg:%s", k, commissionForThisSegment);

                // Check for underflow before subtraction
                if (grossRewardForSegment < commissionForThisSegment) {
                    console2.log(
                        "CRWC_UNDERFLOW_ALERT [%s]: grossRwdSeg (%s) < commSeg (%s)",
                        k,
                        grossRewardForSegment,
                        commissionForThisSegment
                    );
                    // This should ideally not happen with commission <= 100%
                    // If it does, it means an issue elsewhere (e.g. commissionRate > REWARD_PRECISION)
                    // For safety, can treat net reward as 0 in this case, or revert explicitly.
                    // Reverting here would give a more specific error than a generic panic 0x11.
                    // revert("Commission exceeds gross reward in segment calculation");
                }
                totalUserRewardDelta += (grossRewardForSegment - commissionForThisSegment);
                totalCommissionAmountDelta += commissionForThisSegment;
                console2.log(
                    "CRWC_LOOP_ACCUM [%s]: userDelta:%s, commDelta:%s",
                    k,
                    totalUserRewardDelta,
                    totalCommissionAmountDelta
                );
            }
            currentCumulativeRewardPerToken = rptAtSegmentEnd;
        }
        console2.log("CRWC_EXIT_SUCCESS - user:", user);
        console2.log("CRWC_EXIT_SUCCESS - validatorId:", validatorId);
        console2.log("CRWC_EXIT_SUCCESS - token:", token);
        console2.log("CRWC_EXIT_SUCCESS - totalUserRewardDelta:", totalUserRewardDelta);
        console2.log("CRWC_EXIT_SUCCESS - totalCommissionAmountDelta:", totalCommissionAmountDelta);
        console2.log("CRWC_EXIT_SUCCESS - effectiveTimeDelta:", effectiveTimeDelta);
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
        console2.log("GERRA Entry: val %s, token %s, queryTs %s", validatorId, token, timestamp);
        PlumeStakingStorage.RateCheckpoint[] storage checkpoints = $.validatorRewardRateCheckpoints[validatorId][token];
        uint256 chkCount = checkpoints.length;
        console2.log("GERRA: chkCount %s", chkCount);

        if (chkCount > 0) {
            for (uint256 i = 0; i < chkCount; ++i) {
                console2.log("GERRA - index:", i);
                console2.log("GERRA - timestamp:", checkpoints[i].timestamp);
                console2.log("GERRA - rate:", checkpoints[i].rate);
                console2.log("GERRA - cumulativeIndex:", checkpoints[i].cumulativeIndex);
            }
            uint256 idx = findRewardRateCheckpointIndexAtOrBefore($, validatorId, token, timestamp);
            console2.log("GERRA: findRewardRateCheckpointIndexAtOrBefore returned idx %s", idx);

            // Check if checkpoints[idx] is actually valid for this timestamp.
            if (idx < chkCount && checkpoints[idx].timestamp <= timestamp) {
                console2.log(
                    "GERRA: Using checkpoint idx %s: ts %s, rate %s",
                    idx,
                    checkpoints[idx].timestamp,
                    checkpoints[idx].rate
                );
                return checkpoints[idx];
            } else {
                console2.log(
                    "GERRA: Checkpoint at idx %s (ts %s) is not valid for queryTs %s or idx out of bounds.",
                    idx,
                    (idx < chkCount ? checkpoints[idx].timestamp : 9_999_999_999),
                    timestamp
                );
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
        console2.log("GECRA_ENTRY: v:%s ts:%s", validatorId, timestamp);
        PlumeStakingStorage.RateCheckpoint[] storage checkpoints = $.validatorCommissionCheckpoints[validatorId];
        uint256 chkCount = checkpoints.length;
        console2.log("GECRA_STATE: v:%s chkCount:%s", validatorId, chkCount);

        if (chkCount > 0) {
            for (uint256 i = 0; i < chkCount; ++i) {
                console2.log("GECRA_CHK - validatorId:", validatorId);
                console2.log("GECRA_CHK - index:", i);
                console2.log("GECRA_CHK - timestamp:", checkpoints[i].timestamp);
                console2.log("GECRA_CHK - rate:", checkpoints[i].rate);
            }
            uint256 idx = findCommissionCheckpointIndexAtOrBefore($, validatorId, timestamp);
            console2.log("GECRA_STATE: v:%s findCommChkIdx:%s", validatorId, idx);
            if (idx < chkCount && checkpoints[idx].timestamp <= timestamp) {
                console2.log("GECRA_RETURN_CHK: v:%s idx:%s rate:%s", validatorId, idx, checkpoints[idx].rate);
                return checkpoints[idx].rate;
            }
        }
        uint256 fallbackComm = $.validators[validatorId].commission;
        console2.log("GECRA_FALLBACK: v:%s fallbackComm:%s", validatorId, fallbackComm);
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
        // console2.log("FRRCIAOB_ENTRY: v:%s t:%s ts:%s len:%s", validatorId, token, timestamp, len); // Optional:
        // entry log
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
        // console2.log("FRRCIAOB_EXIT: v:%s ans:%s found:%s", validatorId, ans, foundSuitable);
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
        console2.log("FCCIAOB_ENTRY: v:%s ts:%s", validatorId, timestamp);
        PlumeStakingStorage.RateCheckpoint[] storage checkpoints = $.validatorCommissionCheckpoints[validatorId];
        uint256 len = checkpoints.length;
        console2.log("FCCIAOB_STATE: v:%s len:%s", validatorId, len);
        if (len == 0) {
            console2.log("FCCIAOB_EXIT_EMPTY: v:%s", validatorId);
            return 0;
        }

        uint256 low = 0;
        uint256 high = len - 1;
        uint256 ans = 0;
        bool foundSuitable = false;

        while (low <= high) {
            uint256 mid = low + (high - low) / 2;
            console2.log("FCCIAOB_LOOP - validatorId:", validatorId);
            console2.log("FCCIAOB_LOOP - low:", low);
            console2.log("FCCIAOB_LOOP - high:", high);
            console2.log("FCCIAOB_LOOP - mid:", mid);
            console2.log("FCCIAOB_LOOP - chkTs:", checkpoints[mid].timestamp);
            console2.log("FCCIAOB_LOOP - queryTimestamp:", timestamp); // Corrected log to use 'timestamp' arg
            if (checkpoints[mid].timestamp <= timestamp) {
                console2.log("FCCIAOB_LOOP - found chk at idx %s", mid);
                ans = mid;
                foundSuitable = true; // Mark that we found at least one suitable checkpoint
                low = mid + 1;
            } else {
                // checkpoints[mid].timestamp > timestamp
                console2.log("FCCIAOB_LOOP - chkTs > queryTimestamp, mid is %s", mid);
                if (mid == 0) {
                    // If the first element is already too new
                    console2.log("FCCIAOB_LOOP - mid is 0 and chkTs > queryTs, breaking");
                    break;
                }
                high = mid - 1;
            }
            console2.log("FCCIAOB_LOOP - FINISH_ITERATION");
        }
        console2.log("FCCIAOB_EXIT_FOUND: v:%s ans:%s foundSuitable:%s", validatorId, ans, foundSuitable);
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
        console2.log("CRRC_LOGIC_ENTRY: valId ", validatorId);
        console2.log("CRRC_LOGIC_ENTRY: token", token);
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
