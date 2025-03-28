// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {
    CommissionTooHigh,
    InvalidAmount,
    NativeTransferFailed,
    NoActiveStake,
    NotValidatorAdmin,
    TokenDoesNotExist,
    TooManyStakers,
    ValidatorAlreadyExists,
    ValidatorCapacityExceeded,
    ValidatorDoesNotExist,
    ValidatorInactive,
    ValidatorPercentageExceeded,
    ZeroAddress
} from "../lib/PlumeErrors.sol";
import {
    EmergencyFundsTransferred,
    MaxValidatorCommissionUpdated,
    MaxValidatorPercentageUpdated,
    RewardClaimedFromValidator,
    StakedToValidator,
    UnstakedFromValidator,
    ValidatorActivated,
    ValidatorAdded,
    ValidatorCapacityUpdated,
    ValidatorCommissionClaimed,
    ValidatorDeactivated,
    ValidatorEmergencyTransfer,
    ValidatorRemoved,
    ValidatorStakersRewardsUpdated,
    ValidatorUpdated
} from "../lib/PlumeEvents.sol";
import { PlumeStakingStorage } from "../lib/PlumeStakingStorage.sol";
import { PlumeStakingBase } from "./PlumeStakingBase.sol";

/**
 * @title PlumeStakingValidator
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Extension for validator-specific functionality
 */
contract PlumeStakingValidator is PlumeStakingBase {

    using SafeERC20 for IERC20;

    /**
     * @notice Stake PLUME to a specific validator
     * @param validatorId ID of the validator to stake to
     */
    function stakeToValidator(
        uint16 validatorId
    ) external payable nonReentrant returns (uint256) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        // Verify validator exists and is active
        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }

        PlumeStakingStorage.ValidatorInfo storage validator = $.validators[validatorId];
        if (!validator.active) {
            revert ValidatorInactive(validatorId);
        }

        uint256 amount = msg.value;
        if (amount < $.minStakeAmount) {
            revert InvalidAmount(amount);
        }

        // Check if absolute validator capacity would be exceeded
        if (validator.maxCapacity > 0 && validator.delegatedAmount + amount > validator.maxCapacity) {
            revert ValidatorCapacityExceeded();
        }

        // Check if percentage-based capacity would be exceeded
        if ($.maxValidatorPercentage > 0) {
            uint256 newTotalStaked = $.totalStaked + amount;
            uint256 newValidatorStaked = validator.delegatedAmount + amount;
            uint256 maxAllowed = (newTotalStaked * $.maxValidatorPercentage) / 10_000;

            if (newValidatorStaked > maxAllowed) {
                revert ValidatorPercentageExceeded();
            }
        }

        // Get user's stake info for this validator
        PlumeStakingStorage.StakeInfo storage info = $.userValidatorStakes[msg.sender][validatorId];

        // Update rewards before changing stake amount
        _updateRewardsForValidator(msg.sender, validatorId);

        // Update user's staked amount for this validator
        info.staked += amount;

        // Update validator's delegated amount
        validator.delegatedAmount += amount;

        // Update total staked amounts
        $.validatorTotalStaked[validatorId] += amount;
        $.totalStaked += amount;

        // Track user-validator relationship
        _addStakerToValidator(msg.sender, validatorId);

        // Update rewards again with new stake amount
        _updateRewardsForValidator(msg.sender, validatorId);

        emit StakedToValidator(msg.sender, validatorId, amount, 0, 0, amount);
        return amount;
    }

    /**
     * @notice Unstake PLUME from a specific validator
     * @param validatorId ID of the validator to unstake from
     * @return amount Amount of PLUME unstaked
     */
    function unstakeFromValidator(
        uint16 validatorId
    ) external nonReentrant returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        // Verify validator exists
        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }

        // Get user's stake info for this validator
        PlumeStakingStorage.StakeInfo storage info = $.userValidatorStakes[msg.sender][validatorId];

        if (info.staked == 0) {
            revert NoActiveStake();
        }

        // Update rewards before changing stake amount
        _updateRewardsForValidator(msg.sender, validatorId);

        // Get unstaked amount
        amount = info.staked;

        // Update user's staked amount for this validator
        info.staked = 0;

        // Update validator's delegated amount
        $.validators[validatorId].delegatedAmount -= amount;

        // Update total staked amounts
        $.validatorTotalStaked[validatorId] -= amount;
        $.totalStaked -= amount;

        // Move tokens to cooling period
        info.cooled += amount;
        info.cooldownEnd = block.timestamp + $.cooldownInterval;

        // Update cooling totals
        $.validatorTotalCooling[validatorId] += amount;
        $.totalCooling += amount;

        emit UnstakedFromValidator(msg.sender, validatorId, amount);
        return amount;
    }

    /**
     * @notice Claim all accumulated rewards from a single token and validator
     * @param token Address of the reward token to claim
     * @param validatorId ID of the validator to claim from
     * @return amount Amount of reward token claimed
     */
    function claimFromValidator(address token, uint16 validatorId) external nonReentrant returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        if (!_isRewardToken(token)) {
            revert TokenDoesNotExist(token);
        }

        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }

        _updateRewardsForValidator(msg.sender, validatorId);

        amount = $.userRewards[msg.sender][validatorId][token];
        if (amount > 0) {
            $.userRewards[msg.sender][validatorId][token] = 0;

            // Update total claimable
            if ($.totalClaimableByToken[token] >= amount) {
                $.totalClaimableByToken[token] -= amount;
            } else {
                $.totalClaimableByToken[token] = 0;
            }

            // Transfer tokens - either ERC20 or native PLUME
            if (token != PLUME) {
                IERC20(token).safeTransfer(msg.sender, amount);
            } else {
                // Check if native transfer was successful
                (bool success,) = payable(msg.sender).call{ value: amount }("");
                if (!success) {
                    revert NativeTransferFailed();
                }
            }

            emit RewardClaimedFromValidator(msg.sender, token, validatorId, amount);
        }

        return amount;
    }

    /**
     * @notice Claim validator commission rewards
     * @param validatorId ID of the validator
     * @param token Address of the reward token to claim
     * @return amount Amount of commission claimed
     */
    function claimValidatorCommission(
        uint16 validatorId,
        address token
    ) external nonReentrant returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }

        PlumeStakingStorage.ValidatorInfo storage validator = $.validators[validatorId];

        // Only validator admin can claim commission
        if (msg.sender != validator.l2AdminAddress) {
            revert NotValidatorAdmin(msg.sender);
        }

        // For safety, check if too many stakers
        address[] memory stakers = $.validatorStakers[validatorId];
        if (stakers.length > 100) {
            revert TooManyStakers();
        }

        // Update all rewards to ensure commission is current
        _updateRewardsForAllValidatorStakers(validatorId);

        amount = $.validatorAccruedCommission[validatorId][token];
        if (amount > 0) {
            $.validatorAccruedCommission[validatorId][token] = 0;

            // Transfer to validator's withdraw address
            if (token != PLUME) {
                IERC20(token).safeTransfer(validator.l2WithdrawAddress, amount);
            } else {
                // Check if native transfer was successful
                (bool success,) = payable(validator.l2WithdrawAddress).call{ value: amount }("");
                if (!success) {
                    revert NativeTransferFailed();
                }
            }

            emit ValidatorCommissionClaimed(validatorId, token, amount);
        }

        return amount;
    }

    /**
     * @notice Update rewards for a user on a specific validator
     * @param user Address of the user
     * @param validatorId ID of the validator
     */
    function _updateRewardsForValidator(address user, uint16 validatorId) internal {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        address[] memory rewardTokens = $.rewardTokens;

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];

            // Update reward per token for this validator
            _updateRewardPerTokenForValidator(token, validatorId);

            if (user != address(0)) {
                // Get validator commission rate
                PlumeStakingStorage.ValidatorInfo storage validator = $.validators[validatorId];
                uint256 validatorCommission = validator.commission;

                // Get user's stake info
                uint256 userStakedAmount = $.userValidatorStakes[user][validatorId].staked;

                // Get previous reward data
                uint256 oldReward = $.userRewards[user][validatorId][token];
                uint256 oldRewardPerToken = $.userValidatorRewardPerTokenPaid[user][validatorId][token];
                uint256 currentRewardPerToken = $.validatorRewardPerTokenCumulative[validatorId][token];

                // Calculate reward with improved precision
                uint256 rewardDelta = currentRewardPerToken - oldRewardPerToken;

                // Calculate user's portion with commission deducted in a single operation
                uint256 userRewardAfterCommission = (
                    userStakedAmount * rewardDelta * (REWARD_PRECISION - validatorCommission)
                ) / (REWARD_PRECISION * REWARD_PRECISION);

                // Calculate commission amount
                uint256 commissionAmount =
                    (userStakedAmount * rewardDelta * validatorCommission) / (REWARD_PRECISION * REWARD_PRECISION);

                // Add commission to validator's accrued commission
                if (commissionAmount > 0) {
                    $.validatorAccruedCommission[validatorId][token] += commissionAmount;
                }

                // Update user's reward after commission
                $.userRewards[user][validatorId][token] = oldReward + userRewardAfterCommission;

                // Update user's reward per token paid
                $.userValidatorRewardPerTokenPaid[user][validatorId][token] = currentRewardPerToken;
            }
        }
    }

    /**
     * @notice Update the reward per token value for a specific validator
     * @param token The address of the reward token
     * @param validatorId The ID of the validator
     */
    function _updateRewardPerTokenForValidator(address token, uint16 validatorId) internal {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        if ($.validatorTotalStaked[validatorId] > 0) {
            uint256 timeDelta = block.timestamp - $.validatorLastUpdateTimes[validatorId][token];
            if (timeDelta > 0 && $.rewardRates[token] > 0) {
                uint256 reward =
                    (timeDelta * $.rewardRates[token] * REWARD_PRECISION) / $.validatorTotalStaked[validatorId];
                $.validatorRewardPerTokenCumulative[validatorId][token] += reward;
            }
        }

        $.validatorLastUpdateTimes[validatorId][token] = block.timestamp;
    }

    /**
     * @notice Add a staker to a validator's staker list
     * @param staker Address of the staker
     * @param validatorId ID of the validator
     */
    function _addStakerToValidator(address staker, uint16 validatorId) internal {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        // Add validator to user's validator list if not already there
        if (!$.userHasStakedWithValidator[staker][validatorId]) {
            $.userValidators[staker].push(validatorId);
            $.userHasStakedWithValidator[staker][validatorId] = true;
        }

        // Add user to validator's staker list if not already there
        if (!$.isStakerForValidator[validatorId][staker]) {
            $.validatorStakers[validatorId].push(staker);
            $.isStakerForValidator[validatorId][staker] = true;
        }

        // Also add to global stakers list if not already there
        _addStakerIfNew(staker);
    }

    /**
     * @notice Update rewards for all stakers of a validator
     * @param validatorId ID of the validator
     */
    function _updateRewardsForAllValidatorStakers(
        uint16 validatorId
    ) internal {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        address[] memory stakers = $.validatorStakers[validatorId];

        // For safety, revert if attempting to update a very large number of stakers at once
        if (stakers.length > 100) {
            revert TooManyStakers();
        }

        for (uint256 i = 0; i < stakers.length; i++) {
            _updateRewardsForValidator(stakers[i], validatorId);
        }
    }

    /**
     * @notice Add a new validator
     * @param validatorId Fixed UUID for the validator
     * @param commission Commission rate (as fraction of REWARD_PRECISION)
     * @param l2AdminAddress Admin address for the validator
     * @param l2WithdrawAddress Withdrawal address for validator rewards
     * @param l1ValidatorAddress Address of validator on L1 (informational)
     * @param l1AccountAddress Address of account on L1 (informational)
     */
    function addValidator(
        uint16 validatorId,
        uint256 commission,
        address l2AdminAddress,
        address l2WithdrawAddress,
        string calldata l1ValidatorAddress,
        string calldata l1AccountAddress
    ) external onlyRole(ADMIN_ROLE) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        if ($.validatorExists[validatorId]) {
            revert ValidatorAlreadyExists(validatorId);
        }

        if (l2AdminAddress == address(0)) {
            revert ZeroAddress("l2AdminAddress");
        }

        if (l2WithdrawAddress == address(0)) {
            revert ZeroAddress("l2WithdrawAddress");
        }

        if (commission > REWARD_PRECISION) {
            revert CommissionTooHigh();
        }

        // Create new validator
        PlumeStakingStorage.ValidatorInfo storage validator = $.validators[validatorId];
        validator.validatorId = validatorId;
        validator.commission = commission;
        validator.delegatedAmount = 0;
        validator.l2AdminAddress = l2AdminAddress;
        validator.l2WithdrawAddress = l2WithdrawAddress;
        validator.l1ValidatorAddress = l1ValidatorAddress;
        validator.l1AccountAddress = l1AccountAddress;
        validator.active = true;

        // Add to validator registry
        $.validatorIds.push(validatorId);
        $.validatorExists[validatorId] = true;

        // Initialize epoch data if using epochs
        if ($.usingEpochs) {
            $.epochValidatorAmounts[$.currentEpochNumber][validatorId] = 0;
        }

        emit ValidatorAdded(
            validatorId, commission, l2AdminAddress, l2WithdrawAddress, l1ValidatorAddress, l1AccountAddress
        );
    }

}
