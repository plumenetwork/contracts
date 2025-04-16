// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {
    ArrayLengthMismatch,
    EmptyArray,
    InvalidAmount,
    InvalidRewardRateCheckpoint,
    RewardRateExceedsMax,
    TokenAlreadyExists,
    TokenDoesNotExist,
    ValidatorDoesNotExist,
    ValidatorInactive,
    ZeroAddress
} from "../lib/PlumeErrors.sol";
import {
    MaxRewardRateUpdated,
    MaxRewardRatesSet,
    RewardClaimed,
    RewardClaimedFromValidator,
    RewardRateCheckpointCreated,
    RewardRatesSet,
    RewardTokenAdded,
    RewardTokenRemoved,
    RewardsAdded,
    Staked
} from "../lib/PlumeEvents.sol";
import { PlumeStakingStorage } from "../lib/PlumeStakingStorage.sol";
import { PlumeStakingValidator } from "./PlumeStakingValidator.sol";

/**
 * @title PlumeStakingRewards
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Extension for rewards management functionality
 */
contract PlumeStakingRewards is PlumeStakingValidator {

    using SafeERC20 for IERC20;

    /**
     * @notice Add a token to the rewards list
     * @param token Address of the token to add
     */
    function addRewardToken(
        address token
    ) external onlyRole(ADMIN_ROLE) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        if (token == address(0)) {
            revert ZeroAddress("token");
        }

        if (_isRewardToken(token)) {
            revert TokenAlreadyExists();
        }

        $.rewardTokens.push(token);
        $.lastUpdateTimes[token] = block.timestamp;
        emit RewardTokenAdded(token);
    }

    /**
     * @notice Remove a token from the rewards list
     * @param token Address of the token to remove
     */
    function removeRewardToken(
        address token
    ) external onlyRole(ADMIN_ROLE) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        uint256 tokenIndex = _getTokenIndex(token);

        if (tokenIndex >= $.rewardTokens.length) {
            revert TokenDoesNotExist(token);
        }

        // Capture any remaining rewards and zero the rate
        _updateRewardPerToken(token, 0);
        $.rewardRates[token] = 0;

        // Remove token from the rewards list (replace with last element and pop)
        $.rewardTokens[tokenIndex] = $.rewardTokens[$.rewardTokens.length - 1];
        $.rewardTokens.pop();

        emit RewardTokenRemoved(token);
    }

    /**
     * @notice Set the reward rates for tokens
     * @param tokens Array of token addresses
     * @param rewardRates_ Array of reward rates
     */
    function setRewardRates(address[] calldata tokens, uint256[] calldata rewardRates_) external onlyRole(ADMIN_ROLE) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        if (tokens.length == 0) {
            revert EmptyArray();
        }

        if (tokens.length != rewardRates_.length) {
            revert ArrayLengthMismatch();
        }

        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 rate = rewardRates_[i];

            if (!_isRewardToken(token)) {
                revert TokenDoesNotExist(token);
            }

            // If token has a specific max rate, use it; otherwise use the global default
            uint256 maxRate = $.maxRewardRates[token] > 0 ? $.maxRewardRates[token] : MAX_REWARD_RATE;

            if (rate > maxRate) {
                revert RewardRateExceedsMax();
            }

            // Update existing token reward state for all validators
            uint16[] memory validatorIds = $.validatorIds;
            for (uint256 j = 0; j < validatorIds.length; j++) {
                uint16 validatorId = validatorIds[j];

                // Update global reward state for this token and validator before changing rate
                _updateRewardPerToken(token, validatorId);

                // Create a checkpoint for this validator's token rate
                _createRewardRateCheckpoint(token, validatorId, rate);
            }

            // Create a global checkpoint for this token's rate (for validators added in the future)
            _createGlobalRewardRateCheckpoint(token, rate);

            // Set the current rate
            $.rewardRates[token] = rate;
        }

        emit RewardRatesSet(tokens, rewardRates_);
    }

    /**
     * @notice Create a checkpoint for a specific token's reward rate for a validator
     * @param token The token address
     * @param validatorId The validator ID
     * @param rate The new reward rate
     */
    function _createRewardRateCheckpoint(address token, uint16 validatorId, uint256 rate) internal {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        // Get the current reward per token value
        uint256 currentCumulativeIndex = $.validatorRewardPerTokenCumulative[validatorId][token];

        // Create the checkpoint
        PlumeStakingStorage.RateCheckpoint memory checkpoint = PlumeStakingStorage.RateCheckpoint({
            timestamp: block.timestamp,
            rate: rate,
            cumulativeIndex: currentCumulativeIndex
        });

        // Add the checkpoint to storage
        $.validatorRewardRateCheckpoints[validatorId][token].push(checkpoint);

        // Emit event
        uint256 checkpointIndex = $.validatorRewardRateCheckpoints[validatorId][token].length - 1;
        emit RewardRateCheckpointCreated(token, rate, block.timestamp, checkpointIndex, currentCumulativeIndex);
    }

    /**
     * @notice Create a global checkpoint for a token's reward rate
     * @param token The token address
     * @param rate The new reward rate
     */
    function _createGlobalRewardRateCheckpoint(address token, uint256 rate) internal {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        // Get the current reward per token value
        uint256 currentCumulativeIndex = $.rewardPerTokenCumulative[token];

        // Create the checkpoint
        PlumeStakingStorage.RateCheckpoint memory checkpoint = PlumeStakingStorage.RateCheckpoint({
            timestamp: block.timestamp,
            rate: rate,
            cumulativeIndex: currentCumulativeIndex
        });

        // Add the checkpoint to storage
        $.rewardRateCheckpoints[token].push(checkpoint);

        // Emit event
        uint256 checkpointIndex = $.rewardRateCheckpoints[token].length - 1;
        emit RewardRateCheckpointCreated(token, rate, block.timestamp, checkpointIndex, currentCumulativeIndex);
    }

    /**
     * @notice Add rewards to the pool
     * @param token Address of the token
     * @param amount Amount to add
     */
    function addRewards(address token, uint256 amount) external payable onlyRole(ADMIN_ROLE) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        if (!_isRewardToken(token)) {
            revert TokenDoesNotExist(token);
        }

        // Update for all validators
        uint16[] memory validatorIds = $.validatorIds;
        for (uint256 i = 0; i < validatorIds.length; i++) {
            _updateRewardPerToken(token, validatorIds[i]);
        }

        // For native token
        if (token == PLUME) {
            if (msg.value != amount) {
                revert InvalidAmount(msg.value);
            }
            // Native tokens already received in msg.value
        } else {
            // Transfer ERC20 tokens from sender to this contract
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        $.rewardsAvailable[token] += amount;
        emit RewardsAdded(token, amount);
    }

    /**
     * @notice Stakes native token (PLUME) rewards without withdrawing them first
     * @param validatorId ID of the validator to stake to
     * @return stakedAmount Amount of PLUME rewards that were staked
     */
    function restakeRewards(
        uint16 validatorId
    ) external nonReentrant returns (uint256 stakedAmount) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        // Verify validator exists and is active
        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }

        PlumeStakingStorage.ValidatorInfo storage validator = $.validators[validatorId];
        if (!validator.active) {
            revert ValidatorInactive(validatorId);
        }

        PlumeStakingStorage.StakeInfo storage info = $.stakeInfo[msg.sender];
        PlumeStakingStorage.StakeInfo storage validatorInfo = $.userValidatorStakes[msg.sender][validatorId];

        // Native token is represented by PLUME constant
        address token = PLUME;

        if (!_isRewardToken(token)) {
            revert TokenDoesNotExist(token);
        }

        // Update rewards to get the latest amount for all validators
        _updateRewards(msg.sender);

        // Get all of the user's validators and sum claimable rewards
        uint16[] memory userValidators = $.userValidators[msg.sender];
        stakedAmount = 0;

        for (uint256 i = 0; i < userValidators.length; i++) {
            uint16 userValidatorId = userValidators[i];
            uint256 validatorRewards = $.userRewards[msg.sender][userValidatorId][token];

            if (validatorRewards > 0) {
                // Reset rewards to 0 as if they were claimed
                $.userRewards[msg.sender][userValidatorId][token] = 0;
                stakedAmount += validatorRewards;

                // Update total claimable
                if ($.totalClaimableByToken[token] >= validatorRewards) {
                    $.totalClaimableByToken[token] -= validatorRewards;
                } else {
                    $.totalClaimableByToken[token] = 0;
                }

                emit RewardClaimedFromValidator(msg.sender, token, userValidatorId, validatorRewards);
            }
        }

        if (stakedAmount > 0) {
            // Update rewards before changing stake amount
            _updateRewardsForValidator(msg.sender, validatorId);

            // Update user's staked amount for this validator
            validatorInfo.staked += stakedAmount;
            info.staked += stakedAmount;

            // Update validator's delegated amount
            validator.delegatedAmount += stakedAmount;

            // Update total staked amounts
            $.validatorTotalStaked[validatorId] += stakedAmount;
            $.totalStaked += stakedAmount;

            // Track user-validator relationship
            _addStakerToValidator(msg.sender, validatorId);

            // Update rewards again with new stake amount
            _updateRewardsForValidator(msg.sender, validatorId);

            // Emit staked event
            emit Staked(msg.sender, validatorId, stakedAmount, 0, 0, 0);
        }

        return stakedAmount;
    }

    /**
     * @notice Get reward information for a user
     * @param user Address of the user
     * @param token Address of the token
     * @return rewards Total current pending rewards across all validators
     */
    function earned(address user, address token) external view returns (uint256 rewards) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        if (!_isRewardToken(token)) {
            return 0;
        }

        uint16[] memory userValidators = $.userValidators[user];

        for (uint256 i = 0; i < userValidators.length; i++) {
            uint16 validatorId = userValidators[i];
            rewards += _earned(user, token, validatorId);
        }

        return rewards;
    }

    /**
     * @notice Get all reward tokens
     * @return tokens Array of all reward token addresses
     * @return rates Array of reward rates corresponding to each token
     */
    function getRewardTokens() external view returns (address[] memory tokens, uint256[] memory rates) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        uint256 length = $.rewardTokens.length;
        tokens = new address[](length);
        rates = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            tokens[i] = $.rewardTokens[i];
            rates[i] = $.rewardRates[$.rewardTokens[i]];
        }
    }

    /**
     * @notice Set the maximum reward rate for a token
     * @param token Address of the token
     * @param newMaxRate New maximum reward rate
     */
    function setMaxRewardRate(address token, uint256 newMaxRate) external onlyRole(ADMIN_ROLE) nonReentrant {
        if (!_isRewardToken(token)) {
            revert TokenDoesNotExist(token);
        }

        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        // Ensure current reward rate doesn't exceed new max rate
        if ($.rewardRates[token] > newMaxRate) {
            revert RewardRateExceedsMax();
        }

        $.maxRewardRates[token] = newMaxRate;

        // Emit the MaxRewardRateUpdated event
        emit MaxRewardRateUpdated(token, newMaxRate);
    }

    /**
     * @notice Get token reward info
     * @param token Address of the token
     * @return rate Current reward rate
     * @return available Total rewards available
     */
    function tokenRewardInfo(
        address token
    ) external view returns (uint256 rate, uint256 available) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        return ($.rewardRates[token], $.rewardsAvailable[token]);
    }

    /**
     * @notice Get the maximum reward rate for a token
     * @param token Address of the token
     * @return Maximum reward rate for the token, or the global MAX_REWARD_RATE if not set
     */
    function getMaxRewardRate(
        address token
    ) external view returns (uint256) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        return $.maxRewardRates[token] > 0 ? $.maxRewardRates[token] : MAX_REWARD_RATE;
    }

    /**
     * @notice Get the number of checkpoints for a token
     * @param token The token address
     * @return count Number of checkpoints
     */
    function getRewardRateCheckpointCount(
        address token
    ) external view returns (uint256) {
        return PlumeStakingStorage.layout().rewardRateCheckpoints[token].length;
    }

    /**
     * @notice Get the number of checkpoints for a validator's token
     * @param validatorId The validator ID
     * @param token The token address
     * @return count Number of checkpoints
     */
    function getValidatorRewardRateCheckpointCount(uint16 validatorId, address token) external view returns (uint256) {
        return PlumeStakingStorage.layout().validatorRewardRateCheckpoints[validatorId][token].length;
    }

    /**
     * @notice Get checkpoint data for a token
     * @param token The token address
     * @param index The checkpoint index
     * @return timestamp Timestamp when the checkpoint was created
     * @return rate Reward rate at the checkpoint
     * @return cumulativeIndex Cumulative reward index at the checkpoint
     */
    function getRewardRateCheckpoint(
        address token,
        uint256 index
    ) external view returns (uint256 timestamp, uint256 rate, uint256 cumulativeIndex) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        if (index >= $.rewardRateCheckpoints[token].length) {
            revert InvalidRewardRateCheckpoint(token, index);
        }

        PlumeStakingStorage.RateCheckpoint storage checkpoint = $.rewardRateCheckpoints[token][index];
        return (checkpoint.timestamp, checkpoint.rate, checkpoint.cumulativeIndex);
    }

    /**
     * @notice Get checkpoint data for a validator's token
     * @param validatorId The validator ID
     * @param token The token address
     * @param index The checkpoint index
     * @return timestamp Timestamp when the checkpoint was created
     * @return rate Reward rate at the checkpoint
     * @return cumulativeIndex Cumulative reward index at the checkpoint
     */
    function getValidatorRewardRateCheckpoint(
        uint16 validatorId,
        address token,
        uint256 index
    ) external view returns (uint256 timestamp, uint256 rate, uint256 cumulativeIndex) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        if (index >= $.validatorRewardRateCheckpoints[validatorId][token].length) {
            revert InvalidRewardRateCheckpoint(token, index);
        }

        PlumeStakingStorage.RateCheckpoint storage checkpoint =
            $.validatorRewardRateCheckpoints[validatorId][token][index];
        return (checkpoint.timestamp, checkpoint.rate, checkpoint.cumulativeIndex);
    }

    /**
     * @notice Get the last processed checkpoint index for a user/validator/token
     * @param user The user address
     * @param validatorId The validator ID
     * @param token The token address
     * @return index The last processed checkpoint index
     */
    function getUserLastCheckpointIndex(
        address user,
        uint16 validatorId,
        address token
    ) external view returns (uint256) {
        return PlumeStakingStorage.layout().userLastCheckpointIndex[user][validatorId][token];
    }

}
