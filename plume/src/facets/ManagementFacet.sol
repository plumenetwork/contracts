// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {
    AdminTransferFailed,
    InsufficientFunds,
    InvalidAmount,
    InvalidIndexRange,
    Unauthorized,
    ZeroAddress
} from "../lib/PlumeErrors.sol";
import {
    AdminStakeCorrection,
    AdminWithdraw,
    CooldownIntervalSet,
    MaxSlashVoteDurationSet,
    MinStakeAmountSet,
    PartialTotalAmountsUpdated,
    StakeInfoUpdated
} from "../lib/PlumeEvents.sol";

import { PlumeStakingStorage } from "../lib/PlumeStakingStorage.sol";

import { OwnableStorage } from "@solidstate/access/ownable/OwnableStorage.sol";
import { DiamondBaseStorage } from "@solidstate/proxy/diamond/base/DiamondBaseStorage.sol";

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { OwnableInternal } from "@solidstate/access/ownable/OwnableInternal.sol"; // For inherited onlyOwner

import { PlumeRoles } from "../lib/PlumeRoles.sol";

import { IAccessControl } from "../interfaces/IAccessControl.sol";
import { ValidatorFacet } from "./ValidatorFacet.sol";

/**
 * @title ManagementFacet
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Facet handling administrative functions like setting parameters and managing contract funds.
 */
contract ManagementFacet is ReentrancyGuardUpgradeable, OwnableInternal {

    using SafeERC20 for IERC20;
    using Address for address payable;

    // --- Constants ---
    address internal constant PLUME = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // --- Storage Access ---
    bytes32 internal constant PLUME_STORAGE_POSITION = keccak256("plume.storage.PlumeStaking");

    function _getPlumeStorage() internal pure returns (PlumeStakingStorage.Layout storage $) {
        bytes32 position = PLUME_STORAGE_POSITION;
        assembly {
            $.slot := position
        }
    }

    // --- Modifiers ---

    /**
     * @dev Modifier to check role using the AccessControlFacet.
     * Assumes AccessControlFacet is deployed and added to the diamond.
     */
    modifier onlyRole(
        bytes32 _role
    ) {
        if (!IAccessControl(address(this)).hasRole(_role, msg.sender)) {
            revert Unauthorized(msg.sender, _role);
        }
        _;
    }

    /**
     * @notice Update the minimum stake amount required
     * @dev Requires ADMIN_ROLE.
     * @param _minStakeAmount New minimum stake amount
     */
    function setMinStakeAmount(
        uint256 _minStakeAmount
    ) external onlyRole(PlumeRoles.ADMIN_ROLE) {
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
     * @dev Requires ADMIN_ROLE.
     * @param _cooldownInterval New cooldown interval in seconds
     */
    function setCooldownInterval(
        uint256 _cooldownInterval
    ) external onlyRole(PlumeRoles.ADMIN_ROLE) {
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();
        $.cooldownInterval = _cooldownInterval;
        emit CooldownIntervalSet(_cooldownInterval);
    }

    // --- Admin Fund Management (Roles) ---

    /**
     * @notice Allows admin to withdraw ERC20 or native PLUME tokens from the contract balance
     * @dev Primarily for recovering accidentally sent tokens or managing excess reward funds.
     * Requires ADMIN_ROLE.
     * @param token Address of the token to withdraw (use PLUME address for native token)
     * @param amount Amount to withdraw
     * @param recipient Address to send the withdrawn tokens to
     */
    function adminWithdraw(
        address token,
        uint256 amount,
        address recipient
    ) external onlyRole(PlumeRoles.TIMELOCK_ROLE) nonReentrant {
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

    // --- Global State Update Functions (Roles) ---

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

    /**
     * @notice Set the maximum duration for slashing votes (ADMIN_ROLE only).
     * @param duration The new duration in seconds.
     */
    function setMaxSlashVoteDuration(
        uint256 duration
    ) external onlyRole(PlumeRoles.ADMIN_ROLE) {
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();
        $.maxSlashVoteDurationInSeconds = duration;

        emit MaxSlashVoteDurationSet(duration);
    }

    // --- Admin Data Correction ---

    /**
     * @notice Admin function to recalculate and correct a user's total staked amount in stakeInfoMap.
     * @dev This is useful if past inconsistencies occurred between global and per-validator stakes.
     * Requires caller to have ADMIN_ROLE.
     * @param user The address of the user whose stake info needs correction.
     */
    function adminCorrectUserStakeInfo(
        address user
    ) external onlyRole(PlumeRoles.ADMIN_ROLE) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        if (user == address(0)) {
            revert ZeroAddress("user");
        }

        // Get the list of validators the user is currently staked with.
        // We need to call the ValidatorFacet for this information.
        // Assuming the ValidatorFacet interface/address is accessible or known.
        // NOTE: This requires the ManagementFacet to somehow call or have access to ValidatorFacet's getUserValidators.
        // A cleaner approach might be to put this function directly in ValidatorFacet if it needs validator data,
        // or pass the validator list as an argument.
        // For simplicity here, we'll assume direct access to storage is sufficient if getUserValidators is complex to
        // call across facets.

        // Alternative (less ideal, requires knowing potential validators):
        // Iterate through ALL validators and check stake? Less efficient.

        // Preferred: Recalculate by summing userValidatorStakes.
        // This requires iterating through the user's validator stakes stored in PlumeStakingStorage.
        // Solidity maps are not iterable directly. We need the list of validators the user *might* be staked with.
        // Calling getUserValidators is the clean way.

        // Simplified approach for script: Assume we know the relevant validator IDs (e.g., from off-chain data or logs)
        // OR, if getUserValidators is available via the diamond proxy:

        // Let's assume we can get the list via the proxy (this is the best approach)
        uint16[] memory validatorIds = ValidatorFacet(address(this)).getUserValidators(user);

        uint256 correctTotalStake = 0;
        for (uint256 i = 0; i < validatorIds.length; i++) {
            correctTotalStake += $.userValidatorStakes[user][validatorIds[i]].staked; // Access .staked member
        }

        uint256 oldTotalStake = $.stakeInfo[user].staked; // Use correct mapping name 'stakeInfo'
        if (correctTotalStake != oldTotalStake) {
            $.stakeInfo[user].staked = correctTotalStake; // Use correct mapping name 'stakeInfo'
            emit AdminStakeCorrection(user, oldTotalStake, correctTotalStake);
        } else {
            // Optionally emit an event indicating no change was needed
        }
    }

}
