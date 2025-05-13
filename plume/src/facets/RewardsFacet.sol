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
    RewardsAdded,
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
    address internal constant PLUME = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 internal constant REWARD_PRECISION = 1e18;
    uint256 internal constant BASE = 1e18;
    uint256 internal constant MAX_REWARD_RATE = 3171 * 1e9;

    // --- Storage Access ---
    bytes32 internal constant PLUME_STORAGE_POSITION = keccak256("plume.storage.PlumeStaking");

    // --- Treasury ---
    // Storage slot for treasury address
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

    function plumeStorage() internal pure returns (PlumeStakingStorage.Layout storage $) {
        bytes32 position = PLUME_STORAGE_POSITION;
        assembly {
            $.slot := position
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
    function _earned(address user, address token, uint16 validatorId) internal view returns (uint256 rewards) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        uint256 userStakedAmount = $.userValidatorStakes[user][validatorId].staked;
        if (userStakedAmount == 0) {
            // If no stake, only return previously calculated rewards stored in userRewards
            return $.userRewards[user][validatorId][token];
        }
        // Call the library function to calculate the current pending reward delta
        (uint256 userRewardDelta,) = PlumeRewardLogic.calculateRewardsWithCheckpoints(
            $, user, token, validatorId, userStakedAmount, $.validators[validatorId].commission
        );
        // Add the delta to any previously stored (but unclaimed) rewards
        rewards = $.userRewards[user][validatorId][token] + userRewardDelta;
        return rewards;
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
        PlumeStakingStorage.Layout storage $ = plumeStorage();
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

    function removeRewardToken(
        address token
    ) external onlyRole(PlumeRoles.REWARD_MANAGER_ROLE) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
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
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        if (tokens.length == 0) {
            revert EmptyArray();
        }
        if (tokens.length != rewardRates_.length) {
            revert ArrayLengthMismatch();
        }
        uint16[] memory validatorIds = $.validatorIds;
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 rate = rewardRates_[i];
            if (!$.isRewardToken[token]) {
                revert TokenDoesNotExist(token);
            }
            uint256 maxRate = $.maxRewardRates[token] > 0 ? $.maxRewardRates[token] : MAX_REWARD_RATE;
            if (rate > maxRate) {
                revert RewardRateExceedsMax();
            }
            for (uint256 j = 0; j < validatorIds.length; j++) {
                uint16 validatorId = validatorIds[j];
                PlumeRewardLogic.createRewardRateCheckpoint($, token, validatorId, rate);
            }
            $.rewardRates[token] = rate;
        }
        emit RewardRatesSet(tokens, rewardRates_);
    }

    function setMaxRewardRate(address token, uint256 newMaxRate) external onlyRole(PlumeRoles.REWARD_MANAGER_ROLE) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        if (!$.isRewardToken[token]) {
            revert TokenDoesNotExist(token);
        }
        if ($.rewardRates[token] > newMaxRate) {
            revert RewardRateExceedsMax();
        }
        $.maxRewardRates[token] = newMaxRate;
        emit MaxRewardRateUpdated(token, newMaxRate);
    }

    function addRewards(
        address token,
        uint256 amount
    ) external payable virtual nonReentrant onlyRole(PlumeRoles.REWARD_MANAGER_ROLE) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        if (!$.isRewardToken[token]) {
            revert TokenDoesNotExist(token);
        }

        address treasury = getTreasuryAddress();
        if (treasury == address(0)) {
            revert TreasuryNotSet();
        }

        // Check if treasury has sufficient funds - direct balance check
        if (token == PLUME) {
            // For native PLUME, check the treasury's ETH balance
            if (treasury.balance < amount) {
                revert InsufficientBalance(token, treasury.balance, amount);
            }
        } else {
            // For ERC20 tokens, check the token balance
            uint256 treasuryBalance = IERC20(token).balanceOf(treasury);
            if (treasuryBalance < amount) {
                revert InsufficientBalance(token, treasuryBalance, amount);
            }
        }

        uint16[] memory validatorIds = $.validatorIds;
        for (uint256 i = 0; i < validatorIds.length; i++) {
            // Use library function to update validator cumulative index
            PlumeRewardLogic.updateRewardPerTokenForValidator($, token, validatorIds[i]);
        }

        // Only update the accounting - actual funds remain in the treasury
        $.rewardsAvailable[token] += amount;
        emit RewardsAdded(token, amount);
    }

    // --- Claim Functions ---

    function claim(address token, uint16 validatorId) external nonReentrant returns (uint256) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();

        // If token is not active, only proceed if there are previously earned/stored rewards.
        // _earned will correctly use rate=0 for delta calculation if token is removed.
        if (!$.isRewardToken[token]) {
            if (_earned(msg.sender, token, validatorId) == 0) {
                revert TokenDoesNotExist(token);
            }
        }

        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }
        if (!$.validators[validatorId].active) {
            revert ValidatorInactive(validatorId);
        }
        uint256 userStakedAmount = $.userValidatorStakes[msg.sender][validatorId].staked;
        address user = msg.sender;

        // Call the library function which calculates the earned rewards
        (uint256 userRewardDelta, uint256 commissionAmount) = PlumeRewardLogic.calculateRewardsWithCheckpoints(
            $, user, token, validatorId, userStakedAmount, $.validators[validatorId].commission
        );

        // Calculate total reward as stored + computed delta
        uint256 reward = $.userRewards[user][validatorId][token] + userRewardDelta;
        if (reward > 0) {
            // Reset stored accumulated reward
            $.userRewards[user][validatorId][token] = 0;

            // Update user's last processed timestamp to current time
            $.userValidatorRewardPerTokenPaidTimestamp[user][validatorId][token] = block.timestamp;
            $.userValidatorRewardPerTokenPaid[user][validatorId][token] =
                $.validatorRewardPerTokenCumulative[validatorId][token];

            // Update validator commission
            if (commissionAmount > 0) {
                $.validatorAccruedCommission[validatorId][token] += commissionAmount;
            }

            // Transfer the reward from treasury to user
            _transferRewardFromTreasury(token, reward, user);

            emit RewardClaimedFromValidator(user, token, validatorId, reward);
        }
        return reward;
    }

    function claim(
        address token
    ) external nonReentrant returns (uint256) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();

        // If token is not active, check if there's anything claimable from any validator.
        // If not, and token is not active, then revert.
        if (!$.isRewardToken[token]) {
            bool canClaimRemovedToken = false;
            uint16[] memory validatorIdsLocal = $.userValidators[msg.sender];
            for (uint256 i = 0; i < validatorIdsLocal.length; i++) {
                if (_earned(msg.sender, token, validatorIdsLocal[i]) > 0) {
                    canClaimRemovedToken = true;
                    break;
                }
            }
            if (!canClaimRemovedToken) {
                revert TokenDoesNotExist(token);
            }
        }

        uint16[] memory validatorIds = $.userValidators[msg.sender];
        uint256 totalReward = 0;

        // For each validator the user has staked with
        for (uint256 i = 0; i < validatorIds.length; i++) {
            uint16 validatorId = validatorIds[i];
            if (!$.validators[validatorId].active) {
                continue;
            }
            address user = msg.sender;
            uint256 userStakedAmount = $.userValidatorStakes[user][validatorId].staked;

            // Call library function to calculate owed rewards
            (uint256 userRewardDelta, uint256 commissionAmount) = PlumeRewardLogic.calculateRewardsWithCheckpoints(
                $, user, token, validatorId, userStakedAmount, $.validators[validatorId].commission
            );

            // Calculate total reward as stored + computed delta
            uint256 rewardFromValidator = $.userRewards[user][validatorId][token] + userRewardDelta;
            if (rewardFromValidator > 0) {
                // Reset stored accumulated reward
                $.userRewards[user][validatorId][token] = 0;

                // Update user's last processed timestamp to current time
                $.userValidatorRewardPerTokenPaidTimestamp[user][validatorId][token] = block.timestamp;
                $.userValidatorRewardPerTokenPaid[user][validatorId][token] =
                    $.validatorRewardPerTokenCumulative[validatorId][token];

                totalReward += rewardFromValidator;

                // Update validator commission
                if (commissionAmount > 0) {
                    $.validatorAccruedCommission[validatorId][token] += commissionAmount;
                }

                emit RewardClaimedFromValidator(user, token, validatorId, rewardFromValidator);
            }
        }

        if (totalReward > 0) {
            // Transfer rewards from treasury to user
            _transferRewardFromTreasury(token, totalReward, msg.sender);

            emit RewardClaimed(msg.sender, token, totalReward);
        }
        return totalReward;
    }

    function claimAll() external nonReentrant returns (uint256[] memory) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        address[] memory tokens = $.rewardTokens;
        uint256[] memory claims = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            // No need to check if token is a reward token, as we're iterating through $.rewardTokens

            uint16[] memory validatorIds = $.userValidators[msg.sender];
            uint256 totalReward = 0;

            // For each validator the user has staked with
            for (uint256 j = 0; j < validatorIds.length; j++) {
                uint16 validatorId = validatorIds[j];
                if (!$.validators[validatorId].active) {
                    continue;
                }
                address user = msg.sender;
                uint256 userStakedAmount = $.userValidatorStakes[user][validatorId].staked;

                // Call library function to calculate owed rewards
                (uint256 userRewardDelta, uint256 commissionAmount) = PlumeRewardLogic.calculateRewardsWithCheckpoints(
                    $, user, token, validatorId, userStakedAmount, $.validators[validatorId].commission
                );

                // Calculate total reward as stored + computed delta
                uint256 rewardFromValidator = $.userRewards[user][validatorId][token] + userRewardDelta;
                if (rewardFromValidator > 0) {
                    // Reset stored accumulated reward
                    $.userRewards[user][validatorId][token] = 0;

                    // Update user's last processed timestamp to current time
                    $.userValidatorRewardPerTokenPaidTimestamp[user][validatorId][token] = block.timestamp;
                    $.userValidatorRewardPerTokenPaid[user][validatorId][token] =
                        $.validatorRewardPerTokenCumulative[validatorId][token];

                    totalReward += rewardFromValidator;

                    // Update validator commission
                    if (commissionAmount > 0) {
                        $.validatorAccruedCommission[validatorId][token] += commissionAmount;
                    }

                    emit RewardClaimedFromValidator(user, token, validatorId, rewardFromValidator);
                }
            }

            if (totalReward > 0) {
                // Transfer rewards from treasury to user
                _transferRewardFromTreasury(token, totalReward, msg.sender);

                claims[i] = totalReward;
                emit RewardClaimed(msg.sender, token, totalReward);
            }
        }
        return claims;
    }

    // --- Internal Functions ---

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

        // Update accounting
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        $.rewardsAvailable[token] = ($.rewardsAvailable[token] > amount) ? $.rewardsAvailable[token] - amount : 0;
    }

    function _isRewardToken(
        address token
    ) internal view returns (bool) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        return $.isRewardToken[token];
    }

    function _getTokenIndex(
        address token
    ) internal view returns (uint256) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();

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

    function earned(address user, address token) external view returns (uint256) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        uint16[] memory validatorIds = $.userValidators[user];
        uint256 totalEarned = 0;
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

    function getClaimableReward(address user, address token) external view returns (uint256) {
        // Same implementation as earned
        return this.earned(user, token);
    }

    function getRewardTokens() external view returns (address[] memory) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
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
        PlumeStakingStorage.Layout storage $ = plumeStorage();
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
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        return $.rewardRates[token];
    }

    /**
     * @notice Get detailed reward information for a specific token.
     * @param token Address of the token to check.
     * @return rewardRate Current reward rate for the token.
     * @return rewardsAvailable Amount of rewards available for this token.
     * @return lastUpdateTime Timestamp when the reward was last updated.
     */
    function tokenRewardInfo(
        address token
    ) external view returns (uint256 rewardRate, uint256 rewardsAvailable, uint256 lastUpdateTime) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        rewardRate = $.rewardRates[token];
        rewardsAvailable = $.rewardsAvailable[token];
        lastUpdateTime = $.lastUpdateTimes[token];
    }

    function getRewardRateCheckpointCount(
        address token
    ) external view returns (uint256) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        return $.rewardRateCheckpoints[token].length;
    }

    function getValidatorRewardRateCheckpointCount(uint16 validatorId, address token) external view returns (uint256) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        return $.validatorRewardRateCheckpoints[validatorId][token].length;
    }

    function getUserLastCheckpointIndex(
        address user,
        uint16 validatorId,
        address token
    ) external view returns (uint256) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        return $.userLastCheckpointIndex[user][validatorId][token];
    }

    function getRewardRateCheckpoint(
        address token,
        uint256 index
    ) external view returns (uint256 timestamp, uint256 rate, uint256 cumulativeIndex) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
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
        PlumeStakingStorage.Layout storage $ = plumeStorage();
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

    // --- NEW PUBLIC WRAPPER ---
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
    ) external view returns (uint256 pendingReward) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();

        // Required inputs for the internal logic function
        uint256 userStakedAmount = $.userValidatorStakes[user][validatorId].staked;
        uint256 validatorCommission = $.validators[validatorId].commission;

        // Call the internal logic function - only need the first return value
        (uint256 userRewardDelta,) = PlumeRewardLogic.calculateRewardsWithCheckpoints(
            $, user, token, validatorId, userStakedAmount, validatorCommission
        );

        return userRewardDelta;
    }
    // --- END NEW PUBLIC WRAPPER ---

}
