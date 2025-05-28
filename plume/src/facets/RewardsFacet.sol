// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {
    ArrayLengthMismatch,
    EmptyArray,
    InsufficientBalance,
    InternalInconsistency,
    InvalidAmount,
    InvalidRewardRateCheckpoint,
    NativeTransferFailed,
    RewardRateExceedsMax,
    TokenAlreadyExists,
    TokenDoesNotExist,
    TreasuryNotSet,
    Unauthorized,
    ValidatorDoesNotExist,
    ValidatorInactive,
    ZeroAddress
} from "../lib/PlumeErrors.sol";

import {
    MaxRewardRateUpdated,
    RewardClaimed,
    RewardClaimedFromValidator,
    RewardRateCheckpointCreated,
    RewardRatesSet,
    RewardTokenAdded,
    RewardTokenRemoved,
    Staked,
    TreasurySet
} from "../lib/PlumeEvents.sol";

import { IPlumeStakingRewardTreasury } from "../interfaces/IPlumeStakingRewardTreasury.sol";
import { PlumeRewardLogic } from "../lib/PlumeRewardLogic.sol";
import { PlumeStakingStorage } from "../lib/PlumeStakingStorage.sol";

import { OwnableStorage } from "@solidstate/access/ownable/OwnableStorage.sol";
import { DiamondBaseStorage } from "@solidstate/proxy/diamond/base/DiamondBaseStorage.sol";

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { IAccessControl } from "../interfaces/IAccessControl.sol";
import { PlumeRoles } from "../lib/PlumeRoles.sol";
import { OwnableInternal } from "@solidstate/access/ownable/OwnableInternal.sol";

using PlumeRewardLogic for PlumeStakingStorage.Layout;

/**
 * @title RewardsFacet
 * @notice Facet handling reward token management, rate setting, reward calculation, and claiming.
 */
contract RewardsFacet is ReentrancyGuardUpgradeable, OwnableInternal {

    using SafeERC20 for IERC20;
    using Address for address payable;

    // --- Constants ---
    uint256 internal constant BASE = 1e18;
    uint256 internal constant MAX_REWARD_RATE = 3171 * 1e9;

    // --- Storage Access ---
    bytes32 internal constant TREASURY_STORAGE_POSITION = keccak256("plume.storage.RewardTreasury");

    function getTreasuryAddress() internal view returns (address) {
        bytes32 position = TREASURY_STORAGE_POSITION;
        address treasuryAddress;
        assembly {
            treasuryAddress := sload(position)
        }
        return treasuryAddress;
    }

    function setTreasuryAddress(
        address _treasury
    ) internal {
        bytes32 position = TREASURY_STORAGE_POSITION;
        assembly {
            sstore(position, _treasury)
        }
    }

    modifier onlyRole(
        bytes32 _role
    ) {
        if (!IAccessControl(address(this)).hasRole(_role, msg.sender)) {
            revert Unauthorized(msg.sender, _role);
        }
        _;
    }

    // --- Internal View Function (_earned) ---
    function _earned(address user, address token, uint16 validatorId) internal returns (uint256 rewards) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        uint256 userStakedAmount = $.userValidatorStakes[user][validatorId].staked;
        if (userStakedAmount == 0) {
            return $.userRewards[user][validatorId][token];
        }

        (uint256 userRewardDelta,,) =
            PlumeRewardLogic.calculateRewardsWithCheckpoints($, user, validatorId, token, userStakedAmount);
        rewards = $.userRewards[user][validatorId][token] + userRewardDelta;

        return rewards;
    }

    /**
     * @dev Calculates total earned rewards for a user across all validators for a specific token
     * @param user The user to calculate rewards for
     * @param token The reward token
     * @return totalEarned The total earned amount across all validators
     */
    function _calculateTotalEarned(address user, address token) internal returns (uint256 totalEarned) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        uint16[] memory validatorIds = $.userValidators[user];

        // Sum across all validators
        for (uint256 i = 0; i < validatorIds.length; i++) {
            uint16 validatorId = validatorIds[i];
            if (!$.validators[validatorId].active) {
                totalEarned += $.userRewards[user][validatorId][token];
                continue;
            }
            totalEarned += _earned(user, token, validatorId);
        }

        return totalEarned;
    }

    // --- Admin Functions ---

    /**
     * @notice Sets the treasury address
     * @dev Only callable by ADMIN role
     * @param _treasury Address of the PlumeStakingRewardTreasury contract
     */
    function setTreasury(
        address _treasury
    ) external onlyRole(PlumeRoles.TIMELOCK_ROLE) {
        if (_treasury == address(0)) {
            revert ZeroAddress("treasury");
        }
        setTreasuryAddress(_treasury);
        emit TreasurySet(_treasury);
    }

    function addRewardToken(
        address token
    ) external onlyRole(PlumeRoles.REWARD_MANAGER_ROLE) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        if (token == address(0)) {
            revert ZeroAddress("token");
        }
        if ($.isRewardToken[token]) {
            revert TokenAlreadyExists();
        }
        $.rewardTokens.push(token);
        $.isRewardToken[token] = true;
        for (uint256 i = 0; i < $.validatorIds.length; i++) {
            $.validatorLastUpdateTimes[$.validatorIds[i]][token] = block.timestamp;
        }
        emit RewardTokenAdded(token);
    }

    /**
     * @notice Remove a reward token from the contract.
     *   This also prevents any users from claiming existing rewards for this token.
     * @dev Only callable by REWARD_MANAGER_ROLE
     * @param token Address of the token to remove
     */
    function removeRewardToken(
        address token
    ) external onlyRole(PlumeRoles.REWARD_MANAGER_ROLE) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        if (!$.isRewardToken[token]) {
            revert TokenDoesNotExist(token);
        }

        // Find the index of the token in the array
        uint256 tokenIndex = _getTokenIndex(token);

        // Update rewards using the library before removing
        for (uint256 i = 0; i < $.validatorIds.length; i++) {
            // Needs to update the cumulative index, not user rewards
            PlumeRewardLogic.updateRewardPerTokenForValidator($, token, $.validatorIds[i]);
        }
        $.rewardRates[token] = 0;

        // Update the array
        $.rewardTokens[tokenIndex] = $.rewardTokens[$.rewardTokens.length - 1];
        $.rewardTokens.pop();

        // Update the mapping
        $.isRewardToken[token] = false;

        delete $.maxRewardRates[token];
        emit RewardTokenRemoved(token);
    }

    function setRewardRates(
        address[] calldata tokens,
        uint256[] calldata rewardRates_
    ) external onlyRole(PlumeRoles.REWARD_MANAGER_ROLE) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        if (tokens.length == 0) {
            revert EmptyArray();
        }
        if (tokens.length != rewardRates_.length) {
            revert ArrayLengthMismatch();
        }
        uint16[] memory validatorIds = $.validatorIds;
        for (uint256 i = 0; i < tokens.length; i++) {
            address token_loop = tokens[i];
            uint256 rate_loop = rewardRates_[i];

            if (!$.isRewardToken[token_loop]) {
                revert TokenDoesNotExist(token_loop);
            }
            uint256 maxRate = $.maxRewardRates[token_loop] > 0 ? $.maxRewardRates[token_loop] : MAX_REWARD_RATE;
            if (rate_loop > maxRate) {
                revert RewardRateExceedsMax();
            }

            for (uint256 j = 0; j < validatorIds.length; j++) {
                uint16 validatorId_for_crrc = validatorIds[j];

                PlumeRewardLogic.createRewardRateCheckpoint($, token_loop, validatorId_for_crrc, rate_loop);
            }
            $.rewardRates[token_loop] = rate_loop;
        }
        emit RewardRatesSet(tokens, rewardRates_);
    }

    function setMaxRewardRate(address token, uint256 newMaxRate) external onlyRole(PlumeRoles.REWARD_MANAGER_ROLE) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        if (!$.isRewardToken[token]) {
            revert TokenDoesNotExist(token);
        }
        if ($.rewardRates[token] > newMaxRate) {
            revert RewardRateExceedsMax();
        }
        $.maxRewardRates[token] = newMaxRate;
        emit MaxRewardRateUpdated(token, newMaxRate);
    }

    // --- Claim Functions ---

    function claim(address token, uint16 validatorId) external nonReentrant returns (uint256) {
        // Validate inputs
        _validateTokenForClaim(token, msg.sender);
        _validateValidatorForClaim(validatorId);

        // Process rewards for this specific validator
        uint256 reward = _processValidatorRewards(msg.sender, validatorId, token);

        // Finalize claim if there are rewards
        if (reward > 0) {
            _finalizeRewardClaim(token, reward, msg.sender);
        }

        // Clear pending flags for this validator
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        PlumeRewardLogic.clearPendingRewardsFlagIfEmpty($, msg.sender, validatorId);

        return reward;
    }

    function claim(
        address token
    ) external nonReentrant returns (uint256) {
        // Validate token
        _validateTokenForClaim(token, msg.sender);

        // Process rewards from all active validators
        uint256 totalReward = _processAllValidatorRewards(msg.sender, token);

        // Finalize claim if there are rewards
        if (totalReward > 0) {
            _finalizeRewardClaim(token, totalReward, msg.sender);
            emit RewardClaimed(msg.sender, token, totalReward);
        }

        // Clear pending flags for all validators
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        uint16[] memory validatorIds = $.userValidators[msg.sender];
        _clearPendingRewardFlags(msg.sender, validatorIds);

        return totalReward;
    }

    function claimAll() external nonReentrant returns (uint256[] memory) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        address[] memory tokens = $.rewardTokens;
        uint256[] memory claims = new uint256[](tokens.length);

        // Process each token
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];

            // Process rewards from all active validators for this token
            uint256 totalReward = _processAllValidatorRewards(msg.sender, token);

            // Finalize claim if there are rewards
            if (totalReward > 0) {
                _finalizeRewardClaim(token, totalReward, msg.sender);
                claims[i] = totalReward;
                emit RewardClaimed(msg.sender, token, totalReward);
            }
        }

        // Clear pending flags for all validators after claiming all tokens
        uint16[] memory validatorIds = $.userValidators[msg.sender];
        _clearPendingRewardFlags(msg.sender, validatorIds);

        return claims;
    }

    // --- Internal Functions ---

    /**
     * @dev Validates that a token can be claimed by checking if it's active or has existing rewards
     * @param token The token to validate
     * @param user The user attempting to claim
     * @return isActive Whether the token is currently active
     */
    function _validateTokenForClaim(address token, address user) internal view returns (bool isActive) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        isActive = $.isRewardToken[token];

        if (!isActive) {
            // If token is not active, check if there are previously earned/stored rewards
            uint16[] memory validatorIds = $.userValidators[user];
            bool hasExistingRewards = false;

            for (uint256 i = 0; i < validatorIds.length; i++) {
                if ($.userRewards[user][validatorIds[i]][token] > 0) {
                    hasExistingRewards = true;
                    break;
                }
            }

            if (!hasExistingRewards) {
                revert TokenDoesNotExist(token);
            }
        }
    }

    /**
     * @dev Validates that a validator can be used for claiming
     * @param validatorId The validator to validate
     */
    function _validateValidatorForClaim(
        uint16 validatorId
    ) internal view {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }
        if (!$.validators[validatorId].active) {
            revert ValidatorInactive(validatorId);
        }
    }

    /**
     * @dev Calculates and processes rewards for a single user-validator-token combination
     * @param user The user claiming rewards
     * @param validatorId The validator to claim from
     * @param token The token to claim
     * @return reward The amount of rewards processed
     */
    function _processValidatorRewards(
        address user,
        uint16 validatorId,
        address token
    ) internal returns (uint256 reward) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        uint256 userStakedAmount = $.userValidatorStakes[user][validatorId].staked;

        // Ensure validator's cumulative reward index is up-to-date
        PlumeRewardLogic.updateRewardPerTokenForValidator($, token, validatorId);

        // Calculate rewards using library function
        (uint256 userRewardDelta,,) =
            PlumeRewardLogic.calculateRewardsWithCheckpoints($, user, validatorId, token, userStakedAmount);

        // Calculate total reward as stored + computed delta
        reward = $.userRewards[user][validatorId][token] + userRewardDelta;

        if (reward > 0) {
            // Update state
            _updateUserRewardState(user, validatorId, token, reward);

            emit RewardClaimedFromValidator(user, token, validatorId, reward);
        }

        return reward;
    }

    /**
     * @dev Updates user reward state after claiming
     * @param user The user who claimed
     * @param validatorId The validator claimed from
     * @param token The token claimed
     * @param rewardAmount The amount that was claimed
     */
    function _updateUserRewardState(address user, uint16 validatorId, address token, uint256 rewardAmount) internal {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        // Reset stored accumulated reward
        $.userRewards[user][validatorId][token] = 0;

        // Update user's last processed timestamp and cumulative index
        $.userValidatorRewardPerTokenPaidTimestamp[user][validatorId][token] = block.timestamp;
        $.userValidatorRewardPerTokenPaid[user][validatorId][token] =
            $.validatorRewardPerTokenCumulative[validatorId][token];
    }

    /**
     * @dev Updates global reward tracking and transfers rewards to user
     * @param token The token being claimed
     * @param totalAmount The total amount being claimed
     * @param recipient The recipient of the rewards
     */
    function _finalizeRewardClaim(address token, uint256 totalAmount, address recipient) internal {
        if (totalAmount == 0) {
            return;
        }

        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        // Update global tracking
        if ($.totalClaimableByToken[token] >= totalAmount) {
            $.totalClaimableByToken[token] -= totalAmount;
        } else {
            $.totalClaimableByToken[token] = 0;
        }

        // Transfer rewards from treasury
        _transferRewardFromTreasury(token, totalAmount, recipient);
    }

    /**
     * @dev Clears pending reward flags for validators that no longer have rewards
     * @param user The user to check flags for
     * @param validatorIds Array of validator IDs to check
     */
    function _clearPendingRewardFlags(address user, uint16[] memory validatorIds) internal {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        for (uint256 i = 0; i < validatorIds.length; i++) {
            PlumeRewardLogic.clearPendingRewardsFlagIfEmpty($, user, validatorIds[i]);
        }
    }

    /**
     * @dev Processes rewards for all active validators for a specific token
     * @param user The user claiming rewards
     * @param token The token to claim
     * @return totalReward The total amount of rewards processed
     */
    function _processAllValidatorRewards(address user, address token) internal returns (uint256 totalReward) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        uint16[] memory validatorIds = $.userValidators[user];

        for (uint256 i = 0; i < validatorIds.length; i++) {
            uint16 validatorId = validatorIds[i];

            // For slashed validators, process stored rewards directly
            if ($.validators[validatorId].slashed) {
                uint256 storedReward = $.userRewards[user][validatorId][token];
                if (storedReward > 0) {
                    // Update state to mark rewards as claimed
                    _updateUserRewardState(user, validatorId, token, storedReward);
                    totalReward += storedReward;
                    emit RewardClaimedFromValidator(user, token, validatorId, storedReward);
                }
                continue;
            }

            // Skip inactive (but not slashed) validators
            if (!$.validators[validatorId].active) {
                continue;
            }

            uint256 rewardFromValidator = _processValidatorRewards(user, validatorId, token);
            totalReward += rewardFromValidator;
        }

        return totalReward;
    }

    /**
     * @notice Transfer reward from treasury to recipient
     * @dev Internal function to handle reward transfers from treasury
     * @param token Token to transfer
     * @param amount Amount to transfer
     * @param recipient Recipient address
     */
    function _transferRewardFromTreasury(address token, uint256 amount, address recipient) internal {
        address treasury = getTreasuryAddress();
        if (treasury == address(0)) {
            revert TreasuryNotSet();
        }

        // Make the treasury send the rewards directly to the user
        IPlumeStakingRewardTreasury(treasury).distributeReward(token, amount, recipient);
    }

    function _isRewardToken(
        address token
    ) internal view returns (bool) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        return $.isRewardToken[token];
    }

    function _getTokenIndex(
        address token
    ) internal view returns (uint256) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        // First check if the token is a reward token
        if (!$.isRewardToken[token]) {
            revert TokenDoesNotExist(token);
        }

        // Find the index in the array
        address[] memory rewardTokens = $.rewardTokens;
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (rewardTokens[i] == token) {
                return i;
            }
        }

        // This should never happen if isRewardToken is properly maintained
        revert InternalInconsistency("Reward token map/array mismatch");
    }

    // --- Public View Functions ---

    function earned(address user, address token) external returns (uint256) {
        return _calculateTotalEarned(user, token);
    }

    function getClaimableReward(address user, address token) external returns (uint256) {
        // Same implementation as earned
        return this.earned(user, token);
    }

    function getRewardTokens() external view returns (address[] memory) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        return $.rewardTokens;
    }

    /**
     * @notice Get the maximum reward rate for a specific token.
     * @param token Address of the token to check.
     * @return The maximum reward rate for the token.
     */
    function getMaxRewardRate(
        address token
    ) external view returns (uint256) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        // Fix: Check if token exists in current rewardTokens mapping
        if (!$.isRewardToken[token]) {
            revert TokenDoesNotExist(token);
        }

        return $.maxRewardRates[token] > 0 ? $.maxRewardRates[token] : MAX_REWARD_RATE;
    }

    /**
     * @notice Get the current reward rate for a specific token.
     * @param token Address of the token to check.
     * @return The current reward rate for the token.
     */
    function getRewardRate(
        address token
    ) external view returns (uint256) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        return $.rewardRates[token];
    }

    /**
     * @notice Get detailed reward information for a specific token.
     * @param token Address of the token to check.
     * @return rewardRate Current reward rate for the token.
     * @return lastUpdateTime Most recent timestamp when any validator's reward was updated for this token.
     */
    function tokenRewardInfo(
        address token
    ) external view returns (uint256 rewardRate, uint256 lastUpdateTime) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        rewardRate = $.rewardRates[token];

        // Fix: Return the most recent validator update time for this token
        uint16[] memory validatorIds = $.validatorIds;
        lastUpdateTime = 0;
        for (uint256 i = 0; i < validatorIds.length; i++) {
            uint256 validatorUpdateTime = $.validatorLastUpdateTimes[validatorIds[i]][token];
            if (validatorUpdateTime > lastUpdateTime) {
                lastUpdateTime = validatorUpdateTime;
            }
        }
    }

    function getRewardRateCheckpointCount(
        address token
    ) external view returns (uint256) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        return $.rewardRateCheckpoints[token].length;
    }

    function getValidatorRewardRateCheckpointCount(uint16 validatorId, address token) external view returns (uint256) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        return $.validatorRewardRateCheckpoints[validatorId][token].length;
    }

    function getUserLastCheckpointIndex(
        address user,
        uint16 validatorId,
        address token
    ) external view returns (uint256) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        return $.userLastCheckpointIndex[user][validatorId][token];
    }

    function getRewardRateCheckpoint(
        address token,
        uint256 index
    ) external view returns (uint256 timestamp, uint256 rate, uint256 cumulativeIndex) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        if (index >= $.rewardRateCheckpoints[token].length) {
            revert InvalidRewardRateCheckpoint(token, index);
        }
        PlumeStakingStorage.RateCheckpoint memory checkpoint = $.rewardRateCheckpoints[token][index];
        return (checkpoint.timestamp, checkpoint.rate, checkpoint.cumulativeIndex);
    }

    function getValidatorRewardRateCheckpoint(
        uint16 validatorId,
        address token,
        uint256 index
    ) external view returns (uint256 timestamp, uint256 rate, uint256 cumulativeIndex) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        if (index >= $.validatorRewardRateCheckpoints[validatorId][token].length) {
            revert InvalidRewardRateCheckpoint(token, index);
        }
        PlumeStakingStorage.RateCheckpoint memory checkpoint =
            $.validatorRewardRateCheckpoints[validatorId][token][index];
        return (checkpoint.timestamp, checkpoint.rate, checkpoint.cumulativeIndex);
    }

    /**
     * @notice Get the treasury address.
     * @return The address of the treasury contract.
     */
    function getTreasury() external view returns (address) {
        return getTreasuryAddress();
    }

    /**
     * @notice Calculates the pending reward for a specific user, validator, and token.
     * @dev Calls the internal PlumeRewardLogic.calculateRewardsWithCheckpoints function.
     * @param user The user address.
     * @param validatorId The validator ID.
     * @param token The reward token address.
     * @return pendingReward The calculated reward amount for the user (after commission).
     */
    function getPendingRewardForValidator(
        address user,
        uint16 validatorId,
        address token
    ) external returns (uint256 pendingReward) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        // Required inputs for the internal logic function
        uint256 userStakedAmount = $.userValidatorStakes[user][validatorId].staked;
        // uint256 validatorCommission = $.validators[validatorId].commission; // Not needed for the 5-arg call

        // Call the internal logic function - only need the first return value
        (uint256 userRewardDelta,,) =
            PlumeRewardLogic.calculateRewardsWithCheckpoints($, user, validatorId, token, userStakedAmount);

        return userRewardDelta;
    }
    // --- END NEW PUBLIC WRAPPER ---

}
