// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {
    ActionOnSlashedValidatorError,
    CooldownNotComplete,
    CooldownPeriodNotEnded,
    ExceedsValidatorCapacity,
    InsufficientCooldownBalance,
    InsufficientCooledAndParkedBalance,
    InsufficientFunds,
    InternalInconsistency,
    InvalidAmount,
    NativeTransferFailed,
    NoActiveStake,
    NoRewardsToRestake,
    NoWithdrawableBalanceToRestake,
    NotActive,
    StakeAmountTooSmall,
    TokenDoesNotExist,
    TooManyStakers,
    TransferError,
    ValidatorCapacityExceeded,
    ValidatorDoesNotExist,
    ValidatorInactive,
    ValidatorPercentageExceeded,
    ZeroAddress,
    ZeroRecipientAddress
} from "../lib/PlumeErrors.sol";

import {
    CooldownStarted,
    RewardClaimedFromValidator,
    RewardsRestaked,
    Staked,
    StakedOnBehalf,
    Unstaked,
    Withdrawn
} from "../lib/PlumeEvents.sol";

import { PlumeRewardLogic } from "../lib/PlumeRewardLogic.sol";
import { PlumeStakingStorage } from "../lib/PlumeStakingStorage.sol";
import { PlumeValidatorLogic } from "../lib/PlumeValidatorLogic.sol";

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

using PlumeRewardLogic for PlumeStakingStorage.Layout;

interface IRewardsGetter {

    function getPendingRewardForValidator(
        address user,
        uint16 validatorId,
        address token
    ) external returns (uint256 pendingReward);

}

/**
 * @title StakingFacet
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Facet containing core user staking, unstaking, and withdrawal functions.
 */
contract StakingFacet is ReentrancyGuardUpgradeable {

    using SafeERC20 for IERC20;
    using Address for address payable;

    function _checkValidatorSlashedAndRevert(
        uint16 validatorId
    ) internal view {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        if ($.validatorExists[validatorId] && $.validators[validatorId].slashed) {
            revert ActionOnSlashedValidatorError(validatorId);
        }
    }

    /**
     * @dev Validates that a validator exists and is active (not slashed)
     * @param validatorId The validator ID to validate
     */
    function _validateValidatorForStaking(
        uint16 validatorId
    ) internal view {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }
        _checkValidatorSlashedAndRevert(validatorId);
        if (!$.validators[validatorId].active) {
            revert ValidatorInactive(validatorId);
        }
    }

    /**
     * @dev Validates that a stake amount meets minimum requirements
     * @param amount The amount to validate
     */
    function _validateStakeAmount(
        uint256 amount
    ) internal view {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        if (amount == 0) {
            revert InvalidAmount(0);
        }
        if (amount < $.minStakeAmount) {
            revert StakeAmountTooSmall(amount, $.minStakeAmount);
        }
    }

    /**
     * @dev Combined validation for staking operations
     * @param validatorId The validator ID to validate
     * @param amount The amount to validate
     */
    function _validateStaking(uint16 validatorId, uint256 amount) internal view {
        _validateValidatorForStaking(validatorId);
        _validateStakeAmount(amount);
    }

    /**
     * @dev Validates that validator capacity limits are not exceeded
     * @param validatorId The validator ID to check
     * @param stakeAmount The amount being staked (for error reporting)
     */
    function _validateValidatorCapacity(uint16 validatorId, uint256 stakeAmount) internal view {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        // Check if exceeding validator capacity
        uint256 newDelegatedAmount = $.validators[validatorId].delegatedAmount;
        uint256 maxCapacity = $.validators[validatorId].maxCapacity;
        if (maxCapacity > 0 && newDelegatedAmount > maxCapacity) {
            revert ExceedsValidatorCapacity(validatorId, newDelegatedAmount, maxCapacity, stakeAmount);
        }
    }

    /**
     * @dev Validates that validator percentage limits are not exceeded
     * @param validatorId The validator ID to check
     */
    function _validateValidatorPercentage(
        uint16 validatorId, uint256 stakeAmount
    ) internal view {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        uint256 previousTotalStaked = $.totalStaked - stakeAmount;

        // Check if exceeding validator percentage limit
        if (previousTotalStaked > 0 && $.maxValidatorPercentage > 0) {
            uint256 newDelegatedAmount = $.validators[validatorId].delegatedAmount;
            uint256 validatorPercentage = (newDelegatedAmount * 10_000) / $.totalStaked;
            if (validatorPercentage > $.maxValidatorPercentage) {
                revert ValidatorPercentageExceeded();
            }
        }
    }

    /**
     * @dev Performs both capacity and percentage validation checks
     * @param validatorId The validator ID to check
     * @param stakeAmount The amount being staked (for error reporting)
     */
    function _validateCapacityLimits(uint16 validatorId, uint256 stakeAmount) internal view {
        _validateValidatorCapacity(validatorId, stakeAmount);
        _validateValidatorPercentage(validatorId, stakeAmount);
    }

    /**
     * @dev Validates that a validator exists and is not slashed (for unstaking operations)
     * @param validatorId The validator ID to validate
     */
    function _validateValidatorForUnstaking(
        uint16 validatorId
    ) internal view {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }
        _checkValidatorSlashedAndRevert(validatorId);
    }

    /**
     * @dev Performs all common staking setup and validation for new stakes
     * @param user The user performing the stake
     * @param validatorId The validator to stake to
     * @param stakeAmount The amount being staked
     * @return isNewStake Whether this is a new stake for this user-validator pair
     */
    function _performStakeSetup(
        address user,
        uint16 validatorId,
        uint256 stakeAmount
    ) internal returns (bool isNewStake) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        // Use consolidated validation
        _validateStaking(validatorId, stakeAmount);

        // Check if this is a new stake for this specific validator
        isNewStake = $.userValidatorStakes[user][validatorId].staked == 0;

        if (!isNewStake) {
            // If user is adding to an existing stake with this validator, settle their current rewards first
            PlumeRewardLogic.updateRewardsForValidator($, user, validatorId);
        } else {
            // Initialize reward state for new stakes BEFORE updating stake amounts
            // This ensures that commission calculations use the old totalStaked amount (before this user's stake)
            _initializeRewardStateForNewStake(user, validatorId);
        }

        // Update stake amount AFTER reward state initialization
        _updateStakeAmounts(user, validatorId, stakeAmount);

        // Validate capacity limits
        _validateCapacityLimits(validatorId, stakeAmount);

        // Add user to validator's staker list
        PlumeValidatorLogic.addStakerToValidator($, user, validatorId);
    }

    /**
     * @dev Performs common restaking workflow from cooled/parked funds
     * @param user The user performing the restake
     * @param validatorId The validator to restake to
     * @param amount The amount to restake
     * @param fromSource Description of fund source for events
     */
    function _performRestakeWorkflow(
        address user,
        uint16 validatorId,
        uint256 amount,
        string memory fromSource
    ) internal {
        // Use consolidated validation
        _validateStaking(validatorId, amount);

        // Update rewards before any balance changes
        PlumeRewardLogic.updateRewardsForValidator(PlumeStakingStorage.layout(), user, validatorId);

        // Update stake amounts
        _updateStakeAmounts(user, validatorId, amount);

        // Ensure staker is properly listed for the validator
        PlumeValidatorLogic.addStakerToValidator(PlumeStakingStorage.layout(), user, validatorId);
    }

    /**
     * @notice Stake PLUME to a specific validator using only wallet funds
     * @param validatorId ID of the validator to stake to
     */
    function stake(
        uint16 validatorId
    ) external payable returns (uint256) {
        uint256 stakeAmount = msg.value;

        // Perform all common staking setup
        bool isNewStake = _performStakeSetup(msg.sender, validatorId, stakeAmount);

        // Emit stake event
        emit Staked(msg.sender, validatorId, stakeAmount, 0, 0, stakeAmount);

        return stakeAmount;
    }

    /**
     * @notice Restake PLUME that is currently in cooldown or parked for a specific validator.
     * Prioritizes cooldown funds first, then parked funds. Performs full validation including
     * capacity limits and reward state initialization for new stakes.
     * @param validatorId ID of the validator to restake to.
     * @param amount Amount of PLUME to restake.
     */
    function restake(uint16 validatorId, uint256 amount) external nonReentrant {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        address user = msg.sender;

        if (amount == 0) {
            revert InvalidAmount(0);
        }

        // --- SAFE VALIDATION (Check-Then-Act) ---
        // 1. Atomically process matured cooldowns to update parked balance. This provides a clean state.
        _processMaturedCooldowns(user);

        // 2. Now calculate total available funds from this clean state.
        // Available funds = currently parked + any UNMATURED cooldown from the target validator.
        uint256 parkedAmount = $.stakeInfo[user].parked;
        uint256 unmaturedCooldownFromTarget = $.userValidatorCooldowns[user][validatorId].amount;
        uint256 totalAvailable = parkedAmount + unmaturedCooldownFromTarget;

        if (totalAvailable < amount) {
            revert InsufficientCooledAndParkedBalance(totalAvailable, amount);
        }

        // --- EXECUTION (Act) ---
        // 3. SETUP & EXECUTE RESTAKE
        _performStakeSetup(user, validatorId, amount);

        uint256 fromCooled = 0;
        uint256 fromParked = 0;
        uint256 remaining = amount;

        // Priority 1: Use from unmatured cooldown of the target validator.
        if (remaining > 0 && unmaturedCooldownFromTarget > 0) {
            uint256 useAmount = remaining > unmaturedCooldownFromTarget ? unmaturedCooldownFromTarget : remaining;
            fromCooled = useAmount;
            remaining -= useAmount;
            _removeCoolingAmounts(user, validatorId, useAmount);
        }

        // Priority 2: Use from parked amount if needed
        if (remaining > 0) {
            uint256 currentParked = $.stakeInfo[user].parked;
            if (remaining > currentParked) {
                // This should not be reachable if the initial validation was correct.
                revert InternalInconsistency("Insufficient parked funds for restake allocation");
            }
            fromParked = remaining;
            _removeParkedAmounts(user, fromParked);
        }

        emit Staked(user, validatorId, amount, fromCooled, fromParked, 0);
    }

    /**
     * @notice Unstake PLUME from a specific validator (full amount)
     * @param validatorId ID of the validator to unstake from
     * @return amount Amount of PLUME unstaked
     */
    function unstake(
        uint16 validatorId
    ) external returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        PlumeStakingStorage.UserValidatorStake storage userStake = $.userValidatorStakes[msg.sender][validatorId];

        if (userStake.staked > 0) {
            return _unstake(validatorId, userStake.staked);
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
        if (amount == 0) {
            revert InvalidAmount(0);
        }
        return _unstake(validatorId, amount);
    }

    /**
     * @notice Internal logic for unstaking, handles moving stake to cooling or parked.
     * @param validatorId ID of the validator to unstake from.
     * @param amount The amount of PLUME to unstake. If 0, unstakes all.
     * @return amountToUnstake The actual amount that was unstaked.
     */
    function _unstake(uint16 validatorId, uint256 amount) internal returns (uint256 amountToUnstake) {
        PlumeStakingStorage.Layout storage $s = PlumeStakingStorage.layout();

        // Validate unstaking conditions
        _validateValidatorForUnstaking(validatorId);
        if (amount == 0) {
            revert InvalidAmount(amount);
        }
        if ($s.userValidatorStakes[msg.sender][validatorId].staked < amount) {
            revert InsufficientFunds($s.userValidatorStakes[msg.sender][validatorId].staked, amount);
        }

        // Update rewards before balance changes
        PlumeRewardLogic.updateRewardsForValidator($s, msg.sender, validatorId);

        // Update stake amounts
        _updateUnstakeAmounts(msg.sender, validatorId, amount);

        // Process cooldown logic and cleanup
        uint256 newCooldownEndTimestamp = _processCooldownLogic(msg.sender, validatorId, amount);
        _handlePostUnstakeCleanup(msg.sender, validatorId);

        emit CooldownStarted(msg.sender, validatorId, amount, newCooldownEndTimestamp);
        return amount;
    }

    /**
     * @notice Withdraw all PLUME that is available in the parked balance (matured cooldowns)
     */
    function withdraw() external {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        address user = msg.sender;


        // Process matured cooldowns into parked balance
        _processMaturedCooldowns(user);

        uint256 amountToWithdraw = $.stakeInfo[user].parked;
        if (amountToWithdraw == 0) {
            revert InvalidAmount(0);
        }

        // Remove from parked and transfer
        _removeParkedAmounts(user, amountToWithdraw);

        // Clean up validator relationships for validators where user has no remaining involvement
        _cleanupValidatorRelationships(user);

        emit Withdrawn(user, amountToWithdraw);

        (bool success,) = user.call{ value: amountToWithdraw }("");
        if (!success) {
            revert NativeTransferFailed();
        }
    }

    /**
     * @notice Stake PLUME to a specific validator on behalf of another user
     * @param validatorId ID of the validator to stake to
     * @param staker Address of the staker to stake on behalf of
     * @return Amount of PLUME staked
     */
    function stakeOnBehalf(uint16 validatorId, address staker) external payable returns (uint256) {
        if (staker == address(0)) {
            revert ZeroRecipientAddress();
        }

        uint256 stakeAmount = msg.value;

        // Perform all common staking setup for the beneficiary
        bool isNewStake = _performStakeSetup(staker, validatorId, stakeAmount);

        // Emit events
        emit Staked(staker, validatorId, stakeAmount, 0, 0, stakeAmount);
        emit StakedOnBehalf(msg.sender, staker, validatorId, stakeAmount);

        return stakeAmount;
    }

    /**
     * @notice Restakes the user's entire pending native PLUME rewards to a specific validator.
     * Also processes any matured cooldowns into the user's parked balance.
     * @param validatorId ID of the validator to stake the rewards to.
     * @return amountRestaked The total amount of pending rewards successfully restaked.
     */
    function restakeRewards(
        uint16 validatorId
    ) external nonReentrant returns (uint256 amountRestaked) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        address user = msg.sender;

        // Process matured cooldowns first
        _processMaturedCooldowns(user);

        // Verify target validator and calculate rewards
        _validateValidatorForStaking(validatorId);
        address tokenToRestake = PlumeStakingStorage.PLUME_NATIVE;
        if (!$.isRewardToken[tokenToRestake]) {
            revert TokenDoesNotExist(tokenToRestake);
        }

        // Calculate and claim all pending rewards with proper cleanup
        amountRestaked = _calculateAndClaimAllRewardsWithCleanup(user, tokenToRestake);

        // Validate restake amount
        if (amountRestaked == 0) {
            revert NoRewardsToRestake();
        }
        if (amountRestaked < $.minStakeAmount) {
            revert StakeAmountTooSmall(amountRestaked, $.minStakeAmount);
        }

        // Use proper stake setup instead of restake workflow - this handles:
        // 1. New stake reward state initialization
        // 2. Existing stake reward settlement
        // 3. Capacity validation
        // 4. Validator relationship management
        bool isNewStake = _performStakeSetup(user, validatorId, amountRestaked);

        // Emit events
        emit Staked(user, validatorId, amountRestaked, 0, 0, amountRestaked);
        emit RewardsRestaked(user, validatorId, amountRestaked);

        return amountRestaked;
    }

    // --- View Functions ---

    /**
     * @notice Returns the amount of PLUME currently staked by the caller
     */
    function amountStaked() external view returns (uint256 amount) {
        return PlumeStakingStorage.layout().stakeInfo[msg.sender].staked;
    }

    /**
     * @notice Returns the amount of PLUME currently in cooling period for the caller.
     * This now dynamically calculates funds in active, non-matured cooldowns.
     */
    function amountCooling() external view returns (uint256 activelyCoolingAmount) {
        return _calculateActivelyCoolingAmount(msg.sender);
    }

    /**
     * @notice Returns the amount of PLUME that is withdrawable for the caller.
     * This includes already parked funds plus any funds in matured cooldowns.
     * For slashed validators, cooled funds are only considered withdrawable if their
     * cooldownEndTime was *before* the validator's slashedAtTimestamp.
     */
    function amountWithdrawable() external view returns (uint256 totalWithdrawableAmount) {
        return _calculateTotalWithdrawableAmount(msg.sender);
    }

    /**
     * @notice Get staking information for a user (global stake info)
     */
    function stakeInfo(
        address user
    ) external view returns (PlumeStakingStorage.StakeInfo memory) {
        return PlumeStakingStorage.layout().stakeInfo[user];
    }

    /**
     * @notice Get the total amount of PLUME staked in the contract.
     * @return amount Total amount of PLUME staked.
     */
    function totalAmountStaked() external view returns (uint256 amount) {
        return PlumeStakingStorage.layout().totalStaked;
    }

    /**
     * @notice Get the total amount of PLUME cooling in the contract.
     * @return amount Total amount of PLUME cooling.
     */
    function totalAmountCooling() external view returns (uint256 amount) {
        return PlumeStakingStorage.layout().totalCooling;
    }

    /**
     * @notice Get the total amount of PLUME withdrawable in the contract.
     * @return amount Total amount of PLUME withdrawable.
     */
    function totalAmountWithdrawable() external view returns (uint256 amount) {
        return PlumeStakingStorage.layout().totalWithdrawable;
    }

    /**
     * @notice Get the total amount of a specific token claimable across all users.
     * @param token Address of the token to check.
     * @return amount Total amount of the token claimable.
     */
    function totalAmountClaimable(
        address token
    ) external view returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        // Check if token is a reward token using the mapping
        require($.isRewardToken[token], "Token is not a reward token");

        // Return the total claimable amount
        return $.totalClaimableByToken[token];
    }

    /**
     * @notice Get the staked amount for a specific user on a specific validator.
     * @param user The address of the user.
     * @param validatorId The ID of the validator.
     * @return The staked amount.
     */
    function getUserValidatorStake(address user, uint16 validatorId) external view returns (uint256) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        return $.userValidatorStakes[user][validatorId].staked;
    }

    struct CooldownView {
        // Define struct for the return type
        uint16 validatorId;
        uint256 amount;
        uint256 cooldownEndTime;
    }

    /**
     * @notice Get all active cooldown entries for a specific user.
     * @param user The address of the user.
     * @return An array of CooldownView structs.
     */
    function getUserCooldowns(
        address user
    ) external view returns (CooldownView[] memory) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        uint16[] storage userAssociatedValidators = $.userValidators[user];

        uint256 activeCooldownCount = _countActiveCooldowns(user);
        CooldownView[] memory cooldowns = new CooldownView[](activeCooldownCount);
        uint256 currentIndex = 0;

        // Populate the array
        for (uint256 i = 0; i < userAssociatedValidators.length; i++) {
            uint16 validatorId_iterator = userAssociatedValidators[i];
            if ($.validatorExists[validatorId_iterator] && !$.validators[validatorId_iterator].slashed) {
                PlumeStakingStorage.CooldownEntry storage entry = $.userValidatorCooldowns[user][validatorId_iterator];
                if (entry.amount > 0) {
                    cooldowns[currentIndex] = CooldownView({
                        validatorId: validatorId_iterator,
                        amount: entry.amount,
                        cooldownEndTime: entry.cooldownEndTime
                    });
                    currentIndex++;
                }
            }
        }
        return cooldowns;
    }

    /**
     * @dev Updates all stake-related storage when adding stake to a validator
     * @param user The user address
     * @param validatorId The validator ID
     * @param amount The amount being staked
     */
    function _updateStakeAmounts(address user, uint16 validatorId, uint256 amount) internal {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        $.userValidatorStakes[user][validatorId].staked += amount;
        $.stakeInfo[user].staked += amount;
        $.validators[validatorId].delegatedAmount += amount;
        $.validatorTotalStaked[validatorId] += amount;
        $.totalStaked += amount;
    }

    /**
     * @dev Updates all stake-related storage when removing stake from a validator
     * @param user The user address
     * @param validatorId The validator ID
     * @param amount The amount being unstaked
     */
    function _updateUnstakeAmounts(address user, uint16 validatorId, uint256 amount) internal {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        $.userValidatorStakes[user][validatorId].staked -= amount;
        $.stakeInfo[user].staked -= amount;
        $.validators[validatorId].delegatedAmount -= amount;
        $.validatorTotalStaked[validatorId] -= amount;
        $.totalStaked -= amount;
    }

    /**
     * @dev Updates cooling-related storage when moving funds to cooling state
     * @param user The user address
     * @param validatorId The validator ID
     * @param amount The amount being moved to cooling
     */
    function _updateCoolingAmounts(address user, uint16 validatorId, uint256 amount) internal {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        $.stakeInfo[user].cooled += amount;
        $.totalCooling += amount;
        $.validatorTotalCooling[validatorId] += amount;
    }

    /**
     * @dev Removes cooling amounts from both global and validator-specific state
     * @param user The user address
     * @param validatorId The validator ID to remove cooling amounts from
     * @param amount The amount being removed from cooling
     */
    function _removeCoolingAmounts(address user, uint16 validatorId, uint256 amount) internal {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        bool isSlashed = $.validators[validatorId].slashed;

        // Update user's global cooling amounts - this always happens
        if ($.stakeInfo[user].cooled >= amount) {
            $.stakeInfo[user].cooled -= amount;
        } else {
            $.stakeInfo[user].cooled = 0;
        }

        // Only update global and validator totals if the validator was NOT slashed
        // because these totals were already decremented during the slash event.
        if (!isSlashed) {
            // Update global total cooling
            if ($.totalCooling >= amount) {
                $.totalCooling -= amount;
            } else {
                $.totalCooling = 0;
            }
            // Update validator total cooling
            if ($.validatorTotalCooling[validatorId] >= amount) {
                $.validatorTotalCooling[validatorId] -= amount;
            } else {
                $.validatorTotalCooling[validatorId] = 0;
            }
        }

        // Update user's specific cooldown entry for the validator - this always happens
        PlumeStakingStorage.CooldownEntry storage entry = $.userValidatorCooldowns[user][validatorId];
        if (entry.amount >= amount) {
            entry.amount -= amount;
            if (entry.amount == 0) {
                entry.cooldownEndTime = 0;
            }
        } else {
            entry.amount = 0;
            entry.cooldownEndTime = 0;
        }
    }

    /**
     * @dev Updates parked amounts for withdrawal
     * @param user The user address
     * @param amount The amount to move to parked state
     */
    function _updateParkedAmounts(address user, uint256 amount) internal {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        $.stakeInfo[user].parked += amount;
        $.totalWithdrawable += amount;
    }

    /**
     * @dev Updates withdrawal amounts after a successful withdrawal
     * @param user The user address
     * @param amount The amount being withdrawn
     */
    function _updateWithdrawalAmounts(address user, uint256 amount) internal {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        $.stakeInfo[user].parked = 0;
        if ($.totalWithdrawable >= amount) {
            $.totalWithdrawable -= amount;
        } else {
            $.totalWithdrawable = 0;
        }
    }

    /**
     * @dev Updates reward claim tracking when rewards are claimed
     * @param user The user address
     * @param validatorId The validator ID
     * @param token The reward token address
     * @param amount The reward amount being claimed
     */
    function _updateRewardClaim(address user, uint16 validatorId, address token, uint256 amount) internal {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        // Reset stored accumulated reward
        $.userRewards[user][validatorId][token] = 0;

        // Update user's last processed timestamp to current time
        $.userValidatorRewardPerTokenPaidTimestamp[user][validatorId][token] = block.timestamp;
        $.userValidatorRewardPerTokenPaid[user][validatorId][token] =
            $.validatorRewardPerTokenCumulative[validatorId][token];

        // Update total claimable tracking
        if ($.totalClaimableByToken[token] >= amount) {
            $.totalClaimableByToken[token] -= amount;
        } else {
            $.totalClaimableByToken[token] = 0;
        }
    }

    /**
     * @dev Updates commission claim tracking when commission is claimed
     * @param validatorId The validator ID
     * @param token The reward token address
     * @param amount The commission amount being claimed
     * @param recipient The recipient address
     */
    function _updateCommissionClaim(uint16 validatorId, address token, uint256 amount, address recipient) internal {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        $.pendingCommissionClaims[validatorId][token] = PlumeStakingStorage.PendingCommissionClaim({
            amount: amount,
            requestTimestamp: block.timestamp,
            token: token,
            recipient: recipient
        });

        // Zero out accrued commission immediately
        $.validatorAccruedCommission[validatorId][token] = 0;
    }

    /**
     * @dev Removes parked (withdrawable) amounts
     * @param user The user address
     * @param amount The amount being removed from parked state
     */
    function _removeParkedAmounts(address user, uint256 amount) internal {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        $.stakeInfo[user].parked -= amount;
        $.totalWithdrawable -= amount;
    }

    // ====================================================================================
    // ============================= COMPLEX LOGIC FUNCTIONS ===========================
    // ====================================================================================

    /**
     * @dev Processes cooldown logic for unstaking operations
     * @param user The user address
     * @param validatorId The validator ID
     * @param amount The amount being unstaked
     * @return newCooldownEndTime The timestamp when the new cooldown ends
     */
    function _processCooldownLogic(
        address user,
        uint16 validatorId,
        uint256 amount
    ) internal returns (uint256 newCooldownEndTime) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        PlumeStakingStorage.CooldownEntry storage cooldownEntrySlot = $.userValidatorCooldowns[user][validatorId];

        uint256 currentCooledAmountInSlot = cooldownEntrySlot.amount;
        uint256 currentCooldownEndTimeInSlot = cooldownEntrySlot.cooldownEndTime;

        uint256 finalNewCooledAmountForSlot;
        newCooldownEndTime = block.timestamp + $.cooldownInterval;

        if (currentCooledAmountInSlot > 0 && block.timestamp >= currentCooldownEndTimeInSlot) {
            // Previous cooldown for this slot has matured - move to parked and start new cooldown
            _updateParkedAmounts(user, currentCooledAmountInSlot);
            _removeCoolingAmounts(user, validatorId, currentCooledAmountInSlot);
            _updateCoolingAmounts(user, validatorId, amount);
            finalNewCooledAmountForSlot = amount;
        } else {
            // No matured cooldown - add to existing cooldown
            _updateCoolingAmounts(user, validatorId, amount);
            finalNewCooledAmountForSlot = currentCooledAmountInSlot + amount;
        }

        cooldownEntrySlot.amount = finalNewCooledAmountForSlot;
        cooldownEntrySlot.cooldownEndTime = newCooldownEndTime;

        return newCooldownEndTime;
    }

    /**
     * @dev Processes matured cooldowns and moves them to parked balance
     * @param user The user address
     * @return amountMovedToParked Total amount moved from cooled to parked
     */
    function _processMaturedCooldowns(
        address user
    ) internal returns (uint256 amountMovedToParked) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        amountMovedToParked = 0;

        // Make a copy to avoid iteration issues when removeStakerFromValidator is called
        uint16[] memory userAssociatedValidators = $.userValidators[user];

        for (uint256 i = 0; i < userAssociatedValidators.length; i++) {
            uint16 validatorId = userAssociatedValidators[i];
            PlumeStakingStorage.CooldownEntry memory cooldownEntry = $.userValidatorCooldowns[user][validatorId];

            if (cooldownEntry.amount == 0) {
                continue;
            }


            bool canRecoverFromThisCooldown = _canRecoverFromCooldown(user, validatorId, cooldownEntry);

            if (canRecoverFromThisCooldown) {
                uint256 amountInThisCooldown = cooldownEntry.amount;
                amountMovedToParked += amountInThisCooldown;

                _removeCoolingAmounts(user, validatorId, amountInThisCooldown);
                delete $.userValidatorCooldowns[user][validatorId];

                // Remove staker if they have no remaining stake with this validator
                if ($.userValidatorStakes[user][validatorId].staked == 0) {
                    PlumeValidatorLogic.removeStakerFromValidator($, user, validatorId);
                }
            }
        }

        if (amountMovedToParked > 0) {
            _updateParkedAmounts(user, amountMovedToParked);
        }

        return amountMovedToParked;
    }

    /**
     * @dev Determines if a cooldown can be recovered (considering slashing)
     * @param user The user address
     * @param validatorId The validator ID
     * @param cooldownEntry The cooldown entry to check
     * @return canRecover True if the cooldown can be recovered
     */
    function _canRecoverFromCooldown(
        address user,
        uint16 validatorId,
        PlumeStakingStorage.CooldownEntry memory cooldownEntry
    ) internal view returns (bool canRecover) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        if (!$.validatorExists[validatorId]) {
            return false;
        }

        if ($.validators[validatorId].slashed) {
            // Validator is slashed - check if cooldown ended BEFORE the slash
            uint256 slashTs = $.validators[validatorId].slashedAtTimestamp;
            return (cooldownEntry.cooldownEndTime < slashTs && block.timestamp >= cooldownEntry.cooldownEndTime);
        } else {
            // Validator is not slashed - check if cooldown matured normally
            return (block.timestamp >= cooldownEntry.cooldownEndTime);
        }
    }

    /**
     * @dev Processes reward state initialization for new stakes
     * @param user The user address
     * @param validatorId The validator ID
     */
    function _initializeRewardStateForNewStake(address user, uint16 validatorId) internal {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        $.userValidatorStakeStartTime[user][validatorId] = block.timestamp;

        address[] memory rewardTokens = $.rewardTokens;
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            if ($.isRewardToken[token]) {
                PlumeRewardLogic.updateRewardPerTokenForValidator($, token, validatorId);

                $.userValidatorRewardPerTokenPaid[user][validatorId][token] =
                    $.validatorRewardPerTokenCumulative[validatorId][token];
                $.userValidatorRewardPerTokenPaidTimestamp[user][validatorId][token] = block.timestamp;
            }
        }
    }

    /**
     * @dev Calculates and claims all pending rewards for a user across all validators with proper cleanup
     * @param user The user address
     * @param targetToken The token to calculate rewards for
     * @return totalRewards Total rewards claimed
     */
    function _calculateAndClaimAllRewardsWithCleanup(
        address user,
        address targetToken
    ) internal returns (uint256 totalRewards) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        totalRewards = 0;

        // Make a copy to avoid iteration issues
        uint16[] memory currentUserValidators = $.userValidators[user];

        // Track validators that might need cleanup after claiming
        uint16[] memory validatorsToCheck = new uint16[](currentUserValidators.length);
        uint256 checkCount = 0;

        for (uint256 i = 0; i < currentUserValidators.length; i++) {
            uint16 userValidatorId = currentUserValidators[i];

            uint256 existingRewards = $.userRewards[user][userValidatorId][targetToken];
            uint256 rewardDelta =
                IRewardsGetter(address(this)).getPendingRewardForValidator(user, userValidatorId, targetToken);
            uint256 totalValidatorReward = existingRewards + rewardDelta;

            if (totalValidatorReward > 0) {
                totalRewards += totalValidatorReward;
                PlumeRewardLogic.updateRewardsForValidator($, user, userValidatorId);
                $.userRewards[user][userValidatorId][targetToken] = 0;

                if ($.totalClaimableByToken[targetToken] >= totalValidatorReward) {
                    $.totalClaimableByToken[targetToken] -= totalValidatorReward;
                } else {
                    $.totalClaimableByToken[targetToken] = 0;
                }

                emit RewardClaimedFromValidator(user, targetToken, userValidatorId, totalValidatorReward);

                // Clear pending rewards flag for this validator and track for cleanup
                PlumeRewardLogic.clearPendingRewardsFlagIfEmpty($, user, userValidatorId);

                // Track this validator for potential relationship cleanup
                validatorsToCheck[checkCount] = userValidatorId;
                checkCount++;
            }
        }

        // Clean up validator relationships for validators where user has no remaining involvement
        for (uint256 i = 0; i < checkCount; i++) {
            PlumeValidatorLogic.removeStakerFromValidator($, user, validatorsToCheck[i]);
        }

        return totalRewards;
    }

    /**
     * @dev Handles post-unstake validator relationship cleanup
     * @param user The user address
     * @param validatorId The validator ID
     */
    function _handlePostUnstakeCleanup(address user, uint16 validatorId) internal {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        if ($.userValidatorStakes[user][validatorId].staked == 0) {
            PlumeValidatorLogic.removeStakerFromValidator($, user, validatorId);
        }
    }

    /**
     * @dev Counts active cooldowns for a user (used by view functions)
     * @param user The user address
     * @return count Number of active cooldowns
     */
    function _countActiveCooldowns(
        address user
    ) internal view returns (uint256 count) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        uint16[] storage userAssociatedValidators = $.userValidators[user];
        count = 0;

        for (uint256 i = 0; i < userAssociatedValidators.length; i++) {
            uint16 validatorId = userAssociatedValidators[i];
            if (
                $.validatorExists[validatorId] && !$.validators[validatorId].slashed
                    && $.userValidatorCooldowns[user][validatorId].amount > 0
            ) {
                count++;
            }
        }

        return count;
    }

    /**
     * @dev Calculates actively cooling amount for a user
     * @param user The user address
     * @return activelyCoolingAmount Total amount in active cooldowns
     */
    function _calculateActivelyCoolingAmount(
        address user
    ) internal view returns (uint256 activelyCoolingAmount) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        uint16[] storage userAssociatedValidators = $.userValidators[user];
        activelyCoolingAmount = 0;

        for (uint256 i = 0; i < userAssociatedValidators.length; i++) {
            uint16 validatorId = userAssociatedValidators[i];
            if ($.validatorExists[validatorId] && !$.validators[validatorId].slashed) {
                PlumeStakingStorage.CooldownEntry storage cooldownEntry = $.userValidatorCooldowns[user][validatorId];
                if (cooldownEntry.amount > 0 && block.timestamp < cooldownEntry.cooldownEndTime) {
                    activelyCoolingAmount += cooldownEntry.amount;
                }
            }
        }

        return activelyCoolingAmount;
    }

    /**
     * @dev Calculates total withdrawable amount for a user (including matured cooldowns)
     * @param user The user address
     * @return totalWithdrawableAmount Total amount available for withdrawal
     */
    function _calculateTotalWithdrawableAmount(
        address user
    ) internal view returns (uint256 totalWithdrawableAmount) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        uint16[] storage userAssociatedValidators = $.userValidators[user];

        totalWithdrawableAmount = $.stakeInfo[user].parked;

        for (uint256 i = 0; i < userAssociatedValidators.length; i++) {
            uint16 validatorId = userAssociatedValidators[i];
            PlumeStakingStorage.CooldownEntry storage cooldownEntry = $.userValidatorCooldowns[user][validatorId];

            if (cooldownEntry.amount > 0 && block.timestamp >= cooldownEntry.cooldownEndTime) {
                if ($.validatorExists[validatorId] && $.validators[validatorId].slashed) {
                    // Only withdrawable if cooldown ended before slash
                    if (cooldownEntry.cooldownEndTime < $.validators[validatorId].slashedAtTimestamp) {
                        totalWithdrawableAmount += cooldownEntry.amount;
                    }
                } else if ($.validatorExists[validatorId] && !$.validators[validatorId].slashed) {
                    totalWithdrawableAmount += cooldownEntry.amount;
                }
            }
        }

        return totalWithdrawableAmount;
    }

    /**
     * @dev Cleans up validator relationships for validators where user has no remaining involvement
     * @param user The user address
     */
    function _cleanupValidatorRelationships(
        address user
    ) internal {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        PlumeValidatorLogic.removeStakerFromAllValidators($, user);
    }

    /**
     * @dev Calculates and claims all pending rewards for a user across all validators
     * @param user The user address
     * @param targetToken The token to calculate rewards for
     * @return totalRewards Total rewards claimed
     */
    function _calculateAndClaimAllRewards(address user, address targetToken) internal returns (uint256 totalRewards) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        totalRewards = 0;

        // Make a copy to avoid iteration issues
        uint16[] memory currentUserValidators = $.userValidators[user];

        for (uint256 i = 0; i < currentUserValidators.length; i++) {
            uint16 userValidatorId = currentUserValidators[i];

            uint256 existingRewards = $.userRewards[user][userValidatorId][targetToken];
            uint256 rewardDelta =
                IRewardsGetter(address(this)).getPendingRewardForValidator(user, userValidatorId, targetToken);
            uint256 totalValidatorReward = existingRewards + rewardDelta;

            if (totalValidatorReward > 0) {
                totalRewards += totalValidatorReward;
                PlumeRewardLogic.updateRewardsForValidator($, user, userValidatorId);
                $.userRewards[user][userValidatorId][targetToken] = 0;

                if ($.totalClaimableByToken[targetToken] >= totalValidatorReward) {
                    $.totalClaimableByToken[targetToken] -= totalValidatorReward;
                } else {
                    $.totalClaimableByToken[targetToken] = 0;
                }

                emit RewardClaimedFromValidator(user, targetToken, userValidatorId, totalValidatorReward);
            }
        }

        return totalRewards;
    }

}
