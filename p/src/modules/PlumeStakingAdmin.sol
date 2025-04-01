// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { InvalidAmount, ZeroAddress } from "../lib/PlumeErrors.sol";
import { PlumeStakingStorage } from "../lib/PlumeStakingStorage.sol";
import { PlumeStakingBase } from "./PlumeStakingBase.sol";
/**
 * @title PlumeStakingAdmin
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Extension for administrative functionality
 */

contract PlumeStakingAdmin is PlumeStakingBase {

    using SafeERC20 for IERC20;

    // Events
    event MinStakeAmountSet(uint256 amount);
    event CooldownIntervalSet(uint256 interval);
    event TotalAmountsUpdated(uint256 totalStaked, uint256 totalCooling, uint256 totalWithdrawable);
    event PartialTotalAmountsUpdated(
        uint256 startIndex,
        uint256 endIndex,
        uint256 processedStaked,
        uint256 processedCooling,
        uint256 processedWithdrawable
    );
    event StakeInfoUpdated(
        address indexed user,
        uint256 staked,
        uint256 cooled,
        uint256 parked,
        uint256 cooldownEnd,
        uint256 lastUpdateTimestamp
    );
    event StakerAdded(address indexed staker);
    event AdminWithdraw(address indexed token, uint256 amount, address indexed recipient);

    // Admin helpers
    /**
     * @notice Admin function to recalculate and update total amounts
     * @param startIndex The starting index for processing stakers
     * @param endIndex The ending index for processing stakers (exclusive)
     * @dev Updates totalStaked, totalCooling, totalWithdrawable, and individual cooling amounts
     * @dev When endIndex == 0, it processes until the end of the stakers array
     */
    function updateTotalAmounts(uint256 startIndex, uint256 endIndex) external onlyRole(ADMIN_ROLE) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        uint256 newTotalStaked = 0;
        uint256 newTotalCooling = 0;
        uint256 newTotalWithdrawable = 0;

        // Ensure indices are within bounds
        uint256 stakersLength = $.stakers.length;
        if (startIndex >= stakersLength) {
            revert("Start index out of bounds");
        }

        // If endIndex is 0 or greater than stakers length, set it to stakers length
        if (endIndex == 0 || endIndex > stakersLength) {
            endIndex = stakersLength;
        }

        if (startIndex >= endIndex) {
            revert("Invalid index range");
        }

        // Process specified range of stakers
        for (uint256 i = startIndex; i < endIndex; i++) {
            address staker = $.stakers[i];
            PlumeStakingStorage.StakeInfo storage info = $.stakeInfo[staker];

            // Add to staked total
            newTotalStaked += info.staked;

            // Check and update cooling amounts
            if (info.cooled > 0) {
                if (info.cooldownEnd != 0 && block.timestamp >= info.cooldownEnd) {
                    // Cooldown period has ended, move to parked
                    info.parked += info.cooled;
                    info.cooled = 0;
                    info.cooldownEnd = 0;
                } else {
                    // Still in cooling period
                    newTotalCooling += info.cooled;
                }
            }

            // Add to withdrawable total
            newTotalWithdrawable += info.parked;
        }

        // If this is a full update (processing all stakers), update the storage totals
        if (startIndex == 0 && endIndex == stakersLength) {
            $.totalStaked = newTotalStaked;
            $.totalCooling = newTotalCooling;
            $.totalWithdrawable = newTotalWithdrawable;
            emit TotalAmountsUpdated(newTotalStaked, newTotalCooling, newTotalWithdrawable);
        } else {
            // This is a partial update, only emit event with processed amounts
            emit PartialTotalAmountsUpdated(startIndex, endIndex, newTotalStaked, newTotalCooling, newTotalWithdrawable);
        }
    }

    /**
     * @notice Admin function to set a user's stake info
     * @param user Address of the user
     * @param staked Amount staked
     * @param cooled Amount in cooling
     * @param parked Amount parked (withdrawable)
     * @param cooldownEnd Timestamp when cooldown ends
     * @param lastUpdateTimestamp Last reward update timestamp
     */
    function setStakeInfo(
        address user,
        uint256 staked,
        uint256 cooled,
        uint256 parked,
        uint256 cooldownEnd,
        uint256 lastUpdateTimestamp
    ) external onlyRole(ADMIN_ROLE) nonReentrant {
        if (user == address(0)) {
            revert ZeroAddress("user");
        }

        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        PlumeStakingStorage.StakeInfo storage info = $.stakeInfo[user];

        // Update user's stake info
        info.staked = staked;
        info.cooled = cooled;
        info.parked = parked;
        info.cooldownEnd = cooldownEnd;

        // Add user to stakers list if they have any funds
        if (staked > 0 || cooled > 0 || parked > 0) {
            _addStakerIfNew(user);
        }

        // Update rewards for all tokens
        _updateRewards(user);

        emit StakeInfoUpdated(user, staked, cooled, parked, cooldownEnd, lastUpdateTimestamp);
    }

    /**
     * @notice Admin function to manually add a staker to tracking
     * @param staker Address of the staker to add
     * @dev Will revert if address is zero or already a staker
     */
    function addStaker(
        address staker
    ) external onlyRole(ADMIN_ROLE) nonReentrant {
        if (staker == address(0)) {
            revert ZeroAddress("staker");
        }

        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        if ($.isStaker[staker]) {
            revert("Already a staker");
        }

        $.stakers.push(staker);
        $.isStaker[staker] = true;

        emit StakerAdded(staker);
    }

    /**
     * @notice Allows admin to withdraw any token from the contract
     * @param token Address of the token to withdraw (use PLUME for native tokens)
     * @param amount Amount of tokens to withdraw
     * @param recipient Address to receive the tokens
     */
    function adminWithdraw(
        address token,
        uint256 amount,
        address recipient
    ) external onlyRole(ADMIN_ROLE) nonReentrant {
        if (token == address(0)) {
            revert ZeroAddress("token");
        }
        if (recipient == address(0)) {
            revert ZeroAddress("recipient");
        }
        if (amount == 0) {
            revert InvalidAmount(0);
        }

        // For native token (PLUME)
        if (token == PLUME) {
            uint256 totalStaked = PlumeStakingStorage.layout().totalStaked;
            uint256 totalCooling = PlumeStakingStorage.layout().totalCooling;
            uint256 totalWithdrawable = PlumeStakingStorage.layout().totalWithdrawable;

            uint256 totalLiabilities = totalStaked + totalCooling + totalWithdrawable;

            // Add estimated pending rewards if PLUME is a reward token
            if (_isRewardToken(PLUME)) {
                totalLiabilities += PlumeStakingStorage.layout().totalClaimableByToken[PLUME];
            }
            uint256 balance = address(this).balance;
            require(balance - amount >= totalLiabilities, "Cannot withdraw user funds");

            // Transfer native tokens
            (bool success,) = payable(recipient).call{ value: amount }("");
            require(success, "Native token transfer failed");
        } else {
            // For ERC20 tokens
            IERC20(token).safeTransfer(recipient, amount);
        }

        emit AdminWithdraw(token, amount, recipient);
    }

    /**
     * @notice Set the cooldown interval
     * @param interval New cooldown interval in seconds
     */
    function setCooldownInterval(
        uint256 interval
    ) external onlyRole(ADMIN_ROLE) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        $.cooldownInterval = interval;
        emit CooldownIntervalSet(interval);
    }

    /**
     * @notice Set the minimum stake amount
     * @param amount The new minimum stake amount
     */
    function setMinStakeAmount(
        uint256 amount
    ) external onlyRole(ADMIN_ROLE) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        $.minStakeAmount = amount;
        emit MinStakeAmountSet(amount);
    }

    /**
     * @notice Get the minimum staking amount
     * @return Minimum amount of PLUME that can be staked
     */
    function getMinStakeAmount() external view returns (uint256) {
        return PlumeStakingStorage.layout().minStakeAmount;
    }

    /**
     * @notice Get the cooldown interval
     * @return Cooldown interval duration in seconds
     */
    function cooldownInterval() external view returns (uint256) {
        return PlumeStakingStorage.layout().cooldownInterval;
    }

    // Empty implementations of abstract functions that will be overridden in PlumeStaking
    function _addStakerToValidator(address staker, uint16 validatorId) internal virtual override { }
    function _updateRewardsForValidator(address user, uint16 validatorId) internal virtual override { }
    function _updateRewardPerTokenForValidator(address token, uint16 validatorId) internal virtual override { }
    function _updateRewardsForAllValidatorStakers(
        uint16 validatorId
    ) internal virtual override { }

}
