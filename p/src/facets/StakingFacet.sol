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
    TransferFailed,
    ValidatorCapacityExceeded,
    ValidatorDoesNotExist,
    ValidatorInactive,
    ZeroAddress
} from "../lib/PlumeErrors.sol";
import { CooldownStarted, Staked, StakedOnBehalf, Unstaked, Withdrawn } from "../lib/PlumeEvents.sol";
import { PlumeStakingStorage } from "../lib/PlumeStakingStorage.sol";
import { PlumeRewardLogic } from "../lib/PlumeRewardLogic.sol";
import { PlumeValidatorLogic } from "../lib/PlumeValidatorLogic.sol";

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { DiamondBaseStorage } from "@solidstate/proxy/diamond/base/DiamondBaseStorage.sol";


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

    function plumeStorage() internal pure returns (PlumeStakingStorage.Layout storage $) {
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
        PlumeStakingStorage.Layout storage $ = plumeStorage();

        // Verify validator exists and is active
        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }

        PlumeStakingStorage.ValidatorInfo storage validator = $.validators[validatorId];
        if (!validator.active) {
            revert ValidatorInactive(validatorId);
        }

        // Get user's stake info
        PlumeStakingStorage.StakeInfo storage info = $.stakeInfo[msg.sender];
        PlumeStakingStorage.StakeInfo storage validatorInfo = $.userValidatorStakes[msg.sender][validatorId];

        // Only use funds from wallet
        uint256 walletAmount = msg.value;

        // Verify minimum stake amount
        if (walletAmount < $.minStakeAmount) {
            revert InvalidAmount(walletAmount);
        }

        // Update rewards using library
        PlumeRewardLogic.updateRewardsForValidator($, msg.sender, validatorId);

        // If this is the first time staking with this validator, record the start time
        bool firstTimeStaking = validatorInfo.staked == 0;

        // Update user's staked amount for this validator
        validatorInfo.staked += walletAmount;
        info.staked += walletAmount;

        // Update validator's delegated amount
        validator.delegatedAmount += walletAmount;

        // Update total staked amounts
        $.validatorTotalStaked[validatorId] += walletAmount;
        $.totalStaked += walletAmount;

        // Replace delegatecall with library call
        PlumeValidatorLogic.addStakerToValidator($, msg.sender, validatorId);

        if (firstTimeStaking) {
            $.userValidatorStakeStartTime[msg.sender][validatorId] = block.timestamp;
        }
        PlumeRewardLogic.updateRewardsForValidator($, msg.sender, validatorId);

        emit Staked(msg.sender, validatorId, walletAmount, 0, 0, walletAmount);
        return walletAmount;
    }

    /**
     * @notice Restake PLUME to a specific validator, using funds only from cooling and parked balances
     * @param validatorId ID of the validator to stake to
     * @param amount Amount of tokens to restake (can be 0 to use all available cooling/parked funds)
     */
    function restake(uint16 validatorId, uint256 amount) external returns (uint256) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();

        // Verify validator exists and is active
        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }

        PlumeStakingStorage.ValidatorInfo storage validator = $.validators[validatorId];
        if (!validator.active) {
            revert ValidatorInactive(validatorId);
        }

        // Get user's stake info
        PlumeStakingStorage.StakeInfo storage info = $.stakeInfo[msg.sender];
        PlumeStakingStorage.StakeInfo storage validatorInfo = $.userValidatorStakes[msg.sender][validatorId];

        // Calculate amounts to use from each source
        uint256 fromCooling = 0;
        uint256 fromParked = 0;
        uint256 totalAmount = 0;

        // If amount is 0, use all available funds from cooling and parked
        bool useAllFunds = amount == 0;
        uint256 remainingToUse = useAllFunds ? type(uint256).max : amount;

        // First, use cooling amount if available (regardless of cooldown status)
        if (info.cooled > 0 && remainingToUse > 0) {
            uint256 amountToUseFromCooling =
                useAllFunds ? info.cooled : (remainingToUse < info.cooled ? remainingToUse : info.cooled);

            fromCooling = amountToUseFromCooling;
            info.cooled -= fromCooling;
            $.totalCooling = ($.totalCooling > fromCooling) ? $.totalCooling - fromCooling : 0;
            remainingToUse = useAllFunds ? remainingToUse : remainingToUse - fromCooling;

            if (info.cooled == 0) {
                info.cooldownEnd = 0;
            }

            totalAmount += fromCooling;
        }

        // Second, use parked amount if available and more is needed
        if (info.parked > 0 && remainingToUse > 0) {
            uint256 amountToUseFromParked =
                useAllFunds ? info.parked : (remainingToUse < info.parked ? remainingToUse : info.parked);

            fromParked = amountToUseFromParked;
            info.parked -= fromParked;
            totalAmount += fromParked;
            $.totalWithdrawable = ($.totalWithdrawable > fromParked) ? $.totalWithdrawable - fromParked : 0;
        }

        // Verify minimum stake amount (use minStakeAmount from storage)
        if (totalAmount < $.minStakeAmount) {
            revert InvalidAmount(totalAmount);
        }

        // Update rewards using library
        PlumeRewardLogic.updateRewardsForValidator($, msg.sender, validatorId);

        // If this is the first time staking with this validator, record the start time
        bool firstTimeStaking = validatorInfo.staked == 0;

        // Update user's staked amount for this validator
        validatorInfo.staked += totalAmount;
        info.staked += totalAmount;

        // Update validator's delegated amount
        validator.delegatedAmount += totalAmount;

        // Update total staked amounts
        $.validatorTotalStaked[validatorId] += totalAmount;
        $.totalStaked += totalAmount;

        // Replace delegatecall with library call
        PlumeValidatorLogic.addStakerToValidator($, msg.sender, validatorId);

        if (firstTimeStaking) {
            $.userValidatorStakeStartTime[msg.sender][validatorId] = block.timestamp;
        }
        PlumeRewardLogic.updateRewardsForValidator($, msg.sender, validatorId);

        emit Staked(msg.sender, validatorId, totalAmount, fromCooling, fromParked, 0);
        return totalAmount;
    }

    /**
     * @notice Unstake PLUME from a specific validator (full amount)
     * @param validatorId ID of the validator to unstake from
     * @return amount Amount of PLUME unstaked
     */
    function unstake(
        uint16 validatorId
    ) external returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
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
        PlumeStakingStorage.Layout storage $ = plumeStorage();

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

        emit CooldownStarted(msg.sender, validatorId, amountUnstaked, globalInfo.cooldownEnd);
        emit Unstaked(msg.sender, validatorId, amountUnstaked); // Keep original Unstaked event

        return amountUnstaked;
    }

    /**
     * @notice Withdraw PLUME that has completed the cooldown period
     * @return amount Amount of PLUME withdrawn
     */
    function withdraw() external /* nonReentrant - Add Reentrancy Guard later if needed */ returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
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
        PlumeStakingStorage.Layout storage $ = plumeStorage();

        // Verify validator exists and is active
        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }

        if (staker == address(0)) {
            revert ZeroAddress("staker");
        }

        PlumeStakingStorage.ValidatorInfo storage validator = $.validators[validatorId];
        if (!validator.active) {
            revert ValidatorInactive(validatorId);
        }

        // Get staker's stake info
        PlumeStakingStorage.StakeInfo storage info = $.stakeInfo[staker];
        PlumeStakingStorage.StakeInfo storage validatorInfo = $.userValidatorStakes[staker][validatorId];

        // Only use funds from msg.sender's wallet
        uint256 fromWallet = msg.value;

        // Verify minimum stake amount
        if (fromWallet < $.minStakeAmount) {
            revert InvalidAmount(fromWallet);
        }

        // Update rewards for the staker using library
        PlumeRewardLogic.updateRewardsForValidator($, staker, validatorId);

        // Check if this is the first time the staker is staking with this validator
        bool firstTimeStaking = validatorInfo.staked == 0;

        // Update staker's staked amount for this validator
        validatorInfo.staked += fromWallet;
        info.staked += fromWallet;

        // Update validator's delegated amount
        validator.delegatedAmount += fromWallet;

        // Update total staked amounts
        $.validatorTotalStaked[validatorId] += fromWallet;
        $.totalStaked += fromWallet;

        // Replace delegatecall with library call
        PlumeValidatorLogic.addStakerToValidator($, staker, validatorId);

        if (firstTimeStaking) {
            $.userValidatorStakeStartTime[staker][validatorId] = block.timestamp;
        }
        PlumeRewardLogic.updateRewardsForValidator($, staker, validatorId);

        // Use original Staked event for consistency
        emit Staked(staker, validatorId, fromWallet, 0, 0, fromWallet);
        emit StakedOnBehalf(msg.sender, staker, validatorId, fromWallet);
        return fromWallet;
    }

    // --- View Functions ---

    /**
     * @notice Returns the amount of PLUME currently staked by the caller
     */
    function amountStaked() external view returns (uint256 amount) {
        return plumeStorage().stakeInfo[msg.sender].staked;
    }

    /**
     * @notice Returns the amount of PLUME currently in cooling period for the caller
     */
    function amountCooling() external view returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
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
        PlumeStakingStorage.Layout storage $ = plumeStorage();
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
        return plumeStorage().stakeInfo[msg.sender].cooldownEnd;
    }

    /**
     * @notice Get staking information for a user (global stake info)
     */
    function stakeInfo(
        address user
    ) external view returns (PlumeStakingStorage.StakeInfo memory) {
        return plumeStorage().stakeInfo[user];
    }

}
