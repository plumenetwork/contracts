// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {
    ArrayLengthMismatch,
    EmptyArray,
    InsufficientBalance,
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

    function _distributeReward(address token, uint256 amount, address recipient) internal {
        address treasury = getTreasuryAddress();
        require(treasury != address(0), "Treasury not set");
        IPlumeStakingRewardTreasury(treasury).distributeReward(token, amount, recipient);
    }

    /**
     * @notice Stakes native token (PLUME) rewards without withdrawing them first.
     * @dev Calculates claimable native rewards from *all* validators the user is staked with,
     *      marks them as claimed internally, and stakes the total amount to the specified target validator.
     * @param targetValidatorId ID of the validator to stake the rewards to.
     * @return stakedAmount Amount of native PLUME rewards that were successfully staked.
     */
    function restakeRewards(
        uint16 targetValidatorId
    ) external nonReentrant returns (uint256 stakedAmount) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();

        // --- Validation ---
        // Verify target validator exists and is active
        require($.validatorExists[targetValidatorId], "Target validator does not exist");
        PlumeStakingStorage.ValidatorInfo storage targetValidator = $.validators[targetValidatorId];
        require(targetValidator.active, "Target validator is inactive");

        // Verify native token is a reward token
        address nativeToken = PLUME; // Use constant defined in this contract
        require(_isRewardToken(nativeToken), "Native token is not a reward token");

        // --- Calculate Total Native Rewards ---
        stakedAmount = 0;
        uint16[] memory userValidators = $.userValidators[msg.sender];

        for (uint256 i = 0; i < userValidators.length; i++) {
            uint16 currentValidatorId = userValidators[i];
            // Update rewards before calculating earned amount
            PlumeRewardLogic.updateRewardPerTokenForValidator($, nativeToken, currentValidatorId);
            uint256 earnedAmount = _earned(msg.sender, nativeToken, currentValidatorId);

            if (earnedAmount > 0) {
                stakedAmount += earnedAmount;
                // Mark rewards as claimed internally by resetting the user's reward state
                _resetUserRewards(msg.sender, nativeToken, currentValidatorId);
                emit RewardClaimedFromValidator(msg.sender, nativeToken, currentValidatorId, earnedAmount);
            }
        }

        // --- Stake the Calculated Amount ---
        if (stakedAmount > 0) {
            // Update rewards for the *target* validator before modifying its stake
            PlumeRewardLogic.updateRewardPerTokenForValidator($, nativeToken, targetValidatorId);

            // Update Storage (direct manipulation as internal stake call is complex)
            // Use .staked field from PlumeStakingStorage.StakeInfo
            PlumeStakingStorage.StakeInfo storage targetStakeInfo = $.userValidatorStakes[msg.sender][targetValidatorId];
            targetStakeInfo.staked += stakedAmount;
            // Use .staked field from PlumeStakingStorage.UserInfo
            $.stakeInfo[msg.sender].staked += stakedAmount; // Update global user stake info

            targetValidator.delegatedAmount += stakedAmount; // Update validator info
            $.validatorTotalStaked[targetValidatorId] += stakedAmount;
            $.totalStaked += stakedAmount; // Update global total staked

            // Ensure user is tracked as staker for target validator (simplified - assume exists or stake logic handles)
            // This logic might need refinement based on StakingFacet's handling of new stakers.
            bool found = false;
            for (uint256 i = 0; i < $.validatorStakers[targetValidatorId].length; i++) {
                if ($.validatorStakers[targetValidatorId][i] == msg.sender) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                $.validatorStakers[targetValidatorId].push(msg.sender);
                // Check if user needs to be added to global list too - depends on StakingFacet
                bool userListed = false;
                for (uint256 i = 0; i < $.userValidators[msg.sender].length; i++) {
                    if ($.userValidators[msg.sender][i] == targetValidatorId) {
                        userListed = true;
                        break;
                    }
                }
                if (!userListed) {
                    $.userValidators[msg.sender].push(targetValidatorId);
                }
            }

            // Update rewards for the *target* validator again *after* modifying its stake
            PlumeRewardLogic.updateRewardPerTokenForValidator($, nativeToken, targetValidatorId);

            // Emit Staked event (Note: fromWallet/Cooling/Parked are 0 as it comes from rewards)
            emit Staked(msg.sender, targetValidatorId, stakedAmount, 0, 0, 0);
        }

        return stakedAmount;
    }

    /**
     * @notice Internal function to reset user's reward state after claiming or restaking.
     * @dev Updates the user's paid index to the current validator cumulative index.
     */
    function _resetUserRewards(address user, address token, uint16 validatorId) internal {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        // Update the 'paid' marker to the current cumulative index for the validator
        // Access the correct mapping directly
        $.userValidatorRewardPerTokenPaid[user][validatorId][token] =
            $.validatorRewardPerTokenCumulative[validatorId][token];
        // Clear any previously calculated, stored rewards (as they are now accounted for)
        $.userRewards[user][validatorId][token] = 0;
    }

    // --- Global View Functions ---

    /**
     * @notice Get the total amount of PLUME staked in the contract.
     * @return amount Total amount of PLUME staked.
     */
    function totalAmountStaked() external view returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        return $.totalStaked;
    }

    /**
     * @notice Get the total amount of PLUME cooling in the contract.
     * @return amount Total amount of PLUME cooling.
     */
    function totalAmountCooling() external view returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        return $.totalCooling;
    }

    /**
     * @notice Get the total amount of PLUME withdrawable in the contract.
     * @return amount Total amount of PLUME withdrawable.
     */
    function totalAmountWithdrawable() external view returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
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
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        require(_isRewardToken(token), "Token is not a reward token");
        // Note: This value relies on being correctly updated during claim/restake operations.
        return $.totalClaimableByToken[token];
    }

}
