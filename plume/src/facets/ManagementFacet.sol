// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {
    AdminTransferFailed,
    CannotPruneAllCheckpoints,
    CooldownTooShortForSlashVote,
    EmptyArray,
    InsufficientFunds,
    InvalidAmount,
    InvalidIndexRange,
    InvalidInterval,
    InvalidMaxCommissionRate,
    InvalidPercentage,
    MaxCommissionCheckpointsExceeded,
    SlashVoteDurationExceedsCommissionTimelock,
    SlashVoteDurationTooLongForCooldown,
    TokenDoesNotExist,
    TokenAlreadyExists,
    Unauthorized,
    ValidatorDoesNotExist,
    ValidatorNotSlashed,
    ZeroAddress
} from "../lib/PlumeErrors.sol";
import {
    AdminClearedSlashedCooldown,
    AdminClearedSlashedStake,
    AdminStakeCorrection,
    AdminWithdraw,
    CommissionCheckpointsPruned,
    CooldownIntervalSet,
    MaxAllowedValidatorCommissionSet,
    MaxCommissionCheckpointsSet,
    MaxSlashVoteDurationSet,
    MaxValidatorPercentageUpdated,
    MinStakeAmountSet,
    HistoricalRewardTokenAdded,
    HistoricalRewardTokenRemoved,
    RewardRateCheckpointsPruned,
    StakeInfoUpdated,
    ValidatorCommissionSet
} from "../lib/PlumeEvents.sol";

import { PlumeRewardLogic } from "../lib/PlumeRewardLogic.sol";
import { PlumeStakingStorage } from "../lib/PlumeStakingStorage.sol";
import { PlumeValidatorLogic } from "../lib/PlumeValidatorLogic.sol";

import { OwnableStorage } from "@solidstate/access/ownable/OwnableStorage.sol";
import { DiamondBaseStorage } from "@solidstate/proxy/diamond/base/DiamondBaseStorage.sol";

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { OwnableInternal } from "@solidstate/access/ownable/OwnableInternal.sol"; // For inherited onlyOwner

import { PlumeRoles } from "../lib/PlumeRoles.sol";

import { IAccessControl } from "../interfaces/IAccessControl.sol";
import { ValidatorFacet } from "./ValidatorFacet.sol";

/**
 * @title ManagementFacet
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Facet handling administrative functions like setting parameters and managing contract funds.
 */
contract ManagementFacet is ReentrancyGuardUpgradeable, OwnableInternal {

    using SafeERC20 for IERC20;
    using Address for address payable;

    // --- Modifiers ---

    /**
     * @dev Modifier to check role using the AccessControlFacet.
     * Assumes AccessControlFacet is deployed and added to the diamond.
     */
    modifier onlyRole(
        bytes32 _role
    ) {
        if (!IAccessControl(address(this)).hasRole(_role, msg.sender)) {
            revert Unauthorized(msg.sender, _role);
        }
        _;
    }

    /**
     * @notice Update the minimum stake amount required
     * @dev Requires ADMIN_ROLE.
     * @param _minStakeAmount New minimum stake amount
     */
    function setMinStakeAmount(
        uint256 _minStakeAmount
    ) external onlyRole(PlumeRoles.ADMIN_ROLE) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        uint256 oldAmount = $.minStakeAmount;
        if (_minStakeAmount == 0) {
            revert InvalidAmount(_minStakeAmount);
        }
        $.minStakeAmount = _minStakeAmount;
        emit MinStakeAmountSet(_minStakeAmount);
    }

    /**
     * @notice Update the cooldown interval for unstaking
     * @dev Requires ADMIN_ROLE.
     * @param interval New cooldown interval in seconds
     */
    function setCooldownInterval(
        uint256 interval
    ) external onlyRole(PlumeRoles.ADMIN_ROLE) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        if (interval == 0) {
            revert InvalidInterval(interval);
        }
        // New check against maxSlashVoteDuration
        if ($.maxSlashVoteDurationInSeconds != 0 && interval <= $.maxSlashVoteDurationInSeconds) {
            revert CooldownTooShortForSlashVote(interval, $.maxSlashVoteDurationInSeconds);
        }
        $.cooldownInterval = interval;
        emit CooldownIntervalSet(interval);
    }

    // --- Admin Fund Management (Roles) ---

    /**
     * @notice Allows admin to withdraw ERC20 or native PLUME tokens from the contract balance
     * @dev Primarily for recovering accidentally sent tokens or managing excess reward funds.
     * Requires TIMELOCK_ROLE.
     * @param token Address of the token to withdraw (use PLUME address for native token)
     * @param amount Amount to withdraw
     * @param recipient Address to send the withdrawn tokens to
     */
    function adminWithdraw(
        address token,
        uint256 amount,
        address recipient
    ) external onlyRole(PlumeRoles.TIMELOCK_ROLE) nonReentrant {
        // Validate inputs
        if (token == address(0)) {
            revert ZeroAddress("token");
        }
        if (recipient == address(0)) {
            revert ZeroAddress("recipient");
        }
        if (amount == 0) {
            revert InvalidAmount(amount);
        }

        if (token == PlumeStakingStorage.PLUME_NATIVE) {
            // Native PLUME withdrawal
            uint256 balance = address(this).balance;
            if (amount > balance) {
                revert InsufficientFunds(balance, amount);
            }
            (bool success,) = payable(recipient).call{ value: amount }("");
            if (!success) {
                revert AdminTransferFailed();
            }
        } else {
            // ERC20 withdrawal
            IERC20 erc20Token = IERC20(token);
            uint256 balance = erc20Token.balanceOf(address(this));
            if (amount > balance) {
                revert InsufficientFunds(balance, amount);
            }
            erc20Token.safeTransfer(recipient, amount);
        }

        emit AdminWithdraw(token, amount, recipient);
    }

    // --- Global State Update Functions (Roles) ---

    /**
     * @notice Gets the current minimum stake amount.
     */
    function getMinStakeAmount() external view returns (uint256) {
        return PlumeStakingStorage.layout().minStakeAmount;
    }

    /**
     * @notice Gets the current cooldown interval.
     */
    function getCooldownInterval() external view returns (uint256) {
        return PlumeStakingStorage.layout().cooldownInterval;
    }

    /**
     * @notice Set the maximum duration for slashing votes (ADMIN_ROLE only).
     * @param duration The new duration in seconds.
     */
    function setMaxSlashVoteDuration(
        uint256 duration
    ) external onlyRole(PlumeRoles.ADMIN_ROLE) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        if (duration == 0) {
            revert InvalidInterval(duration);
        }
        // New check against cooldownInterval
        if ($.cooldownInterval != 0 && duration >= $.cooldownInterval) {
            revert SlashVoteDurationTooLongForCooldown(duration, $.cooldownInterval);
        }

        // NEW CHECK: Ensure slash duration is shorter than commission claim timelock
        if (duration >= PlumeStakingStorage.COMMISSION_CLAIM_TIMELOCK) {
            revert SlashVoteDurationExceedsCommissionTimelock(duration, PlumeStakingStorage.COMMISSION_CLAIM_TIMELOCK);
        }

        $.maxSlashVoteDurationInSeconds = duration;
        emit MaxSlashVoteDurationSet(duration);
    }

    /**
     * @notice Set the system-wide maximum allowed commission rate for any validator.
     * @dev Requires TIMELOCK_ROLE. Max rate cannot exceed 50%.
     * @param newMaxRate The new maximum commission rate (e.g., 50e16 for 50%).
     */
    function setMaxAllowedValidatorCommission(
        uint256 newMaxRate
    ) external onlyRole(PlumeRoles.TIMELOCK_ROLE) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        // Max rate cannot be more than 50% (REWARD_PRECISION / 2)
        if (newMaxRate > PlumeStakingStorage.REWARD_PRECISION / 2) {
            revert InvalidMaxCommissionRate(newMaxRate, PlumeStakingStorage.REWARD_PRECISION / 2);
        }

        uint256 oldMaxRate = $.maxAllowedValidatorCommission;
        $.maxAllowedValidatorCommission = newMaxRate;

        emit MaxAllowedValidatorCommissionSet(oldMaxRate, newMaxRate);

        // Enforce the new max commission on all existing validators
        uint16[] memory validatorIds = $.validatorIds;
        for (uint256 i = 0; i < validatorIds.length; i++) {
            uint16 validatorId = validatorIds[i];
            PlumeStakingStorage.ValidatorInfo storage validator = $.validators[validatorId];

            if (validator.commission > newMaxRate) {
                uint256 oldCommission = validator.commission;

                // Settle commissions accrued with the old rate up to this point.
                PlumeRewardLogic._settleCommissionForValidatorUpToNow($, validatorId);

                // Update the validator's commission rate to the new max rate.
                validator.commission = newMaxRate;

                // Create a checkpoint for the new commission rate.
                PlumeRewardLogic.createCommissionRateCheckpoint($, validatorId, newMaxRate);

                emit ValidatorCommissionSet(validatorId, oldCommission, newMaxRate);
            }
        }
    }

    /**
     * @notice Sets the maximum number of commission checkpoints a single validator can have.
     * @dev Protects against gas-exhaustion griefing attacks. Requires ADMIN_ROLE.
     * @param newLimit The new maximum number of checkpoints.
     */
    function setMaxCommissionCheckpoints(
        uint16 newLimit
    ) external onlyRole(PlumeRoles.ADMIN_ROLE) {
        if (newLimit < 10) {
            // Enforce a minimum reasonable limit
            revert InvalidAmount(newLimit);
        }
        PlumeStakingStorage.layout().maxCommissionCheckpoints = newLimit;
        emit MaxCommissionCheckpointsSet(newLimit);
    }

    /**
     * @notice Sets the maximum percentage of total stake a single validator can hold.
     * @dev A value of 0 disables the check. Requires ADMIN_ROLE.
     * @param newPercentage The new percentage in basis points (e.g., 2000 for 20%).
     */
    function setMaxValidatorPercentage(
        uint256 newPercentage
    ) external onlyRole(PlumeRoles.ADMIN_ROLE) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        // A percentage must not exceed 100% (10,000 basis points).
        if (newPercentage > 10_000) {
            revert InvalidPercentage(newPercentage);
        }

        uint256 oldPercentage = $.maxValidatorPercentage;
        $.maxValidatorPercentage = newPercentage;

        emit MaxValidatorPercentageUpdated(oldPercentage, newPercentage);
    }

    // --- Checkpoint Pruning Functions ---

    /**
     * @notice Admin function to prune old commission checkpoints for a validator.
     * @dev DANGEROUS: This operation is gas-intensive and can break reward calculations if checkpoints
     *      are removed that are still needed by users who have not claimed rewards recently.
     *      The administrator is responsible for ensuring this is called safely.
     *      Removes the `count` oldest checkpoints. Requires ADMIN_ROLE.
     * @param validatorId The ID of the validator whose checkpoints will be pruned.
     * @param count The number of old checkpoints to remove.
     */
    function pruneCommissionCheckpoints(uint16 validatorId, uint256 count) external onlyRole(PlumeRoles.ADMIN_ROLE) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }
        if (count == 0) {
            revert InvalidAmount(count);
        }

        PlumeStakingStorage.RateCheckpoint[] storage checkpoints = $.validatorCommissionCheckpoints[validatorId];
        uint256 len = checkpoints.length;

        if (count >= len) {
            // Cannot remove all checkpoints. At least one must remain to define the current rate.
            revert CannotPruneAllCheckpoints();
        }

        // This is a gas-intensive operation. It shifts all elements to the left.
        for (uint256 i = 0; i < len - count; i++) {
            checkpoints[i] = checkpoints[i + count];
        }

        // Pop the now-duplicate elements from the end.
        for (uint256 i = 0; i < count; i++) {
            checkpoints.pop();
        }

        emit CommissionCheckpointsPruned(validatorId, count);
    }

    /**
     * @notice Admin function to prune old reward rate checkpoints for a validator and token.
     * @dev DANGEROUS: Similar to pruneCommissionCheckpoints, this is gas-intensive and can break
     *      reward calculations. Use with extreme caution. Requires ADMIN_ROLE.
     * @param validatorId The ID of the validator.
     * @param token The address of the reward token.
     * @param count The number of old checkpoints to remove.
     */
    function pruneRewardRateCheckpoints(
        uint16 validatorId,
        address token,
        uint256 count
    ) external onlyRole(PlumeRoles.ADMIN_ROLE) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }
        // Allow pruning for both active and removed reward tokens, as both may have legacy checkpoints.
        if (!$.isRewardToken[token] && $.tokenAdditionTimestamps[token] == 0) {
            revert TokenDoesNotExist(token);
        }
        if (count == 0) {
            revert InvalidAmount(count);
        }

        PlumeStakingStorage.RateCheckpoint[] storage checkpoints = $.validatorRewardRateCheckpoints[validatorId][token];
        uint256 len = checkpoints.length;

        if (count >= len) {
            revert CannotPruneAllCheckpoints();
        }

        for (uint256 i = 0; i < len - count; i++) {
            checkpoints[i] = checkpoints[i + count];
        }

        for (uint256 i = 0; i < count; i++) {
            checkpoints.pop();
        }

        emit RewardRateCheckpointsPruned(validatorId, token, count);
    }

    // --- NEW ADMIN SLASH CLEANUP FUNCTION ---
    /**
     * @notice Admin function to clear a user's stale records associated with a slashed validator.
     * @dev This is used because a 100% slash means the user has no funds to recover via a user-facing function.
     *      This function cleans up their internal tracking for that validator.
     *      Requires caller to have ADMIN_ROLE.
     * @param user The address of the user whose records need cleanup.
     * @param slashedValidatorId The ID of the validator that was slashed.
     */
    function adminClearValidatorRecord(
        address user,
        uint16 slashedValidatorId
    ) external onlyRole(PlumeRoles.ADMIN_ROLE) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        if (user == address(0)) {
            revert ZeroAddress("user");
        }
        if (!$.validatorExists[slashedValidatorId]) {
            revert ValidatorDoesNotExist(slashedValidatorId);
        }
        if (!$.validators[slashedValidatorId].slashed) {
            revert ValidatorNotSlashed(slashedValidatorId);
        }

        uint256 userActiveStakeToClear = $.userValidatorStakes[user][slashedValidatorId].staked;
        PlumeStakingStorage.CooldownEntry storage cooldownEntry = $.userValidatorCooldowns[user][slashedValidatorId];
        uint256 userCooledAmountToClear = cooldownEntry.amount;

        bool recordChanged = false;

        if (userActiveStakeToClear > 0) {
            $.userValidatorStakes[user][slashedValidatorId].staked = 0;
            // Decrement user's global stake
            if ($.stakeInfo[user].staked >= userActiveStakeToClear) {
                $.stakeInfo[user].staked -= userActiveStakeToClear;
            } else {
                $.stakeInfo[user].staked = 0; // Should not happen if state is consistent
            }
            emit AdminClearedSlashedStake(user, slashedValidatorId, userActiveStakeToClear);
            recordChanged = true;
        }

        if (userCooledAmountToClear > 0) {
            // This function should only clear funds considered lost to the slash.
            // A cooldown is lost if it did NOT mature before the slash timestamp.
            uint256 slashTimestamp = $.validators[slashedValidatorId].slashedAtTimestamp;
            bool cooldownIsLost = cooldownEntry.cooldownEndTime >= slashTimestamp;

            if (cooldownIsLost) {
                delete $.userValidatorCooldowns[user][slashedValidatorId];
                // Decrement user's global cooled amount
                if ($.stakeInfo[user].cooled >= userCooledAmountToClear) {
                    $.stakeInfo[user].cooled -= userCooledAmountToClear;
                } else {
                    $.stakeInfo[user].cooled = 0; // Should not happen
                }
                emit AdminClearedSlashedCooldown(user, slashedValidatorId, userCooledAmountToClear);
                recordChanged = true;
            }
        }

        if ($.userHasStakedWithValidator[user][slashedValidatorId] || recordChanged) {
            PlumeValidatorLogic.removeStakerFromValidator($, user, slashedValidatorId);
        }
    }

    /**
     * @notice Admin function to clear stale records for multiple users associated with a single slashed validator.
     * @dev This iterates through a list of users and calls the single-user cleanup logic.
     *      Due to gas limits, this should be called with reasonably sized batches of users.
     *      Requires caller to have ADMIN_ROLE.
     * @param users Array of user addresses whose records need cleanup for the given validator.
     * @param slashedValidatorId The ID of the validator that was slashed.
     */
    function adminBatchClearValidatorRecords(
        address[] calldata users,
        uint16 slashedValidatorId
    ) external onlyRole(PlumeRoles.ADMIN_ROLE) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        if (!$.validatorExists[slashedValidatorId]) {
            revert ValidatorDoesNotExist(slashedValidatorId);
        }
        if (!$.validators[slashedValidatorId].slashed) {
            revert ValidatorNotSlashed(slashedValidatorId);
        }
        if (users.length == 0) {
            revert EmptyArray();
        }

        uint256 slashTimestamp = $.validators[slashedValidatorId].slashedAtTimestamp;

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            if (user != address(0)) {
                uint256 userActiveStakeToClear = $.userValidatorStakes[user][slashedValidatorId].staked;
                PlumeStakingStorage.CooldownEntry storage cooldownEntry =
                    $.userValidatorCooldowns[user][slashedValidatorId];
                uint256 userCooledAmountToClear = cooldownEntry.amount;
                bool recordActuallyChangedForThisUser = false;

                if (userActiveStakeToClear > 0) {
                    $.userValidatorStakes[user][slashedValidatorId].staked = 0;
                    // Decrement user's global stake
                    if ($.stakeInfo[user].staked >= userActiveStakeToClear) {
                        $.stakeInfo[user].staked -= userActiveStakeToClear;
                    } else {
                        $.stakeInfo[user].staked = 0;
                    }
                    emit AdminClearedSlashedStake(user, slashedValidatorId, userActiveStakeToClear);
                    recordActuallyChangedForThisUser = true;
                }

                if (userCooledAmountToClear > 0) {
                    bool cooldownIsLost = cooldownEntry.cooldownEndTime >= slashTimestamp;
                    if (cooldownIsLost) {
                        delete $.userValidatorCooldowns[user][slashedValidatorId];
                        // Decrement user's global cooled amount
                        if ($.stakeInfo[user].cooled >= userCooledAmountToClear) {
                            $.stakeInfo[user].cooled -= userCooledAmountToClear;
                        } else {
                            $.stakeInfo[user].cooled = 0;
                        }
                        emit AdminClearedSlashedCooldown(user, slashedValidatorId, userCooledAmountToClear);
                        recordActuallyChangedForThisUser = true;
                    }
                }

                if ($.userHasStakedWithValidator[user][slashedValidatorId] || recordActuallyChangedForThisUser) {
                    PlumeValidatorLogic.removeStakerFromValidator($, user, slashedValidatorId);
                }
            }
        }
    }
    // --- END NEW ADMIN SLASH CLEANUP FUNCTION ---

    // --- HISTORICAL REWARD TOKEN MANAGEMENT ---

    /**
     * @notice Admin function to manually add a token to the historical rewards list.
     * @dev This is for administrative correction, e.g., after a data migration. It does not make
     *      the token an *active* reward token. Requires ADMIN_ROLE.
     * @param token The address of the token to add to the historical list.
     */
    function addHistoricalRewardToken(address token) external onlyRole(PlumeRoles.ADMIN_ROLE) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        if (token == address(0)) {
            revert ZeroAddress("token");
        }
        if ($.isHistoricalRewardToken[token]) {
            // Revert if it's already in the historical list to prevent duplicates.
            revert TokenAlreadyExists();
        }

        $.isHistoricalRewardToken[token] = true;
        $.historicalRewardTokens.push(token);

        emit HistoricalRewardTokenAdded(token);
    }

    /**
     * @notice Admin function to manually remove a token from the historical rewards list.
     * @dev DANGEROUS: This operation can lead to PERMANENT LOSS OF USER FUNDS if there are any
     *      unclaimed or unsettled rewards for this token. The responsibility for ensuring safety
     *      lies entirely with the caller of this function. Requires ADMIN_ROLE.
     * @param token The address of the token to remove from the historical list.
     */
    function removeHistoricalRewardToken(address token) external onlyRole(PlumeRoles.ADMIN_ROLE) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        if (token == address(0)) {
            revert ZeroAddress("token");
        }

        // CRITICAL CHECK: The token MUST NOT be an active reward token.
        // It must be "soft removed" via the standard `removeRewardToken` function first.
        if ($.isRewardToken[token]) {
            revert TokenAlreadyExists(); // Re-using error for "token is currently active"
        }

        // Find and remove the token from the historical array
        address[] storage historicalTokens = $.historicalRewardTokens;
        uint256 tokenIndex = type(uint256).max;
        for (uint256 i = 0; i < historicalTokens.length; i++) {
            if (historicalTokens[i] == token) {
                tokenIndex = i;
                break;
            }
        }

        // Revert if the token was not found in the historical list
        if (tokenIndex == type(uint256).max) {
            revert TokenDoesNotExist(token);
        }

        // Swap and pop to remove the element
        historicalTokens[tokenIndex] = historicalTokens[historicalTokens.length - 1];
        historicalTokens.pop();

        // Update the mapping
        $.isHistoricalRewardToken[token] = false;

        emit HistoricalRewardTokenRemoved(token);
    }

    // --- HISTORICAL REWARD TOKEN VIEW FUNCTIONS ---

    /**
     * @notice Checks if a token has ever been a reward token.
     * @param token The address of the token to check.
     * @return True if the token is in the historical list, false otherwise.
     */
    function isHistoricalRewardToken(address token) external view returns (bool) {
        return PlumeStakingStorage.layout().isHistoricalRewardToken[token];
    }

    /**
     * @notice Returns the complete list of all tokens that have ever been reward tokens.
     * @return An array of token addresses.
     */
    function getHistoricalRewardTokens() external view returns (address[] memory) {
        return PlumeStakingStorage.layout().historicalRewardTokens;
    }

    // --- MIGRATION-SPECIFIC FUNCTION ---

    /**
     * @notice Admin function to manually create a historical reward rate checkpoint for a validator.
     * @dev DANGEROUS: This is a special-purpose migration function. It bypasses normal settlement logic
     *      and should only be used to back-fill historical data during an upgrade.
     *      Requires ADMIN_ROLE.
     * @param validatorId The ID of the validator to create the checkpoint for.
     * @param token The address of the reward token.
     * @param timestamp The historical timestamp for the checkpoint.
     * @param rate The historical rate for the checkpoint.
     */
    function adminCreateHistoricalRewardCheckpoint(
        uint16 validatorId,
        address token,
        uint256 timestamp,
        uint256 rate
    ) external onlyRole(PlumeRoles.ADMIN_ROLE) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        // Basic validation
        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }
        if (!$.isHistoricalRewardToken[token]) {
            // Check historical list, as this is for migrating historical data
            revert TokenDoesNotExist(token);
        }

        // Directly create the checkpoint. We assume cumulativeIndex is not needed for this migration,
        // as the new reward logic will calculate it based on this new baseline.
        PlumeStakingStorage.RateCheckpoint memory checkpoint = PlumeStakingStorage.RateCheckpoint({
            timestamp: timestamp,
            rate: rate,
            cumulativeIndex: 0 // Explicitly set to 0 for migrated checkpoints
         });

        $.validatorRewardRateCheckpoints[validatorId][token].push(checkpoint);

        // Note: No event is emitted here as this is a background migration action.
    }

    /**
     * @notice Admin function to manually set the addition timestamp for a historical token.
     * @dev DANGEROUS: This is a special-purpose migration function intended to be used with
     *      `adminCreateHistoricalRewardCheckpoint`. It should only be used to back-fill
     *      historical data during an upgrade. Requires ADMIN_ROLE.
     * @param token The address of the historical reward token.
     * @param timestamp The historical timestamp when the token was originally added.
     */
    function adminSetTokenAdditionTimestamp(
        address token,
        uint256 timestamp
    ) external onlyRole(PlumeRoles.ADMIN_ROLE) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        // Basic validation
        if (token == address(0)) {
            revert ZeroAddress("token");
        }
        if (timestamp == 0) {
            revert InvalidAmount(timestamp);
        }
        if (!$.isHistoricalRewardToken[token]) {
            revert TokenDoesNotExist(token);
        }

        // Set the timestamp.
        $.tokenAdditionTimestamps[token] = timestamp;

        // No event is emitted as this is a background migration action.
    }
}
