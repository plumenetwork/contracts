// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {
    AlreadyVotedToSlash,
    CannotVoteForSelf,
    CommissionTooHigh,
    NativeTransferFailed,
    NotValidatorAdmin,
    SlashConditionsNotMet,
    SlashVoteDurationTooLong,
    SlashVoteExpired,
    TooManyStakers,
    UnanimityNotReached,
    ValidatorAlreadyExists,
    ValidatorAlreadySlashed,
    ValidatorDoesNotExist,
    ValidatorNotActive,
    ZeroAddress
} from "../lib/PlumeErrors.sol";
import {
    SlashVoteCast,
    ValidatorAdded,
    ValidatorCapacityUpdated,
    ValidatorCommissionClaimed,
    ValidatorSlashed,
    ValidatorUpdated
} from "../lib/PlumeEvents.sol";

import { PlumeRewardLogic } from "../lib/PlumeRewardLogic.sol";
import { PlumeStakingStorage } from "../lib/PlumeStakingStorage.sol";

import { OwnableInternal } from "@solidstate/access/ownable/OwnableInternal.sol";
import { OwnableStorage } from "@solidstate/access/ownable/OwnableStorage.sol";
import { DiamondBaseStorage } from "@solidstate/proxy/diamond/base/DiamondBaseStorage.sol";

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IAccessControl } from "../interfaces/IAccessControl.sol";
import { PlumeRoles } from "../lib/PlumeRoles.sol";

// Struct definition REMOVED from file level

/**
 * @title ValidatorFacet
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Facet handling validator management: adding, updating, commission, capacity.
 */
contract ValidatorFacet is ReentrancyGuardUpgradeable, OwnableInternal {

    // Struct definition MOVED INSIDE the contract
    struct ValidatorListData {
        uint16 id;
        uint256 totalStaked;
        uint256 commission;
    }

    using SafeERC20 for IERC20;
    using Address for address payable;
    using PlumeStakingStorage for PlumeStakingStorage.Layout;
    using SafeCast for uint256;

    // --- Constants ---
    address private constant PLUME = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 private constant REWARD_PRECISION = 1e18;

    // --- Storage Access ---
    // Helper to get Plume-specific storage layout
    function _getPlumeStorage() internal pure returns (PlumeStakingStorage.Layout storage $) {
        $ = PlumeStakingStorage.layout();
    }

    // Modifier for Validator Admin checks
    modifier onlyValidatorAdmin(
        uint16 validatorId
    ) {
        // Access Plume storage to find validator admin
        require(msg.sender == _getPlumeStorage().validators[validatorId].l2AdminAddress, "Not validator admin");
        _;
    }

    // --- Modifiers ---

    /**
     * @dev Modifier to check role using the AccessControlFacet.
     */
    modifier onlyRole(
        bytes32 _role
    ) {
        require(IAccessControl(address(this)).hasRole(_role, msg.sender), "Caller does not have the required role");
        _;
    }

    // --- Validator Management (Owner) ---

    /**
     * @notice Add a new validator (Owner only)
     * @param validatorId Fixed UUID for the validator
     * @param commission Commission rate (as fraction of REWARD_PRECISION)
     * @param l2AdminAddress Admin address for the validator
     * @param l2WithdrawAddress Withdrawal address for validator rewards
     * @param l1ValidatorAddress Address of validator on L1 (informational)
     * @param l1AccountAddress Address of account on L1 (informational)
     * @param l1AccountEvmAddress EVM address of account on L1 (informational)
     */
    function addValidator(
        uint16 validatorId,
        uint256 commission,
        address l2AdminAddress,
        address l2WithdrawAddress,
        string calldata l1ValidatorAddress,
        string calldata l1AccountAddress,
        uint256 l1AccountEvmAddress
    ) external onlyRole(PlumeRoles.VALIDATOR_ROLE) {
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();

        if ($.validatorExists[validatorId]) {
            revert ValidatorAlreadyExists(validatorId);
        }
        if (l2AdminAddress == address(0)) {
            revert ZeroAddress("l2AdminAddress");
        }
        if (l2WithdrawAddress == address(0)) {
            revert ZeroAddress("l2WithdrawAddress");
        }
        if (commission > REWARD_PRECISION) {
            revert CommissionTooHigh();
        }

        PlumeStakingStorage.ValidatorInfo storage validator = $.validators[validatorId];
        validator.validatorId = validatorId;
        validator.commission = commission;
        validator.delegatedAmount = 0;
        validator.l2AdminAddress = l2AdminAddress;
        validator.l2WithdrawAddress = l2WithdrawAddress;
        validator.l1ValidatorAddress = l1ValidatorAddress;
        validator.l1AccountAddress = l1AccountAddress;
        validator.l1AccountEvmAddress = l1AccountEvmAddress;
        validator.active = true;

        $.validatorIds.push(validatorId);
        $.validatorExists[validatorId] = true;
        // Add admin to ID mapping
        $.adminToValidatorId[l2AdminAddress] = validatorId;

        emit ValidatorAdded(
            validatorId,
            commission,
            l2AdminAddress,
            l2WithdrawAddress,
            l1ValidatorAddress,
            l1AccountAddress,
            l1AccountEvmAddress
        );
    }

    /**
     * @notice Set the maximum capacity for a validator (Owner only)
     * @param validatorId ID of the validator
     * @param maxCapacity New maximum capacity
     */
    function setValidatorCapacity(
        uint16 validatorId,
        uint256 maxCapacity
    ) external onlyRole(PlumeRoles.VALIDATOR_ROLE) {
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();

        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }

        PlumeStakingStorage.ValidatorInfo storage validator = $.validators[validatorId];
        uint256 oldCapacity = validator.maxCapacity;
        validator.maxCapacity = maxCapacity;

        emit ValidatorCapacityUpdated(validatorId, oldCapacity, maxCapacity);
    }

    // --- Validator Operations (Specific Validator Admin) ---

    /**
     * @notice Update validator settings (commission, admin address, withdraw address)
     * @dev Caller must be the current l2AdminAddress for the specific validatorId.
     */
    function updateValidator(
        uint16 validatorId,
        uint8 updateType,
        bytes calldata data
    ) external onlyValidatorAdmin(validatorId) {
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();
        // Existence check done by modifier implicitly via storage access
        PlumeStakingStorage.ValidatorInfo storage validator = $.validators[validatorId];

        if (updateType == 0) {
            // Update Commission
            uint256 newCommission = abi.decode(data, (uint256));
            if (newCommission > REWARD_PRECISION) {
                revert CommissionTooHigh();
            }
            _updateRewardsForAllValidatorStakers(validatorId);
            validator.commission = newCommission;
        } else if (updateType == 1) {
            // Update Admin Address
            address currentAdminAddress = validator.l2AdminAddress;
            address newAdminAddress = abi.decode(data, (address));
            if (newAdminAddress == address(0)) {
                revert ZeroAddress("newAdminAddress");
            }
            validator.l2AdminAddress = newAdminAddress;
            // Update admin to ID mapping
            delete $.adminToValidatorId[currentAdminAddress];
            $.adminToValidatorId[newAdminAddress] = validatorId;
        } else if (updateType == 2) {
            // Update Withdraw Address
            address newWithdrawAddress = abi.decode(data, (address));
            if (newWithdrawAddress == address(0)) {
                revert ZeroAddress("newWithdrawAddress");
            }
            validator.l2WithdrawAddress = newWithdrawAddress;
        } else {
            revert("Invalid update type");
        }

        emit ValidatorUpdated(
            validatorId,
            validator.commission,
            validator.l2AdminAddress,
            validator.l2WithdrawAddress,
            validator.l1ValidatorAddress,
            validator.l1AccountAddress,
            validator.l1AccountEvmAddress
        );
    }

    /**
     * @notice Claim validator commission rewards for a specific token
     * @dev Caller must be the current l2AdminAddress for the specific validatorId.
     */
    function claimValidatorCommission(
        uint16 validatorId,
        address token
    ) external nonReentrant onlyValidatorAdmin(validatorId) returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();
        // Existence check done implicitly
        PlumeStakingStorage.ValidatorInfo storage validator = $.validators[validatorId];

        _updateRewardsForAllValidatorStakers(validatorId);

        amount = $.validatorAccruedCommission[validatorId][token];
        if (amount > 0) {
            $.validatorAccruedCommission[validatorId][token] = 0;
            address recipient = validator.l2WithdrawAddress;
            if (token != PLUME) {
                IERC20(token).safeTransfer(recipient, amount);
            } else {
                (bool success,) = payable(recipient).call{ value: amount }("");
                if (!success) {
                    revert NativeTransferFailed();
                }
            }
            emit ValidatorCommissionClaimed(validatorId, token, amount);
        }
        // Return amount even if 0
        return amount;
    }

    /**
     * @notice Vote to slash a malicious validator
     * @dev Caller must be the L2 admin of an *active* validator.
     * @param maliciousValidatorId ID of the malicious validator to vote against
     * @param voteExpiration Timestamp when this vote expires
     */
    function voteToSlashValidator(uint16 maliciousValidatorId, uint256 voteExpiration) external nonReentrant {
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();
        address voterAdmin = msg.sender;
        uint16 voterValidatorId = $.adminToValidatorId[voterAdmin];

        // Check 1: Voter is an active validator admin
        if (voterValidatorId == 0 || !$.validators[voterValidatorId].active) {
            revert NotValidatorAdmin(voterAdmin); // Or a more specific error like "CallerIsNotActiveValidatorAdmin"
        }

        // Check 2: Target validator exists and is active
        PlumeStakingStorage.ValidatorInfo storage targetValidator = $.validators[maliciousValidatorId];
        if (!$.validatorExists[maliciousValidatorId]) {
            revert ValidatorDoesNotExist(maliciousValidatorId);
        }
        if (!targetValidator.active) {
            revert ValidatorNotActive(maliciousValidatorId);
        }
        if (targetValidator.slashed) {
            revert ValidatorAlreadySlashed(maliciousValidatorId);
        }

        // Check 3: Cannot vote for self
        if (voterValidatorId == maliciousValidatorId) {
            revert CannotVoteForSelf();
        }

        // Check 4: Vote expiration validity
        if (
            // set
            voteExpiration <= block.timestamp || $.maxSlashVoteDurationInSeconds == 0 // Prevent voting if duration not
                || voteExpiration > block.timestamp + $.maxSlashVoteDurationInSeconds
        ) {
            revert SlashVoteDurationTooLong(); // Re-use or create "InvalidVoteExpiration"
        }

        // Check 5: Voter hasn't already voted recently (check existing vote expiration)
        uint256 currentVoteExpiration = $.slashingVotes[maliciousValidatorId][voterValidatorId];
        if (currentVoteExpiration >= block.timestamp) {
            revert AlreadyVotedToSlash(maliciousValidatorId, voterValidatorId);
        }

        // Store the vote
        $.slashingVotes[maliciousValidatorId][voterValidatorId] = voteExpiration;

        // Increment vote count only if the previous vote was expired
        if (currentVoteExpiration < block.timestamp) {
            $.slashVoteCounts[maliciousValidatorId]++;
        }

        emit SlashVoteCast(maliciousValidatorId, voterValidatorId, voteExpiration);
    }

    /**
     * @notice Slash a malicious validator if enough valid votes have been cast.
     * @dev Callable by anyone with ADMIN_ROLE.
     * @param validatorId ID of the validator to potentially slash
     */
    function slashValidator(
        uint16 validatorId
    ) external nonReentrant onlyRole(PlumeRoles.ADMIN_ROLE) {
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();

        // Check 1: Target validator exists, is active, and not already slashed
        PlumeStakingStorage.ValidatorInfo storage targetValidator = $.validators[validatorId];
        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }
        if (!targetValidator.active) {
            revert ValidatorNotActive(validatorId);
        }
        if (targetValidator.slashed) {
            revert ValidatorAlreadySlashed(validatorId);
        }

        // Check 3: Count valid votes from *active* validators
        uint256 validVotes = 0;
        uint256 activeValidatorsCount = 0;
        uint16[] memory allValidatorIds = $.validatorIds;

        for (uint256 i = 0; i < allValidatorIds.length; i++) {
            uint16 currentId = allValidatorIds[i];
            if ($.validators[currentId].active) {
                activeValidatorsCount++;
                // Don't count self-votes (shouldn't exist, but defense-in-depth)
                if (currentId == validatorId) {
                    continue;
                }

                // Check if this active validator has a non-expired vote
                if ($.slashingVotes[validatorId][currentId] >= block.timestamp) {
                    validVotes++;
                }
            }
        }

        // Check 4: Unanimity condition
        // Required votes = activeValidatorsCount - 1 (all *other* active validators)
        uint256 requiredVotes = activeValidatorsCount > 0 ? activeValidatorsCount - 1 : 0;

        if (validVotes < requiredVotes) {
            // revert SlashThresholdNotMet(validVotes, requiredVotes);
            revert UnanimityNotReached(validVotes, requiredVotes);
        }

        // --- Conditions met, perform slashing --- //

        // a) Mark as inactive and slashed
        targetValidator.active = false;
        targetValidator.slashed = true;

        // b) Zero out any pending commission for the slashed validator
        address[] memory rewardTokens = $.rewardTokens;
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            $.validatorAccruedCommission[validatorId][rewardTokens[i]] = 0;
        }

        /*
         * --- Slashing Penalty Implementation ---
         * When a validator is confirmed to be slashed:
         * 1. The validator is marked inactive and slashed.
         * 2. Any pending commission rewards for the validator are zeroed out.
        * 3. The total active stake currently delegated to this validator (`$.validatorTotalStaked[validatorId]`)
         *    is calculated as the `penaltyAmount`.
        * 4. This `penaltyAmount` is subtracted from the global `$.totalStaked`, effectively burning these tokens
         *    from the total supply tracked by this contract.
         * 5. The slashed validator's specific `$.validatorTotalStaked[validatorId]` is set to 0.
        * 6. **(High Gas Cost Warning)** The function iterates through all stakers currently delegated to this
        validator.
         *    For each staker, their individual active stake balance with *this specific validator*
         *    (`$.userValidatorStakes[staker][validatorId].staked`) is set to 0.
         *    This prevents users from attempting to unstake or otherwise interact with the burned funds.
         * 7. The `ValidatorSlashed` event is emitted, including the total `penaltyAmount` burned.
         */
        // d) Implement stake penalty: Burn all stake associated with this validator.
        uint256 penaltyAmount = $.validatorTotalStaked[validatorId];
        if (penaltyAmount > 0) {
            // Decrease global and validator totals
            $.totalStaked -= penaltyAmount;
            $.validatorTotalStaked[validatorId] = 0;

            // !! WARNING: HIGH GAS COST !!
            // Zero out individual stakes for all stakers of this validator.
            // This prevents users from trying to unstake burned funds.
            // Consider adding limits or alternative mechanisms if gas is a concern.
            address[] storage stakers = $.validatorStakers[validatorId];
            for (uint256 i = 0; i < stakers.length; i++) {
                $.userValidatorStakes[stakers[i]][validatorId].staked = 0;
                // Note: We don't remove the staker from the array here, as they might have
                // stake with other validators or cooled/parked tokens.
                // The validator is marked inactive, preventing new stakes.
            }
        }

        // e) Reset vote counts and potentially votes for the slashed validator (cleanup)
        $.slashVoteCounts[validatorId] = 0;
        // Might also clear $.slashingVotes[validatorId][*] loop if needed, though checking `slashed` flag is
        // sufficient.

        emit ValidatorSlashed(validatorId, msg.sender, penaltyAmount);
    }

    // --- View Functions --- (Using _getPlumeStorage)

    /**
     * @notice Get information about a validator including total staked amount and staker count
     */
    function getValidatorInfo(
        uint16 validatorId
    )
        external
        view
        returns (PlumeStakingStorage.ValidatorInfo memory info, uint256 totalStaked, uint256 stakersCount)
    {
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();
        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }
        info = $.validators[validatorId];
        totalStaked = $.validatorTotalStaked[validatorId];
        stakersCount = $.validatorStakers[validatorId].length;
        return (info, totalStaked, stakersCount);
    }

    /**
     * @notice Get essential statistics about a validator
     */
    function getValidatorStats(
        uint16 validatorId
    ) external view returns (bool active, uint256 commission, uint256 totalStaked, uint256 stakersCount) {
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();
        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }
        PlumeStakingStorage.ValidatorInfo storage validator = $.validators[validatorId];
        active = validator.active;
        commission = validator.commission;
        totalStaked = $.validatorTotalStaked[validatorId];
        stakersCount = $.validatorStakers[validatorId].length;
        return (active, commission, totalStaked, stakersCount);
    }

    /**
     * @notice Get the list of validators a user has staked with
     */
    function getUserValidators(
        address user
    ) external view returns (uint16[] memory validatorIds) {
        return _getPlumeStorage().userValidators[user];
    }

    /**
     * @notice Get the amount of commission accrued for a specific token by a validator but not yet claimed.
     */
    function getAccruedCommission(uint16 validatorId, address token) external view returns (uint256 amount) {
        return _getPlumeStorage().validatorAccruedCommission[validatorId][token];
    }

    /**
     * @notice Returns a list of all validators with their basic data.
     * @return list An array of ValidatorListData structs.
     */
    function getValidatorsList() external view virtual returns (ValidatorFacet.ValidatorListData[] memory list) {
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();
        uint16[] memory ids = $.validatorIds;
        uint256 numValidators = ids.length;
        list = new ValidatorFacet.ValidatorListData[](numValidators);

        for (uint256 i = 0; i < numValidators; i++) {
            uint16 id = ids[i];
            PlumeStakingStorage.ValidatorInfo storage info = $.validators[id];
            list[i] = ValidatorFacet.ValidatorListData({
                id: id,
                totalStaked: $.validatorTotalStaked[id],
                commission: info.commission
            });
        }
    }

    /**
     * @notice Returns the number of currently active validators.
     */
    function getActiveValidatorCount() external view returns (uint256 count) {
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();
        uint16[] memory ids = $.validatorIds;
        count = 0;
        for (uint256 i = 0; i < ids.length; i++) {
            if ($.validators[ids[i]].active) {
                count++;
            }
        }
        return count;
    }

    // --- Internal Functions Definitions ---

    function _updateRewardsForAllValidatorStakers(
        uint16 validatorId
    ) internal {
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();
        address[] memory stakers = $.validatorStakers[validatorId];
        if (stakers.length > 100) {
            revert TooManyStakers();
        }
        for (uint256 i = 0; i < stakers.length; i++) {
            PlumeRewardLogic.updateRewardsForValidator($, stakers[i], validatorId);
        }
    }

}
