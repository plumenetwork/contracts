// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {
    AdminTransferFailed,
    IndexOutOfRange,
    InsufficientFunds,
    InvalidAmount,
    InvalidIndexRange,
    StakerExists,
    ZeroAddress
} from "../lib/PlumeErrors.sol";
import {
    AdminWithdraw,
    CooldownIntervalSet,
    MinStakeAmountSet,
    PartialTotalAmountsUpdated,
    StakeInfoUpdated,
    StakerAdded,
    TotalAmountsUpdated
} from "../lib/PlumeEvents.sol";
import { PlumeStakingStorage } from "../lib/PlumeStakingStorage.sol";
import { PlumeStakingRewards } from "./PlumeStakingRewards.sol";
/**
 * @title PlumeStakingManager
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Extension for administrative functionality
 */

contract PlumeStakingManager is PlumeStakingRewards {

    using SafeERC20 for IERC20;

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
            revert IndexOutOfRange(startIndex, stakersLength);
        }

        // If endIndex is 0 or greater than stakers length, set it to stakers length
        if (endIndex == 0 || endIndex > stakersLength) {
            endIndex = stakersLength;
        }

        if (startIndex >= endIndex) {
            revert InvalidIndexRange(startIndex, endIndex);
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
            if (balance - amount < totalLiabilities) {
                revert InsufficientFunds(balance - totalLiabilities, amount);
            }

            // Transfer native tokens
            (bool success,) = payable(recipient).call{ value: amount }("");
            if (!success) {
                revert AdminTransferFailed();
            }
        } else {
            // For ERC20 tokens
            IERC20(token).safeTransfer(recipient, amount);
        }

        emit AdminWithdraw(token, amount, recipient);
    }

    /**
     * @notice Set staking parameters (cooldown interval and/or minimum stake amount)
     * @param flags Bitmap: bit 0 = update cooldown, bit 1 = update min stake
     * @param newCooldownInterval New cooldown interval (if bit 0 set)
     * @param newMinStakeAmount New minimum stake amount (if bit 1 set)
     */
    function setStakingParams(
        uint8 flags,
        uint256 newCooldownInterval,
        uint256 newMinStakeAmount
    ) external onlyRole(ADMIN_ROLE) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        // Update cooldown interval if flag bit 0 is set
        if (flags & 1 != 0) {
            $.cooldownInterval = newCooldownInterval;
            emit CooldownIntervalSet(newCooldownInterval);
        }

        // Update minimum stake amount if flag bit 1 is set
        if (flags & 2 != 0) {
            $.minStakeAmount = newMinStakeAmount;
            emit MinStakeAmountSet(newMinStakeAmount);
        }
    }

    /**
     * @notice Set the cooldown interval
     * @param interval New cooldown interval in seconds
     */
    function setCooldownInterval(
        uint256 interval
    ) external onlyRole(ADMIN_ROLE) {
        PlumeStakingStorage.layout().cooldownInterval = interval;
        emit CooldownIntervalSet(interval);
    }

    /**
     * @notice Set the minimum stake amount
     * @param amount The new minimum stake amount
     */
    function setMinStakeAmount(
        uint256 amount
    ) external onlyRole(ADMIN_ROLE) {
        PlumeStakingStorage.layout().minStakeAmount = amount;
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

}
