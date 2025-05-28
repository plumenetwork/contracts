// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {
    AdminTransferFailed,
    CooldownTooShortForSlashVote,
    EmptyArray,
    InsufficientFunds,
    InvalidAmount,
    InvalidIndexRange,
    InvalidInterval,
    InvalidMaxCommissionRate,
    SlashVoteDurationTooLongForCooldown,
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
    CooldownIntervalSet,
    MaxAllowedValidatorCommissionSet,
    MaxSlashVoteDurationSet,
    MinStakeAmountSet,
    StakeInfoUpdated
} from "../lib/PlumeEvents.sol";

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
        uint256 userCooledAmountToClear = $.userValidatorCooldowns[user][slashedValidatorId].amount;

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

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            if (user != address(0)) {
                uint256 userActiveStakeToClear = $.userValidatorStakes[user][slashedValidatorId].staked;
                uint256 userCooledAmountToClear = $.userValidatorCooldowns[user][slashedValidatorId].amount;
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

                if ($.userHasStakedWithValidator[user][slashedValidatorId] || recordActuallyChangedForThisUser) {
                    PlumeValidatorLogic.removeStakerFromValidator($, user, slashedValidatorId);
                }
            }
        }
    }
    // --- END NEW ADMIN SLASH CLEANUP FUNCTION ---

}
