// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IPlumeStaking } from "../interfaces/IPlumeStaking.sol";
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
import {
    CoolingCompleted,
    RewardClaimed,
    RewardClaimedFromValidator,
    Staked,
    StakedOnBehalf,
    Unstaked,
    UnstakedFromValidator,
    Withdrawn
} from "../lib/PlumeEvents.sol";
import { PlumeStakingStorage } from "../lib/PlumeStakingStorage.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title PlumeStakingBase
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Base contract for the PlumeStaking system with core functionality
 */
abstract contract PlumeStakingBase is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    IPlumeStaking
{

    using SafeERC20 for IERC20;
    using Address for address payable;

    // Constants
    /// @notice Role for administrators of PlumeStaking
    bytes32 public constant override ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @notice Role for upgraders of PlumeStaking
    bytes32 public constant override UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    /// @notice Maximum reward rate: ~100% APY (3171 nanotoken per second per token)
    uint256 public constant override MAX_REWARD_RATE = 3171 * 1e9;
    /// @notice Scaling factor for reward calculations
    uint256 public constant override REWARD_PRECISION = 1e18;
    /// @notice Base unit for calculations (equivalent to REWARD_PRECISION)
    uint256 public constant override BASE = 1e18;
    /// @notice Address constant used to represent the native PLUME token
    address public constant override PLUME = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /**
     * @notice Initialize PlumeStaking
     * @param owner Address of the owner of PlumeStaking
     */
    function initialize(
        address owner
    ) public virtual override initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        $.minStakeAmount = 1e18;
        $.cooldownInterval = 7 days;

        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(ADMIN_ROLE, owner);
        _grantRole(UPGRADER_ROLE, owner);
    }

    /**
     * @notice Authorize upgrade by role
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER_ROLE) { }

    /**
     * @notice Stake PLUME to a specific validator
     * @param validatorId ID of the validator to stake to
     */
    function stake(
        uint16 validatorId
    ) external payable override returns (uint256) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

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
        uint256 fromWallet = 0;
        uint256 totalAmount = 0;

        // First, use cooling amount if available (regardless of cooldown status)
        if (info.cooled > 0) {
            // Determine how much to use from cooling - only use what's needed
            uint256 amountToUseFromCooling = msg.value > 0
                ? (msg.value < info.cooled ? msg.value : info.cooled) // Use only what's needed up to msg.value
                : info.cooled; // If no msg.value, use all cooling tokens

            fromCooling = amountToUseFromCooling;
            info.cooled -= fromCooling;
            $.totalCooling = ($.totalCooling > fromCooling) ? $.totalCooling - fromCooling : 0;

            // Only reset cooldown if all cooling tokens are used
            if (info.cooled == 0) {
                info.cooldownEnd = 0;
            }

            totalAmount += fromCooling;
        }

        // Second, use parked amount if available and more is needed
        uint256 remainingNeeded = msg.value > 0 ? (msg.value - fromCooling) : 0;
        if (info.parked > 0 && remainingNeeded > 0) {
            // Only use as much as needed from parked
            fromParked = remainingNeeded > info.parked ? info.parked : remainingNeeded;
            info.parked -= fromParked;
            totalAmount += fromParked;
            $.totalWithdrawable = ($.totalWithdrawable > fromParked) ? $.totalWithdrawable - fromParked : 0;
            remainingNeeded -= fromParked;
        }

        // Finally, use wallet amount if needed
        if (msg.value > 0 && remainingNeeded > 0) {
            fromWallet = remainingNeeded;
            totalAmount += fromWallet;
        }

        // Verify minimum stake amount
        if (totalAmount < $.minStakeAmount) {
            revert InvalidAmount(totalAmount);
        }

        // Update rewards before changing stake amount
        _updateRewardsForValidator(msg.sender, validatorId);

        // Update user's staked amount for this validator
        validatorInfo.staked += totalAmount;
        info.staked += totalAmount;

        // Update validator's delegated amount
        validator.delegatedAmount += totalAmount;

        // Update total staked amounts
        $.validatorTotalStaked[validatorId] += totalAmount;
        $.totalStaked += totalAmount;

        // Track user-validator relationship
        _addStakerToValidator(msg.sender, validatorId);

        // Update rewards again with new stake amount
        _updateRewardsForValidator(msg.sender, validatorId);

        emit Staked(msg.sender, validatorId, totalAmount, fromCooling, fromParked, fromWallet);
        return totalAmount;
    }

    /**
     * @notice Unstake PLUME from a specific validator
     * @param validatorId ID of the validator to unstake from
     * @return amount Amount of PLUME unstaked
     */
    function unstake(
        uint16 validatorId
    ) external override returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        PlumeStakingStorage.StakeInfo storage info = $.userValidatorStakes[msg.sender][validatorId];

        // Unstake the full amount
        if (info.staked > 0) {
            return _unstake(validatorId, info.staked);
        }

        // If no stake, revert with the appropriate error
        revert NoActiveStake();
    }

    /**
     * @notice Unstake a specific amount of PLUME from a specific validator
     * @param validatorId ID of the validator to unstake from
     * @param amount Amount of PLUME to unstake
     * @return amountUnstaked The amount actually unstaked
     */
    function unstake(uint16 validatorId, uint256 amount) external override returns (uint256 amountUnstaked) {
        return _unstake(validatorId, amount);
    }

    /**
     * @notice Internal implementation of unstake logic
     * @param validatorId ID of the validator to unstake from
     * @param amount Amount of PLUME to unstake
     * @return amountUnstaked The amount actually unstaked
     */
    function _unstake(uint16 validatorId, uint256 amount) internal returns (uint256 amountUnstaked) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

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

        // Limit amount to what's actually staked
        amountUnstaked = amount > info.staked ? info.staked : amount;

        // Update rewards before changing stake amount
        _updateRewardsForValidator(msg.sender, validatorId);

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
            // If there's an active cooldown, add to the existing cooling amount
            globalInfo.cooled += amountUnstaked;
            // Reset cooldown period to start from current timestamp
            globalInfo.cooldownEnd = block.timestamp + $.cooldownInterval;
        } else {
            // Start new cooldown period with unstaked amount
            globalInfo.cooled = amountUnstaked;
            globalInfo.cooldownEnd = block.timestamp + $.cooldownInterval;
        }

        // Update validator-specific cooling totals
        $.validatorTotalCooling[validatorId] += amountUnstaked;
        $.totalCooling += amountUnstaked;

        // Emit both events for backward compatibility
        emit Unstaked(msg.sender, validatorId, amountUnstaked);
        emit UnstakedFromValidator(msg.sender, validatorId, amountUnstaked);

        return amountUnstaked;
    }

    /**
     * @notice Withdraw PLUME that has completed the cooldown period
     * @return amount Amount of PLUME withdrawn
     */
    function withdraw() external override nonReentrant returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        PlumeStakingStorage.StakeInfo storage info = $.stakeInfo[msg.sender];

        // Calculate withdrawable amount
        amount = info.parked;
        if (info.cooled > 0 && info.cooldownEnd <= block.timestamp) {
            amount += info.cooled;
            info.cooled = 0;
            $.totalCooling = ($.totalCooling > info.cooled) ? $.totalCooling - info.cooled : 0;
        }

        if (amount == 0) {
            revert InvalidAmount(amount);
        }

        // Clear parked amount and update timestamp
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
     * @notice Claim rewards for a specific token from a specific validator
     * @param token Address of the token to claim
     * @param validatorId ID of the validator to claim from
     * @return amount Amount of reward token claimed
     */
    function _claimWithValidator(address token, uint16 validatorId) internal virtual returns (uint256 amount) {
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
     * @notice Claim rewards for a specific token from all validators
     * @param token Address of the token to claim
     * @return totalAmount Total amount of reward token claimed
     */
    function claim(
        address token
    ) external virtual override nonReentrant returns (uint256 totalAmount) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        if (!_isRewardToken(token)) {
            revert TokenDoesNotExist(token);
        }

        uint16[] memory userValidators = $.userValidators[msg.sender];
        totalAmount = 0;

        for (uint256 i = 0; i < userValidators.length; i++) {
            uint16 validatorId = userValidators[i];
            uint256 amount = _claimWithValidator(token, validatorId);
            totalAmount += amount;
        }

        return totalAmount;
    }

    /**
     * @notice Claim rewards for a specific token from a specific validator
     * @param token Address of the token to claim
     * @param validatorId ID of the validator to claim from
     * @return amount Amount of reward token claimed
     */
    function claim(address token, uint16 validatorId) external virtual override nonReentrant returns (uint256 amount) {
        return _claimWithValidator(token, validatorId);
    }

    /**
     * @notice Claim rewards for all tokens from all validators
     * @return totalAmount Total amount of all reward tokens claimed
     */
    function claimAll() external virtual override nonReentrant returns (uint256 totalAmount) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        address[] memory tokens = $.rewardTokens;
        uint16[] memory userValidators = $.userValidators[msg.sender];

        // For each token
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];

            if (!_isRewardToken(token)) {
                continue;
            }

            uint256 tokenTotalAmount = 0;

            // For each validator
            for (uint256 j = 0; j < userValidators.length; j++) {
                uint16 validatorId = userValidators[j];
                uint256 amount = _claimWithValidator(token, validatorId);
                tokenTotalAmount += amount;
            }

            totalAmount += tokenTotalAmount;
        }

        return totalAmount;
    }

    /**
     * @notice Get information about the staking contract
     */
    function stakingInfo()
        external
        view
        virtual
        override
        returns (
            uint256 totalStaked,
            uint256 totalCooling,
            uint256 totalWithdrawable,
            uint256 minStakeAmount,
            address[] memory rewardTokens
        )
    {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        return ($.totalStaked, $.totalCooling, $.totalWithdrawable, $.minStakeAmount, $.rewardTokens);
    }

    /**
     * @notice Get staking information for a user
     */
    function stakeInfo(
        address user
    ) external view virtual override returns (PlumeStakingStorage.StakeInfo memory) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        return $.stakeInfo[user];
    }

    /**
     * @notice Returns the amount of PLUME currently staked by the caller
     */
    function amountStaked() external view virtual override returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        return $.stakeInfo[msg.sender].staked;
    }

    /**
     * @notice Returns the amount of PLUME currently in cooling period for the caller
     */
    function amountCooling() external view virtual override returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        PlumeStakingStorage.StakeInfo storage info = $.stakeInfo[msg.sender];

        // If cooldown has ended, return 0
        if (info.cooldownEnd <= block.timestamp) {
            return 0;
        }

        return info.cooled;
    }

    /**
     * @notice Returns the amount of PLUME that is withdrawable for the caller
     */
    function amountWithdrawable() external view virtual override returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        PlumeStakingStorage.StakeInfo storage info = $.stakeInfo[msg.sender];

        amount = info.parked;
        // Add cooled amount if cooldown period has ended
        if (info.cooldownEnd <= block.timestamp) {
            amount += info.cooled;
        }

        return amount;
    }

    /**
     * @notice Get the claimable reward amount for a user and token across all validators
     * @param user Address of the user to check
     * @param token Address of the reward token
     * @return amount Amount of reward token claimable
     */
    function getClaimableReward(address user, address token) external view virtual override returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        if (!_isRewardToken(token)) {
            return 0;
        }

        uint16[] memory userValidators = $.userValidators[user];

        for (uint256 i = 0; i < userValidators.length; i++) {
            uint16 validatorId = userValidators[i];
            amount += _earned(user, token, validatorId);
        }

        return amount;
    }

    /**
     * @notice Stake PLUME to a specific validator on behalf of another user
     * @param validatorId ID of the validator to stake to
     * @param staker Address of the staker to stake on behalf of
     * @return Amount of PLUME staked
     */
    function stakeOnBehalf(uint16 validatorId, address staker) external payable returns (uint256) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

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

        // Update rewards before changing stake amount
        _updateRewardsForValidator(staker, validatorId);

        // Update staker's staked amount for this validator
        validatorInfo.staked += fromWallet;
        info.staked += fromWallet;

        // Update validator's delegated amount
        validator.delegatedAmount += fromWallet;

        // Update total staked amounts
        $.validatorTotalStaked[validatorId] += fromWallet;
        $.totalStaked += fromWallet;

        // Track staker-validator relationship
        _addStakerToValidator(staker, validatorId);

        // Update rewards again with new stake amount
        _updateRewardsForValidator(staker, validatorId);

        emit Staked(staker, validatorId, fromWallet, 0, 0, fromWallet);
        emit StakedOnBehalf(msg.sender, staker, validatorId, fromWallet);
        return fromWallet;
    }

    // Internal utility functions
    /**
     * @notice Add a staker to the list if they are not already in it
     */
    function _addStakerIfNew(
        address staker
    ) internal {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        if ($.stakeInfo[staker].staked > 0 && !$.isStaker[staker]) {
            $.stakers.push(staker);
            $.isStaker[staker] = true;
        }
    }

    /**
     * @notice Update rewards for a user
     */
    function _updateRewards(
        address user
    ) internal {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        // Get all validators the user has staked with
        uint16[] memory userValidators = $.userValidators[user];

        // Update rewards for each validator
        for (uint256 i = 0; i < userValidators.length; i++) {
            uint16 validatorId = userValidators[i];
            _updateRewardsForValidator(user, validatorId);
        }
    }

    /**
     * @notice Update the reward per token value
     * @param token The address of the reward token
     * @param validatorId The ID of the validator
     */
    function _updateRewardPerToken(address token, uint16 validatorId) internal {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        if ($.validatorTotalStaked[validatorId] > 0) {
            uint256 timeDelta = block.timestamp - $.validatorLastUpdateTimes[validatorId][token];
            if (timeDelta > 0 && $.rewardRates[token] > 0) {
                // Calculate reward with proper precision handling
                uint256 reward = timeDelta * $.rewardRates[token];
                reward = (reward * REWARD_PRECISION) / $.validatorTotalStaked[validatorId];
                $.validatorRewardPerTokenCumulative[validatorId][token] += reward;
            }
        }

        $.validatorLastUpdateTimes[validatorId][token] = block.timestamp;
    }

    /**
     * @notice Calculate the earned rewards for a user
     * @param user Address of the user
     * @param token Address of the token
     * @param validatorId ID of the validator
     * @return rewards Amount of rewards earned
     */
    function _earned(address user, address token, uint16 validatorId) internal view returns (uint256 rewards) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        // Get validator commission rate
        PlumeStakingStorage.ValidatorInfo storage validator = $.validators[validatorId];
        uint256 validatorCommission = validator.commission;

        // Get user's stake info
        uint256 userStakedAmount = $.userValidatorStakes[user][validatorId].staked;

        if (userStakedAmount == 0) {
            return 0;
        }

        uint256 rewardPerToken = $.validatorRewardPerTokenCumulative[validatorId][token];

        // If there are currently staked tokens, add the rewards that have accumulated since last update
        if ($.validatorTotalStaked[validatorId] > 0) {
            uint256 timeDelta = block.timestamp - $.validatorLastUpdateTimes[validatorId][token];
            if (timeDelta > 0 && $.rewardRates[token] > 0) {
                // Calculate reward with proper precision handling
                uint256 additionalReward = timeDelta * $.rewardRates[token];
                additionalReward = (additionalReward * REWARD_PRECISION) / $.validatorTotalStaked[validatorId];
                rewardPerToken += additionalReward;
            }
        }

        // Calculate reward delta
        uint256 rewardDelta = rewardPerToken - $.userValidatorRewardPerTokenPaid[user][validatorId][token];

        // Calculate user's portion with commission deducted
        uint256 userRewardAfterCommission = (userStakedAmount * rewardDelta * (REWARD_PRECISION - validatorCommission))
            / (REWARD_PRECISION * REWARD_PRECISION);

        return $.userRewards[user][validatorId][token] + userRewardAfterCommission;
    }

    /**
     * @notice Check if a token is in the rewards list
     */
    function _isRewardToken(
        address token
    ) internal view returns (bool) {
        return _getTokenIndex(token) < PlumeStakingStorage.layout().rewardTokens.length;
    }

    /**
     * @notice Get the index of a token in the rewards list
     */
    function _getTokenIndex(
        address token
    ) internal view returns (uint256) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        address[] memory tokens = $.rewardTokens;

        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token) {
                return i;
            }
        }

        return tokens.length;
    }

    /**
     * @notice Add a staker to a validator's staker list
     * @param staker Address of the staker
     * @param validatorId ID of the validator
     */
    function _addStakerToValidator(address staker, uint16 validatorId) internal virtual {
        // This delegate function is implemented in PlumeStakingValidator
        // Empty implementation in base to allow other contracts to override
    }

    /**
     * @notice Update rewards for a user on a specific validator
     * @param user Address of the user
     * @param validatorId ID of the validator
     */
    function _updateRewardsForValidator(address user, uint16 validatorId) internal virtual {
        // This delegate function is implemented in PlumeStakingValidator
        // Empty implementation in base to allow other contracts to override
    }

    /**
     * @notice Update the reward per token value for a specific validator
     * @param token The address of the reward token
     * @param validatorId The ID of the validator
     */
    function _updateRewardPerTokenForValidator(address token, uint16 validatorId) internal virtual {
        // This delegate function is implemented in PlumeStakingValidator
        // Empty implementation in base to allow other contracts to override
    }

    /**
     * @notice Update rewards for all stakers of a validator
     * @param validatorId ID of the validator
     */
    function _updateRewardsForAllValidatorStakers(
        uint16 validatorId
    ) internal virtual {
        // This delegate function is implemented in PlumeStakingValidator
        // Empty implementation in base to allow other contracts to override
    }

}
