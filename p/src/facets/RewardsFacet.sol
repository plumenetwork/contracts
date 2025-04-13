// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {
    ArrayLengthMismatch,
    EmptyArray,
    InvalidAmount,
    InvalidRewardRateCheckpoint,
    NativeTransferFailed,
    RewardRateExceedsMax,
    TokenAlreadyExists,
    TokenDoesNotExist,
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
        require(IAccessControl(address(this)).hasRole(_role, msg.sender), "Caller does not have the required role");
        _;
    }

    // --- Internal View Function (_earned) ---
    // NOTE: The implementation of _earned here now depends on the library's
    // calculateRewardsWithCheckpoints for consistency, but it's still needed
    // as the public view entry point.
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
    ) external onlyRole(PlumeRoles.ADMIN_ROLE) {
        require(_treasury != address(0), "Treasury cannot be zero address");
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
        if (_isRewardToken(token)) {
            revert TokenAlreadyExists();
        }
        $.rewardTokens.push(token);
        for (uint256 i = 0; i < $.validatorIds.length; i++) {
            $.validatorLastUpdateTimes[$.validatorIds[i]][token] = block.timestamp;
        }
        emit RewardTokenAdded(token);
    }

    function removeRewardToken(
        address token
    ) external onlyRole(PlumeRoles.REWARD_MANAGER_ROLE) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        uint256 tokenIndex = _getTokenIndex(token);
        if (tokenIndex >= $.rewardTokens.length) {
            revert TokenDoesNotExist(token);
        }
        // Update rewards using the library before removing
        for (uint256 i = 0; i < $.validatorIds.length; i++) {
            // Needs to update the cumulative index, not user rewards
            PlumeRewardLogic.updateRewardPerTokenForValidator($, token, $.validatorIds[i]);
        }
        $.rewardRates[token] = 0;
        $.rewardTokens[tokenIndex] = $.rewardTokens[$.rewardTokens.length - 1];
        $.rewardTokens.pop();
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
            if (!_isRewardToken(token)) {
                revert TokenDoesNotExist(token);
            }
            uint256 maxRate = $.maxRewardRates[token] > 0 ? $.maxRewardRates[token] : MAX_REWARD_RATE;
            if (rate > maxRate) {
                revert RewardRateExceedsMax();
            }
            for (uint256 j = 0; j < validatorIds.length; j++) {
                uint16 validatorId = validatorIds[j];
                PlumeRewardLogic.updateRewardPerTokenForValidator($, token, validatorId);
                PlumeRewardLogic.createRewardRateCheckpoint($, token, validatorId, rate); // Use library
            }
            $.rewardRates[token] = rate;
        }
        emit RewardRatesSet(tokens, rewardRates_);
    }

    function setMaxRewardRate(address token, uint256 newMaxRate) external onlyRole(PlumeRoles.REWARD_MANAGER_ROLE) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        if (!_isRewardToken(token)) {
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
        if (!_isRewardToken(token)) {
            revert TokenDoesNotExist(token);
        }

        address treasury = getTreasuryAddress();
        require(treasury != address(0), "Treasury not set");

        // Check if treasury has sufficient funds
        bool hasFunds = IPlumeStakingRewardTreasury(treasury).hasEnoughBalance(token, amount);
        require(hasFunds, "Insufficient funds in treasury");

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
        if (!_isRewardToken(token)) {
            revert TokenDoesNotExist(token);
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
        if (!_isRewardToken(token)) {
            revert TokenDoesNotExist(token);
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
        require(treasury != address(0), "Treasury not set");

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
        address[] memory rewardTokens = $.rewardTokens;
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (rewardTokens[i] == token) {
                return true;
            }
        }
        return false;
    }

    function _getTokenIndex(
        address token
    ) internal view returns (uint256) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        address[] memory rewardTokens = $.rewardTokens;
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (rewardTokens[i] == token) {
                return i;
            }
        }
        revert TokenDoesNotExist(token);
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

    function getMaxRewardRate(
        address token
    ) external view returns (uint256) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        return $.maxRewardRates[token] > 0 ? $.maxRewardRates[token] : MAX_REWARD_RATE;
    }

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
     * @notice Gets the current treasury address
     * @return The address of the current treasury contract
     */
    function getTreasury() external view returns (address) {
        return getTreasuryAddress();
    }

}
