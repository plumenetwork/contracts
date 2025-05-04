// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {
    AdminAlreadyAssigned,
    AlreadyVotedToSlash,
    CannotVoteForSelf,
    CommissionRateTooHigh,
    CommissionTooHigh,
    InvalidUpdateType,
    NativeTransferFailed,
    NotValidatorAdmin,
    SlashConditionsNotMet,
    SlashVoteDurationTooLong,
    SlashVoteExpired,
    TooManyStakers,
    TreasuryNotSet,
    UnanimityNotReached,
    Unauthorized,
    ValidatorAlreadyExists,
    ValidatorAlreadySlashed,
    ValidatorDoesNotExist,
    ValidatorNotActive,
    ZeroAddress
} from "../lib/PlumeErrors.sol";
import {
    SlashVoteCast,
    ValidatorAdded,
    ValidatorAddressesSet,
    ValidatorCapacityUpdated,
    ValidatorCommissionClaimed,
    ValidatorCommissionSet,
    ValidatorSlashed,
    ValidatorStatusUpdated,
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

import { IPlumeStakingRewardTreasury } from "../interfaces/IPlumeStakingRewardTreasury.sol";
import { PlumeRoles } from "../lib/PlumeRoles.sol";

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
    // Storage slot for treasury address (same as in RewardsFacet)
    bytes32 internal constant TREASURY_STORAGE_POSITION = keccak256("plume.storage.RewardTreasury");

    // Helper to get Plume-specific storage layout
    function _getPlumeStorage() internal pure returns (PlumeStakingStorage.Layout storage $) {
        $ = PlumeStakingStorage.layout();
    }

    // Helper to get treasury address (same implementation as in RewardsFacet)
    function getTreasuryAddress() internal view returns (address) {
        bytes32 position = TREASURY_STORAGE_POSITION;
        address treasuryAddress;
        assembly {
            treasuryAddress := sload(position)
        }
        return treasuryAddress;
    }

    // Modifier for Validator Admin checks
    modifier onlyValidatorAdmin(
        uint16 validatorId
    ) {
        if (!_getPlumeStorage().validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }
        if (msg.sender != _getPlumeStorage().validators[validatorId].l2AdminAddress) {
            revert NotValidatorAdmin(msg.sender);
        }
        _;
    }

    // --- Modifiers ---

    /**
     * @dev Modifier to check role using the AccessControlFacet.
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
     * @dev Modifier to check if a validator exists.
     */
    modifier _validateValidatorExists(
        uint16 validatorId
    ) {
        if (!_getPlumeStorage().validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }
        _;
    }

    // --- Validator Management (Owner/Admin) ---

    /**
     * @notice Add a new validator (Owner only)
     * @param validatorId UUID for the validator
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
        address l1AccountEvmAddress,
        uint256 maxCapacity
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
        // Check if admin address is already assigned using the dedicated mapping
        if ($.isAdminAssigned[l2AdminAddress]) {
            revert AdminAlreadyAssigned(l2AdminAddress);
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
        validator.slashed = false;
        validator.maxCapacity = maxCapacity;

        $.validatorIds.push(validatorId);
        $.validatorExists[validatorId] = true;
        // Add admin to ID mapping
        $.adminToValidatorId[l2AdminAddress] = validatorId;
        // Mark admin as assigned in the dedicated mapping
        $.isAdminAssigned[l2AdminAddress] = true;

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
    ) external onlyRole(PlumeRoles.VALIDATOR_ROLE) _validateValidatorExists(validatorId) {
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();
        PlumeStakingStorage.ValidatorInfo storage validator = $.validators[validatorId];

        uint256 oldCapacity = validator.maxCapacity;
        validator.maxCapacity = maxCapacity;

        emit ValidatorCapacityUpdated(validatorId, oldCapacity, maxCapacity);
    }

    /**
     * @notice Set the active/inactive status for a validator
     * @dev Caller must have ADMIN_ROLE.
     * @param validatorId ID of the validator
     * @param newActiveStatus The desired active status (true for active, false for inactive)
     */
    function setValidatorStatus(
        uint16 validatorId,
        bool newActiveStatus
    ) external onlyRole(PlumeRoles.ADMIN_ROLE) _validateValidatorExists(validatorId) {
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();
        PlumeStakingStorage.ValidatorInfo storage validator = $.validators[validatorId];

        // Prevent activating an already slashed validator through this function
        if (newActiveStatus && validator.slashed) {
            revert ValidatorAlreadySlashed(validatorId);
        }

        validator.active = newActiveStatus;

        // Use the new specific event for status changes
        emit ValidatorStatusUpdated(validatorId, validator.active, validator.slashed);
    }

    /**
     * @notice Set the commission rate for a specific validator.
     * @dev Caller must be the l2AdminAddress for the validator.
     *      Triggers reward updates for stakers and creates a commission checkpoint.
     * @param validatorId ID of the validator to update.
     * @param newCommission The new commission rate (scaled by 1e18).
     */
    function setValidatorCommission(
        uint16 validatorId,
        uint256 newCommission
    ) external onlyValidatorAdmin(validatorId) {
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();
        PlumeStakingStorage.ValidatorInfo storage validator = $.validators[validatorId];

        uint256 oldCommission = validator.commission;

        // Check for maximum commission rate if needed (e.g., 100% = 1e18)
        if (newCommission > 1e18) {
            revert CommissionRateTooHigh(newCommission, 1e18);
        }

        validator.commission = newCommission;
        // Create commission checkpoint
        PlumeRewardLogic.createCommissionRateCheckpoint($, validatorId, newCommission);

        // Emit correct event with old and new values
        emit ValidatorCommissionSet(validatorId, oldCommission, newCommission);
    }

    /**
     * @notice Set various addresses associated with a validator.
     * @dev Caller must be the l2AdminAddress for the validator.
     *      Updates are optional: pass address(0) or "" to keep the current value.
     * @param validatorId ID of the validator to update.
     * @param newL2AdminAddress The new admin address (or address(0) to keep current).
     * @param newL2WithdrawAddress The new withdraw address (or address(0) to keep current).
     * @param newL1ValidatorAddress The new L1 validator address string (or "" to keep current).
     * @param newL1AccountAddress The new L1 account address string (or "" to keep current).
     * @param newL1AccountEvmAddress The new L1 account EVM address (or address(0) to keep current).
     */
    function setValidatorAddresses(
        uint16 validatorId,
        address newL2AdminAddress,
        address newL2WithdrawAddress,
        string calldata newL1ValidatorAddress,
        string calldata newL1AccountAddress,
        address newL1AccountEvmAddress
    ) external onlyValidatorAdmin(validatorId) {
        PlumeStakingStorage.Layout storage $ = _getPlumeStorage();
        PlumeStakingStorage.ValidatorInfo storage validator = $.validators[validatorId];

        address oldL2AdminAddress = validator.l2AdminAddress;
        address oldL2WithdrawAddress = validator.l2WithdrawAddress;
        string memory oldL1ValidatorAddress = validator.l1ValidatorAddress;
        string memory oldL1AccountAddress = validator.l1AccountAddress;
        address oldL1AccountEvmAddress = validator.l1AccountEvmAddress;

        // Update L2 Admin Address if provided and different
        if (newL2AdminAddress != address(0) && newL2AdminAddress != validator.l2AdminAddress) {
            // Check if the new admin address is already assigned
            if ($.isAdminAssigned[newL2AdminAddress]) {
                revert AdminAlreadyAssigned(newL2AdminAddress);
            }
            address currentAdminAddress = validator.l2AdminAddress;
            validator.l2AdminAddress = newL2AdminAddress;
            // Update admin to ID mapping
            delete $.adminToValidatorId[currentAdminAddress];
            $.adminToValidatorId[newL2AdminAddress] = validatorId;
            // Update the dedicated assignment mapping
            $.isAdminAssigned[currentAdminAddress] = false;
            $.isAdminAssigned[newL2AdminAddress] = true;
        }

        // Update L2 Withdraw Address if provided and different
        if (newL2WithdrawAddress != address(0) && newL2WithdrawAddress != validator.l2WithdrawAddress) {
            if (newL2WithdrawAddress == address(0)) {
                // Add specific check for zero address
                revert ZeroAddress("newL2WithdrawAddress");
            }
            validator.l2WithdrawAddress = newL2WithdrawAddress;
        }

        // Update L1 Validator Address string if provided
        if (bytes(newL1ValidatorAddress).length > 0) {
            validator.l1ValidatorAddress = newL1ValidatorAddress;
        }

        // Update L1 Account Address string if provided
        if (bytes(newL1AccountAddress).length > 0) {
            validator.l1AccountAddress = newL1AccountAddress;
        }

        // Update L1 Account EVM Address if provided
        // No need to check for zero address here, as address(0) might be valid representation
        if (newL1AccountEvmAddress != address(0)) {
            validator.l1AccountEvmAddress = newL1AccountEvmAddress;
        }

        // Emit the correct event with old and new values
        emit ValidatorAddressesSet(
            validatorId,
            oldL2AdminAddress,
            validator.l2AdminAddress,
            oldL2WithdrawAddress,
            validator.l2WithdrawAddress,
            oldL1ValidatorAddress,
            validator.l1ValidatorAddress,
            oldL1AccountAddress,
            validator.l1AccountAddress,
            oldL1AccountEvmAddress,
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

        amount = $.validatorAccruedCommission[validatorId][token];
        if (amount > 0) {
            $.validatorAccruedCommission[validatorId][token] = 0;
            address recipient = validator.l2WithdrawAddress;

            // Get the treasury address
            address treasury = getTreasuryAddress();
            if (treasury == address(0)) {
                revert TreasuryNotSet();
            }

            // Use the treasury to distribute reward instead of direct transfer
            IPlumeStakingRewardTreasury(treasury).distributeReward(token, amount, recipient);

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

        // Check 1: Voter is an active validator admin for the ID derived from the mapping
        if ($.validators[voterValidatorId].l2AdminAddress != voterAdmin || !$.validators[voterValidatorId].active) {
            revert NotValidatorAdmin(voterAdmin);
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
            revert SlashVoteDurationTooLong();
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
    ) external nonReentrant onlyRole(PlumeRoles.TIMELOCK_ROLE) {
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

    // --- View Functions ---

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

}
