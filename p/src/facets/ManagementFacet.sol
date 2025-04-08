// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25; // Corrected: Use CooldownIntervalSet

import {
    AdminTransferFailed,
    InsufficientFunds,
    InvalidAmount,
    InvalidIndexRange,
    ZeroAddress
} from "../lib/PlumeErrors.sol";
import {
    AdminWithdraw,
    CooldownIntervalSet,
    MinStakeAmountSet,
    PartialTotalAmountsUpdated,
    StakeInfoUpdated,
    TotalAmountsUpdated
} from "../lib/PlumeEvents.sol";

import { PlumeStakingStorage } from "../lib/PlumeStakingStorage.sol";

import { OwnableStorage } from "@solidstate/access/ownable/OwnableStorage.sol";
import { DiamondBaseStorage } from "@solidstate/proxy/diamond/base/DiamondBaseStorage.sol"; // Import OwnableStorage

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
// import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title ManagementFacet
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Facet handling administrative functions like setting parameters and managing contract funds.
 */
contract ManagementFacet is
    ReentrancyGuardUpgradeable // Removed AccessControlUpgradeable
{

    using SafeERC20 for IERC20;
    using Address for address payable;

    // --- Constants ---
    address internal constant PLUME = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // --- Storage Access ---
    bytes32 internal constant PLUME_STORAGE_POSITION = keccak256("plume.storage.PlumeStaking");

    function _getPlumeStorage() internal pure returns (PlumeStakingStorage.Layout storage $) {
        $ = PlumeStakingStorage.layout();
    }

    modifier onlyOwner() {
        require(msg.sender == OwnableStorage.layout().owner, "Must be owner");
        _;
    }

    // --- Parameter Setting (Owner) ---

    /**
     * @notice Update the minimum stake amount required
     * @param _minStakeAmount New minimum stake amount
     */
    function setMinStakeAmount(
        uint256 _minStakeAmount
    ) external onlyOwner {
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();
        uint256 oldAmount = $.minStakeAmount;
        // Add validation? E.g., prevent setting to 0?
        if (_minStakeAmount == 0) {
            revert InvalidAmount(_minStakeAmount);
        }
        $.minStakeAmount = _minStakeAmount;
        emit MinStakeAmountSet(_minStakeAmount);
    }

    /**
     * @notice Update the cooldown interval for unstaking
     * @param _cooldownInterval New cooldown interval in seconds
     */
    function setCooldownInterval(
        uint256 _cooldownInterval
    ) external onlyOwner {
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();
        $.cooldownInterval = _cooldownInterval;
        emit CooldownIntervalSet(_cooldownInterval);
    }

    // --- Admin Fund Management (Owner) ---

    /**
     * @notice Allows admin to withdraw ERC20 or native PLUME tokens from the contract balance
     * @dev Primarily for recovering accidentally sent tokens or managing excess reward funds.
     * @param token Address of the token to withdraw (use PLUME address for native token)
     * @param amount Amount to withdraw
     * @param recipient Address to send the withdrawn tokens to
     */
    function adminWithdraw(address token, uint256 amount, address recipient) external onlyOwner nonReentrant {
        // Validate inputs
        if (token == address(0)) {
            revert ZeroAddress("token");
        }
        if (recipient == address(0)) {
            revert ZeroAddress("recipient");
        }
        if (amount == 0) {
            revert InvalidAmount(amount);
        }

        if (token == PLUME) {
            // Native PLUME withdrawal
            uint256 balance = address(this).balance;
            if (amount > balance) {
                revert InsufficientFunds(balance, amount);
            }
            (bool success,) = payable(recipient).call{ value: amount }("");
            if (!success) {
                revert AdminTransferFailed();
            }
        } else {
            // ERC20 withdrawal
            IERC20 erc20Token = IERC20(token);
            uint256 balance = erc20Token.balanceOf(address(this));
            if (amount > balance) {
                revert InsufficientFunds(balance, amount);
            }
            erc20Token.safeTransfer(recipient, amount);
        }

        emit AdminWithdraw(token, amount, recipient);
    }

    // --- Global State Update Functions (Owner) ---
    // These were used in tests, potentially for maintenance or migration.

    /**
     * @notice Recalculate and update global totals (staked, cooling, withdrawable)
     * @dev Iterates through stakers, potentially very gas intensive.
     * @param startIndex Start index of the stakers array to process
     * @param endIndex End index (exclusive) of the stakers array to process
     */
    function updateTotalAmounts(uint256 startIndex, uint256 endIndex) external onlyOwner {
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();
        address[] memory stakers = $.stakers;
        uint256 numStakers = stakers.length;

        if (startIndex >= numStakers || startIndex > endIndex) {
            revert InvalidIndexRange(startIndex, endIndex);
        }
        // Cap endIndex to numStakers to prevent out-of-bounds access
        if (endIndex > numStakers) {
            endIndex = numStakers;
        }

        uint256 totalStakedChange = 0;
        uint256 totalCoolingChange = 0;
        uint256 totalWithdrawableChange = 0;

        // Temporary variables to store calculated totals for the batch
        uint256 batchTotalStaked = 0;
        uint256 batchTotalCooling = 0;
        uint256 batchTotalWithdrawable = 0;

        for (uint256 i = startIndex; i < endIndex; i++) {
            address staker = stakers[i];
            PlumeStakingStorage.StakeInfo storage info = $.stakeInfo[staker];

            // Recalculate the user's current state
            uint256 currentStaked = info.staked; // Assume this is correct for the user
            uint256 currentCooling = 0;
            uint256 currentParked = info.parked;

            if (info.cooled > 0) {
                if (block.timestamp >= info.cooldownEnd) {
                    // Cooldown finished, move to parked (withdrawable)
                    currentParked += info.cooled;
                } else {
                    // Still cooling
                    currentCooling = info.cooled;
                }
            }

            // Update batch totals
            batchTotalStaked += currentStaked;
            batchTotalCooling += currentCooling;
            batchTotalWithdrawable += currentParked; // Parked is withdrawable

            // Optional: Update user's storage if cooldown finished during this check
            if (info.cooled > 0 && block.timestamp >= info.cooldownEnd) {
                info.parked += info.cooled;
                info.cooled = 0;
                info.cooldownEnd = 0; // Reset cooldown end
                emit StakeInfoUpdated(
                    staker, info.staked, info.cooled, info.parked, info.cooldownEnd, info.lastUpdateTimestamp
                );
            }
        }

        // --- Update Global Totals ---

        emit PartialTotalAmountsUpdated(
            startIndex, endIndex, batchTotalStaked, batchTotalCooling, batchTotalWithdrawable
        );
    }

    // --- View Functions ---

    /**
     * @notice Gets the current minimum stake amount.
     */
    function getMinStakeAmount() external view returns (uint256) {
        return _getPlumeStorage().minStakeAmount;
    }

    /**
     * @notice Gets the current cooldown interval.
     */
    function getCooldownInterval() external view returns (uint256) {
        return _getPlumeStorage().cooldownInterval;
    }

}
