// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {
    CooldownNotComplete,
    CooldownPeriodNotEnded,
    ExceedsValidatorCapacity,
    InsufficientCooldownBalance,
    InsufficientCooledAndParkedBalance,
    InvalidAmount,
    NativeTransferFailed,
    NoActiveStake,
    NoRewardsToRestake,
    NoWithdrawableBalanceToRestake,
    NoWithdrawableBalanceToRestake,
    StakeAmountTooSmall,
    TokenDoesNotExist,
    TooManyStakers,
    TransferError,
    ValidatorCapacityExceeded,
    ValidatorDoesNotExist,
    ValidatorInactive,
    ValidatorNotActive,
    ValidatorPercentageExceeded,
    ZeroAddress,
    ZeroRecipientAddress
} from "../lib/PlumeErrors.sol";
import { CooldownStarted } from "../lib/PlumeEvents.sol";
import { Staked } from "../lib/PlumeEvents.sol";
import { StakedOnBehalf } from "../lib/PlumeEvents.sol";
import { Unstaked } from "../lib/PlumeEvents.sol";
import { Withdrawn } from "../lib/PlumeEvents.sol";
import { RewardsRestaked } from "../lib/PlumeEvents.sol";
import { ParkedRestaked } from "../lib/PlumeEvents.sol";
import { RewardClaimedFromValidator } from "../lib/PlumeEvents.sol";

import { PlumeRewardLogic } from "../lib/PlumeRewardLogic.sol";
import { PlumeStakingStorage } from "../lib/PlumeStakingStorage.sol";
import { PlumeValidatorLogic } from "../lib/PlumeValidatorLogic.sol";
import { RewardsFacet } from "./RewardsFacet.sol";

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { DiamondBaseStorage } from "@solidstate/proxy/diamond/base/DiamondBaseStorage.sol";
import { console2 } from "forge-std/Test.sol";

/**
 * @title StakingFacet
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Facet containing core user staking, unstaking, and withdrawal functions.
 */
contract StakingFacet is ReentrancyGuardUpgradeable {

    using SafeERC20 for IERC20;
    using Address for address payable;

    // Define PLUME_NATIVE constant
    address internal constant PLUME_NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // Constants moved from Base - needed here
    uint256 internal constant REWARD_PRECISION = 1e18;

    // --- Storage Access ---
    bytes32 internal constant PLUME_STORAGE_POSITION = keccak256("plume.storage.PlumeStaking");

    function _getPlumeStorage() internal pure returns (PlumeStakingStorage.Layout storage $) {
        bytes32 position = PLUME_STORAGE_POSITION;
        assembly {
            $.slot := position
        }
    }

    /**
     * @notice Stake PLUME to a specific validator using only wallet funds
     * @param validatorId ID of the validator to stake to
     */
    function stake(
        uint16 validatorId
    ) external payable returns (uint256) {
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();

        uint256 stakeAmount = msg.value;

        if (stakeAmount < $.minStakeAmount) {
            revert StakeAmountTooSmall(stakeAmount, $.minStakeAmount);
        }
        if (!$.validatorExists[validatorId]) {
            revert ValidatorNotActive(validatorId);
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
     * @notice Restake PLUME to a specific validator, using funds only from cooling and parked balances
     * @param validatorId ID of the validator to stake to
     * @param amount Amount of tokens to restake
     */
    function restake(uint16 validatorId, uint256 amount) external returns (uint256) {
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();
        PlumeStakingStorage.StakeInfo storage info = $.stakeInfo[msg.sender]; // Global info

        if (amount == 0) {
            revert InvalidAmount(amount);
        }
        if (!$.validatorExists[validatorId]) {
            revert ValidatorNotActive(validatorId);
        }

        // Check available balances
        uint256 availableCooled = info.cooled;
        uint256 availableParked = info.parked;
        uint256 totalAvailable = availableCooled + availableParked;

        if (amount > totalAvailable) {
            revert InsufficientCooledAndParkedBalance(totalAvailable, amount);
        }

        // Determine amounts from each source
        uint256 fromCooled = amount <= availableCooled ? amount : availableCooled;
        uint256 fromParked = amount - fromCooled;

        // --- Update State ---
        // 1. Decrease source balances
        if (fromCooled > 0) {
            info.cooled -= fromCooled;
            if ($.totalCooling >= fromCooled) {
                $.totalCooling -= fromCooled;
            } else {
                $.totalCooling = 0;
            }
            // Reset cooldown only if cooled balance becomes zero AFTER this operation
            if (info.cooled == 0) {
                info.cooldownEnd = 0;
            }
        }
        if (fromParked > 0) {
            info.parked -= fromParked;
            if ($.totalWithdrawable >= fromParked) {
                $.totalWithdrawable -= fromParked;
            } else {
                $.totalWithdrawable = 0;
            }
        }

        // 2. Increase staked amounts
        info.staked += amount; // User's global staked
        $.userValidatorStakes[msg.sender][validatorId].staked += amount; // User's stake FOR THIS VALIDATOR
        $.validators[validatorId].delegatedAmount += amount; // Validator's delegated amount
        $.validatorTotalStaked[validatorId] += amount; // Validator's total staked
        $.totalStaked += amount; // Global total staked

        // Add staker to validator list if not already there
        PlumeValidatorLogic.addStakerToValidator($, msg.sender, validatorId);

        // --- Checks ---
        // Check if exceeding validator capacity
        uint256 newDelegatedAmount = $.validators[validatorId].delegatedAmount;
        uint256 maxCapacity = $.validators[validatorId].maxCapacity;
        if (maxCapacity > 0 && newDelegatedAmount > maxCapacity) {
            revert ExceedsValidatorCapacity(validatorId, newDelegatedAmount, maxCapacity, amount);
        }

        // Check if exceeding validator percentage limit
        if ($.totalStaked > 0 && $.maxValidatorPercentage > 0) {
            uint256 validatorPercentage = (newDelegatedAmount * 10_000) / $.totalStaked;
            if (validatorPercentage > $.maxValidatorPercentage) {
                revert ValidatorPercentageExceeded();
            }
        }

        // --- Events ---
        // Emit stake event with details
        emit Staked(
            msg.sender,
            validatorId,
            amount, // Total amount restaked
            fromCooled, // Amount from cooled
            fromParked, // Amount from parked
            amount // Treat the restaked amount as newly active stake
        );

        return amount;
    }

    /**
     * @notice Unstake PLUME from a specific validator (full amount)
     * @param validatorId ID of the validator to unstake from
     * @return amount Amount of PLUME unstaked
     */
    function unstake(
        uint16 validatorId
    ) external returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();
        PlumeStakingStorage.StakeInfo storage info = $.userValidatorStakes[msg.sender][validatorId];

        if (info.staked > 0) {
            // Call internal _unstake which is now part of this facet
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
        return _unstake(validatorId, amount);
    }

    /**
     * @notice Internal implementation of unstake logic
     * @param validatorId ID of the validator to unstake from
     * @param amount Amount of PLUME to unstake
     * @return amountUnstaked The amount actually unstaked
     */
    function _unstake(uint16 validatorId, uint256 amount) internal returns (uint256 amountUnstaked) {
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();

        // Verify validator exists
        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }

        PlumeStakingStorage.StakeInfo storage info = $.userValidatorStakes[msg.sender][validatorId];
        PlumeStakingStorage.StakeInfo storage globalInfo = $.stakeInfo[msg.sender];

        if (info.staked == 0) {
            revert NoActiveStake();
        }

        if (amount == 0) {
            revert InvalidAmount(amount);
        }

        amountUnstaked = amount > info.staked ? info.staked : amount;

        // Update rewards using library
        PlumeRewardLogic.updateRewardsForValidator($, msg.sender, validatorId);

        // Update user's staked amount for this validator
        info.staked -= amountUnstaked;

        // Update global stake info
        globalInfo.staked -= amountUnstaked;

        // Update validator's delegated amount
        $.validators[validatorId].delegatedAmount -= amountUnstaked;

        // Update total staked amounts
        $.validatorTotalStaked[validatorId] -= amountUnstaked;
        $.totalStaked -= amountUnstaked;

        // Handle cooling period
        if (globalInfo.cooldownEnd != 0 && block.timestamp < globalInfo.cooldownEnd) {
            globalInfo.cooled += amountUnstaked;
            globalInfo.cooldownEnd = block.timestamp + $.cooldownInterval;
        } else {
            globalInfo.cooled = amountUnstaked;
            globalInfo.cooldownEnd = block.timestamp + $.cooldownInterval;
        }

        // Update validator-specific cooling totals - No, this seems specific to validator?
        // $.validatorTotalCooling[validatorId] += amountUnstaked; // Let's comment this out for now. Seems validator
        // specific.
        $.totalCooling += amountUnstaked; // Global total cooling is needed

        // If the user's stake with this validator is now zero, remove them from the validator's staker list
        if (info.staked == 0) {
            PlumeValidatorLogic.removeStakerFromValidator($, msg.sender, validatorId);
        }

        emit CooldownStarted(msg.sender, validatorId, amountUnstaked, globalInfo.cooldownEnd);
        emit Unstaked(msg.sender, validatorId, amountUnstaked);

        return amountUnstaked;
    }

    /**
     * @notice Withdraw PLUME that has completed the cooldown period
     * @return amount Amount of PLUME withdrawn
     */
    function withdraw() external nonReentrant returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();
        PlumeStakingStorage.StakeInfo storage info = $.stakeInfo[msg.sender];

        amount = info.parked;
        if (info.cooled > 0 && info.cooldownEnd <= block.timestamp) {
            uint256 cooledAmount = info.cooled; // Store before zeroing
            amount += cooledAmount;
            info.cooled = 0;

            // Need to adjust totalCooling if it exists and is accurate
            if ($.totalCooling >= cooledAmount) {
                $.totalCooling -= cooledAmount;
            } else {
                $.totalCooling = 0; // Avoid underflow
            }
            // Reset cooldown end time only if cooled amount becomes zero
            if (info.cooled == 0) {
                info.cooldownEnd = 0;
            }
        }

        if (amount == 0) {
            revert InvalidAmount(amount);
        }

        info.parked = 0;
        info.lastUpdateTimestamp = block.timestamp;

        // Update total withdrawable amount
        if ($.totalWithdrawable >= amount) {
            $.totalWithdrawable -= amount;
        } else {
            $.totalWithdrawable = 0;
        }

        // Transfer PLUME to user
        (bool success,) = payable(msg.sender).call{ value: amount }("");
        if (!success) {
            revert NativeTransferFailed();
        }

        emit Withdrawn(msg.sender, amount);
        return amount;
    }

    /**
     * @notice Stake PLUME to a specific validator on behalf of another user
     * @param validatorId ID of the validator to stake to
     * @param staker Address of the staker to stake on behalf of
     * @return Amount of PLUME staked
     */
    function stakeOnBehalf(uint16 validatorId, address staker) external payable returns (uint256) {
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();

        uint256 stakeAmount = msg.value;

        if (stakeAmount < $.minStakeAmount) {
            revert StakeAmountTooSmall(stakeAmount, $.minStakeAmount);
        }
        if (!$.validatorExists[validatorId]) {
            revert ValidatorNotActive(validatorId);
        }
        if (staker == address(0)) {
            revert ZeroRecipientAddress();
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
     *         to a specific validator.
     * @param validatorId ID of the validator to stake the rewards to.
     * @return amountRestaked The total amount of pending rewards successfully restaked.
     */
    function restakeRewards( // Kept original name, implement logic based on old function
        uint16 validatorId
    ) external nonReentrant returns (uint256 amountRestaked) {
        // Added nonReentrant, changed return name
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();

        // Verify target validator exists and is active
        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId); // Use correct error
        }
        PlumeStakingStorage.ValidatorInfo storage targetValidator = $.validators[validatorId];
        if (!targetValidator.active) {
            revert ValidatorInactive(validatorId); // Use correct error
        }

        // Native token is represented by PLUME_NATIVE constant
        address token = PLUME_NATIVE;

        // Check if PLUME_NATIVE is actually configured as a reward token
        if (!$.isRewardToken[token]) {
            revert TokenDoesNotExist(token); // Or specific error like "NativeTokenNotReward"
        }

        // Calculate total pending native rewards across all validators
        amountRestaked = 0;
        uint16[] memory userValidators = $.userValidators[msg.sender];

        for (uint256 i = 0; i < userValidators.length; i++) {
            uint16 userValidatorId = userValidators[i];

            // Calculate earned rewards for this specific validator by calling the public wrapper
            // Note: This requires casting the diamond proxy address to RewardsFacet
            uint256 validatorReward =
                RewardsFacet(payable(address(this))).getPendingRewardForValidator(msg.sender, userValidatorId, token);

            if (validatorReward > 0) {
                amountRestaked += validatorReward;

                // Update internal reward states as if claimed
                // This ensures reward-per-token tracking is current before zeroing
                PlumeRewardLogic.updateRewardsForValidator($, msg.sender, userValidatorId);

                // Reset rewards for this validator/token
                $.userRewards[msg.sender][userValidatorId][token] = 0;

                // Update total claimable (decrease)
                if ($.totalClaimableByToken[token] >= validatorReward) {
                    $.totalClaimableByToken[token] -= validatorReward;
                } else {
                    $.totalClaimableByToken[token] = 0;
                }

                // Emit event indicating reward was 'claimed' internally for restaking
                emit RewardClaimedFromValidator(msg.sender, token, userValidatorId, validatorReward);
            }
        }

        // Check if any rewards were found
        if (amountRestaked == 0) {
            revert NoRewardsToRestake(); // Use original error
        }

        // --- Update Stake State ---
        PlumeStakingStorage.StakeInfo storage info = $.stakeInfo[msg.sender]; // Global info

        // Increase staked amounts
        info.staked += amountRestaked; // User's global staked
        $.userValidatorStakes[msg.sender][validatorId].staked += amountRestaked; // User's stake FOR THIS VALIDATOR
        targetValidator.delegatedAmount += amountRestaked; // Validator's delegated amount
        $.validatorTotalStaked[validatorId] += amountRestaked; // Validator's total staked
        $.totalStaked += amountRestaked; // Global total staked

        // Add staker relationship if needed
        PlumeValidatorLogic.addStakerToValidator($, msg.sender, validatorId);

        // --- Checks (copied from stake) ---
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

        // --- Events ---
        // Emit stake event - specifying that the amount came from pending rewards
        emit Staked(
            msg.sender,
            validatorId,
            amountRestaked, // Total amount added to stake
            0, // fromCooled
            0, // fromParked
            amountRestaked // Amount came from pending rewards
        );

        // Emit the specific restake event
        emit RewardsRestaked(msg.sender, validatorId, amountRestaked);

        return amountRestaked;
    }

    // --- View Functions ---

    /**
     * @notice Returns the amount of PLUME currently staked by the caller
     */
    function amountStaked() external view returns (uint256 amount) {
        return _getPlumeStorage().stakeInfo[msg.sender].staked;
    }

    /**
     * @notice Returns the amount of PLUME currently in cooling period for the caller
     */
    function amountCooling() external view returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();
        PlumeStakingStorage.StakeInfo storage info = $.stakeInfo[msg.sender];

        // If cooldown has ended, return 0
        if (info.cooldownEnd != 0 && info.cooldownEnd <= block.timestamp) {
            return 0;
        }

        return info.cooled; // Return cooled amount if cooldown is active or not started
    }

    /**
     * @notice Returns the amount of PLUME that is withdrawable for the caller
     */
    function amountWithdrawable() external view returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();
        PlumeStakingStorage.StakeInfo storage info = $.stakeInfo[msg.sender];
        amount = info.parked;
        if (info.cooldownEnd != 0 && info.cooldownEnd <= block.timestamp) {
            amount += info.cooled;
        }
        return amount;
    }

    /**
     * @notice Get the cooldown end date for the caller
     * @return timestamp Time when the cooldown period ends (0 if no active cooldown)
     */
    function cooldownEndDate() external view returns (uint256 timestamp) {
        return _getPlumeStorage().stakeInfo[msg.sender].cooldownEnd;
    }

    /**
     * @notice Get staking information for a user (global stake info)
     */
    function stakeInfo(
        address user
    ) external view returns (PlumeStakingStorage.StakeInfo memory) {
        return _getPlumeStorage().stakeInfo[user];
    }

    /**
     * @notice Get the total amount of PLUME staked in the contract.
     * @return amount Total amount of PLUME staked.
     */
    function totalAmountStaked() external view returns (uint256 amount) {
        return _getPlumeStorage().totalStaked;
    }

    /**
     * @notice Get the total amount of PLUME cooling in the contract.
     * @return amount Total amount of PLUME cooling.
     */
    function totalAmountCooling() external view returns (uint256 amount) {
        return _getPlumeStorage().totalCooling;
    }

    /**
     * @notice Get the total amount of PLUME withdrawable in the contract.
     * @return amount Total amount of PLUME withdrawable.
     */
    function totalAmountWithdrawable() external view returns (uint256 amount) {
        return _getPlumeStorage().totalWithdrawable;
    }

    /**
     * @notice Get the total amount of a specific token claimable across all users.
     * @param token Address of the token to check.
     * @return amount Total amount of the token claimable.
     */
    function totalAmountClaimable(
        address token
    ) external view returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();

        // Check if token is a reward token using the mapping
        require($.isRewardToken[token], "Token is not a reward token");

        // Return the total claimable amount
        return $.totalClaimableByToken[token];
    }

    // --- NEW VIEW FUNCTION ---
    /**
     * @notice Get the staked amount for a specific user on a specific validator.
     * @param user The address of the user.
     * @param validatorId The ID of the validator.
     * @return The staked amount.
     */
    function getUserValidatorStake(address user, uint16 validatorId) external view returns (uint256) {
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();
        return $.userValidatorStakes[user][validatorId].staked;
    }
    // --- END NEW VIEW FUNCTION ---

    // --- Internal Helper Functions ---

}
