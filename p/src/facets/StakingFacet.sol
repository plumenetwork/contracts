// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {
    CooldownNotComplete,
    CooldownPeriodNotEnded,
    InvalidAmount,
    NativeTransferFailed,
    NoActiveStake,
    TokenDoesNotExist,
    TooManyStakers,
    TransferError,
    ValidatorCapacityExceeded,
    ValidatorDoesNotExist,
    ValidatorInactive,
    ZeroAddress,
    StakeAmountTooSmall,
    ValidatorNotActive,
    ExceedsValidatorCapacity,
    InsufficientCooldownBalance,
    NoRewardsToRestake,
    ValidatorPercentageExceeded,
    ZeroRecipientAddress
} from "../lib/PlumeErrors.sol";
import { CooldownStarted } from "../lib/PlumeEvents.sol";
import { Staked } from "../lib/PlumeEvents.sol";
import { StakedOnBehalf } from "../lib/PlumeEvents.sol";
import { Unstaked } from "../lib/PlumeEvents.sol";
import { Withdrawn } from "../lib/PlumeEvents.sol";
import { RewardsRestaked } from "../lib/PlumeEvents.sol";

import { PlumeRewardLogic } from "../lib/PlumeRewardLogic.sol";
import { PlumeStakingStorage } from "../lib/PlumeStakingStorage.sol";
import { PlumeValidatorLogic } from "../lib/PlumeValidatorLogic.sol";

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

    // Constants moved from Base - needed here
    address internal constant PLUME = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 internal constant REWARD_PRECISION = 1e18; // Needed for commission calc in _earned? No, _earned is
        // elsewhere

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
        if (newDelegatedAmount > maxCapacity) {
            revert ExceedsValidatorCapacity(validatorId, newDelegatedAmount, maxCapacity, stakeAmount);
        }
        
        // Check if exceeding validator percentage limit
        if ($.totalStaked > 0 && $.maxValidatorPercentage > 0) {
            uint256 validatorPercentage = (newDelegatedAmount * 10000) / $.totalStaked;
            if (validatorPercentage > $.maxValidatorPercentage) {
                revert ValidatorPercentageExceeded();
            }
        }

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
     * @param amount Amount of tokens to restake (can be 0 to use all available cooling/parked funds)
     */
    function restake(uint16 validatorId, uint256 amount) external returns (uint256) {
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();
        PlumeStakingStorage.StakeInfo storage info = $.stakeInfo[msg.sender];
        
        // Check there's enough in cooldown
        if (amount > info.cooled) {
            revert InsufficientCooldownBalance(info.cooled, amount);
        }
        if (!$.validatorExists[validatorId]) {
            revert ValidatorNotActive(validatorId);
        }

        // Update stake and cooldown amount
        $.userValidatorStakes[msg.sender][validatorId].staked += amount;
        $.validators[validatorId].delegatedAmount += amount;
        info.cooled -= amount;
        $.totalCooling -= amount;
        $.totalStaked += amount;
        
        // Check if exceeding validator capacity
        uint256 newDelegatedAmount = $.validators[validatorId].delegatedAmount;
        uint256 maxCapacity = $.validators[validatorId].maxCapacity;
        if (newDelegatedAmount > maxCapacity) {
            revert ExceedsValidatorCapacity(validatorId, newDelegatedAmount, maxCapacity, amount);
        }
        
        // Check if exceeding validator percentage limit
        if ($.totalStaked > 0 && $.maxValidatorPercentage > 0) {
            uint256 validatorPercentage = (newDelegatedAmount * 10000) / $.totalStaked;
            if (validatorPercentage > $.maxValidatorPercentage) {
                revert ValidatorPercentageExceeded();
            }
        }

        // Emit stake event with details
        emit Staked(
            msg.sender,
            validatorId,
            amount,
            amount, // fromCooled
            0, // fromParked
            0
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
        // Call internal _unstake which is now part of this facet
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
    function withdraw() external /* nonReentrant - Add Reentrancy Guard later if needed */ returns (uint256 amount) {
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
        info.lastUpdateTimestamp = block.timestamp; // Update timestamp? Check if Base did this. Yes.

        // Update total withdrawable amount
        if ($.totalWithdrawable >= amount) {
            $.totalWithdrawable -= amount;
        } else {
            $.totalWithdrawable = 0; // Avoid underflow
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
        $.validators[validatorId].delegatedAmount += stakeAmount;
        $.totalStaked += stakeAmount;

        // Check if exceeding validator capacity
        uint256 newDelegatedAmount = $.validators[validatorId].delegatedAmount;
        uint256 maxCapacity = $.validators[validatorId].maxCapacity;
        if (newDelegatedAmount > maxCapacity) {
            revert ExceedsValidatorCapacity(validatorId, newDelegatedAmount, maxCapacity, stakeAmount);
        }
        
        // Check if exceeding validator percentage limit
        if ($.totalStaked > 0 && $.maxValidatorPercentage > 0) {
            uint256 validatorPercentage = (newDelegatedAmount * 10000) / $.totalStaked;
            if (validatorPercentage > $.maxValidatorPercentage) {
                revert ValidatorPercentageExceeded();
            }
        }

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

    function restakeRewards(uint16 validatorId) external returns (uint256) {
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();
        
        if (!$.validatorExists[validatorId]) {
            revert ValidatorNotActive(validatorId);
        }

        // Get pending rewards to restake
        uint256 pendingRewards = $.stakeInfo[msg.sender].parked;
        if (pendingRewards == 0) {
            revert NoRewardsToRestake();
        }

        // Update stake amount
        $.userValidatorStakes[msg.sender][validatorId].staked += pendingRewards;
        $.validators[validatorId].delegatedAmount += pendingRewards;
        $.totalStaked += pendingRewards;
        
        // Reset user's withdrawable amount
        $.stakeInfo[msg.sender].parked = 0;
        $.totalWithdrawable -= pendingRewards;
        
        // Check if exceeding validator capacity
        uint256 newDelegatedAmount = $.validators[validatorId].delegatedAmount;
        uint256 maxCapacity = $.validators[validatorId].maxCapacity;
        if (newDelegatedAmount > maxCapacity) {
            revert ExceedsValidatorCapacity(validatorId, newDelegatedAmount, maxCapacity, pendingRewards);
        }
        
        // Check if exceeding validator percentage limit
        if ($.totalStaked > 0 && $.maxValidatorPercentage > 0) {
            uint256 validatorPercentage = (newDelegatedAmount * 10000) / $.totalStaked;
            if (validatorPercentage > $.maxValidatorPercentage) {
                revert ValidatorPercentageExceeded();
            }
        }

        // Emit stake event with details
        emit Staked(
            msg.sender,
            validatorId,
            pendingRewards,
            0, // fromCooled
            0, // fromParked
            0
        );

        emit RewardsRestaked(msg.sender, validatorId, pendingRewards);

        return pendingRewards;
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
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();
        return $.totalStaked;
    }

    /**
     * @notice Get the total amount of PLUME cooling in the contract.
     * @return amount Total amount of PLUME cooling.
     */
    function totalAmountCooling() external view returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();
        return $.totalCooling;
    }

    /**
     * @notice Get the total amount of PLUME withdrawable in the contract.
     * @return amount Total amount of PLUME withdrawable.
     */
    function totalAmountWithdrawable() external view returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();
        return $.totalWithdrawable;
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

}
