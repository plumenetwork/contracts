// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title PlumeStakingStorage
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Storage definitions for PlumeStaking system
 */
library PlumeStakingStorage {

    // Rate checkpoint struct to store historical reward rates
    struct RateCheckpoint {
        uint256 timestamp; // Timestamp when this rate became active
        uint256 rate; // Reward rate at this checkpoint
        uint256 cumulativeIndex; // Accumulated reward per token at this checkpoint
    }

    // New struct for per-user, per-validator cooldown entries
    struct CooldownEntry {
        uint256 amount;         // Amount cooling for this user with this validator
        uint256 cooldownEndTime; // Timestamp when this specific cooldown ends
    }

    // Main storage struct using ERC-7201 namespaced storage pattern
    struct Layout {
        /// @notice Array of all staker addresses
        address[] stakers;
        /// @notice Array of all reward token addresses
        address[] rewardTokens;
        /// @notice Maps a token address to a boolean indicating if it's a reward token
        mapping(address => bool) isRewardToken;
        /// @notice Maps a token address to its reward rate in tokens per second per staked token
        mapping(address => uint256) rewardRates;
        /// @notice Maps a token address to its maximum allowed reward rate
        mapping(address => uint256) maxRewardRates;
        /// @notice Maps a token address to the last time its reward was globally updated
        mapping(address => uint256) lastUpdateTimes;
        /// @notice Maps a token address to the reward per token accumulated so far
        mapping(address => uint256) rewardPerTokenCumulative;
        /// @notice Maps a token address to the total amount claimable for that token
        mapping(address => uint256) totalClaimableByToken;
        /// @notice Maps a token address to its history of rate checkpoints
        mapping(address => RateCheckpoint[]) rewardRateCheckpoints;
        /// @notice Total $PLUME staked in the contract
        uint256 totalStaked;
        /// @notice Total $PLUME in cooling period
        uint256 totalCooling;
        /// @notice Total $PLUME that is withdrawable (parked)
        uint256 totalWithdrawable;
        /// @notice Minimum staking amount
        uint256 minStakeAmount;
        /// @notice Duration of the cooldown period
        uint256 cooldownInterval;
        /// @notice Maps an address to its staking info
        mapping(address => StakeInfo) stakeInfo;
        /// @notice Maps a (user, token) pair to the reward per token paid to that user for that token
        mapping(address => mapping(address => uint256)) userRewardPerTokenPaid;
        /// @notice Maps a (user, token) pair to the reward of that token for that user
        mapping(address => mapping(address => uint256)) rewards;
        // Validator related storage
        /// @notice Information about each validator
        mapping(uint16 => ValidatorInfo) validators;
        /// @notice Array of all validator IDs
        uint16[] validatorIds;
        /// @notice Mapping to check if a validator exists
        mapping(uint16 => bool) validatorExists;
        /// @notice Maps a (user, validator) pair to the user's stake info for that validator
        mapping(address => mapping(uint16 => StakeInfo)) userValidatorStakes;
        /// @notice Maps a user to all validators they have staked with
        mapping(address => uint16[]) userValidators;
        /// @notice Maps a (user, validator) pair to indicate if user has staked with that validator
        mapping(address => mapping(uint16 => bool)) userHasStakedWithValidator;
        /// @notice Maps a validator to all stakers who have staked with it
        mapping(uint16 => address[]) validatorStakers;
        /// @notice Maps a (validator, staker) pair to indicate if staker has staked with that validator
        mapping(uint16 => mapping(address => bool)) isStakerForValidator;
        /// @notice Maps a (staker, validator) pair to the index of the staker within the validator's staker list
        mapping(address => mapping(uint16 => uint256)) userIndexInValidatorStakers;
        /// @notice Maps a validator to its total staked amount
        mapping(uint16 => uint256) validatorTotalStaked;
        /// @notice Maps a validator to its total cooling amount (sum of its entries in userValidatorCooldowns)
        mapping(uint16 => uint256) validatorTotalCooling;
        /// @notice Maps a validator to its total withdrawable amount
        mapping(uint16 => uint256) validatorTotalWithdrawable;
        /// @notice Maps a (user, validator) pair to their specific cooldown details
        mapping(address => mapping(uint16 => CooldownEntry)) userValidatorCooldowns;
        /// @notice Maps a (validator, token) pair to the last time rewards were updated
        mapping(uint16 => mapping(address => uint256)) validatorLastUpdateTimes;
        /// @notice Maps a (validator, token) pair to the reward per token accumulated
        mapping(uint16 => mapping(address => uint256)) validatorRewardPerTokenCumulative;
        /// @notice Maps a (user, validator, token) triple to the reward per token paid
        mapping(address => mapping(uint16 => mapping(address => uint256))) userValidatorRewardPerTokenPaid;
        /// @notice Maps a (user, validator, token) triple to the rewards earned
        mapping(address => mapping(uint16 => mapping(address => uint256))) userRewards;
        /// @notice Maps a (validator, token) pair to the commission accumulated
        mapping(uint16 => mapping(address => uint256)) validatorAccruedCommission;
        /// @notice Maps a validator ID to its history of commission rate checkpoints
        mapping(uint16 => RateCheckpoint[]) validatorCommissionCheckpoints;
        /// @notice Flag to indicate if epochs are being used
        // TODO - remove epochs
        bool usingEpochs;
        /// @notice Current epoch number
        // TODO - remove epochs
        uint256 currentEpochNumber;
        /// @notice Maps epoch number to validator amounts for each validator
        mapping(uint256 => mapping(uint16 => uint256)) epochValidatorAmounts;
        /// @notice Maximum allowed commission for all validators
        // TODO - check where we set this
        uint256 maxValidatorCommission;
        /// @notice Maximum percentage of total staked funds any validator can have (in basis points)
        // TODO - check where we set this
        uint256 maxValidatorPercentage;
        /// @notice Maps a validator ID and token to its history of rate checkpoints
        mapping(uint16 => mapping(address => RateCheckpoint[])) validatorRewardRateCheckpoints;
        /// @notice Maps a (user, validator, token) triple to the index of the last checkpoint that was paid
        mapping(address => mapping(uint16 => mapping(address => uint256))) userLastCheckpointIndex;
        /// @notice Maps a (user, validator) pair to the timestamp when the user started staking with this validator
        mapping(address => mapping(uint16 => uint256)) userValidatorStakeStartTime;
        /// @notice Maps a (user, validator, token) triple to the timestamp when the user's reward per token was last
        /// updated
        mapping(address => mapping(uint16 => mapping(address => uint256))) userValidatorRewardPerTokenPaidTimestamp;
        /// @notice Maps a role (bytes32) to an address to check if the address has the role.
        mapping(bytes32 => mapping(address => bool)) hasRole;
        bool initialized;
        /// @notice Flag to indicate if the AccessControlFacet has been initialized
        bool accessControlFacetInitialized;
        /// @notice Maps a malicious validator ID to the validator that voted to slash it
        mapping(uint16 maliciousValidatorId => mapping(uint16 votingValidatorId => uint256 voteExpiration))
            slashingVotes;
        /// @notice The maximum length of time for which a validator's vote to slash another validator is valid
        // TODO - check where we set this
        uint256 maxSlashVoteDurationInSeconds;
        /// @notice Maps malicious validator ID to the count of active, non-expired votes against it
        mapping(uint16 => uint256) slashVoteCounts;
        /// @notice Maps an admin address to its validator ID (if it's a validator admin)
        mapping(address => uint16) adminToValidatorId;
        /// @notice Tracks if an admin address is already assigned to *any* validator.
        mapping(address => bool) isAdminAssigned;
        /// @notice Maximum allowed commission for any validator
        uint256 maxAllowedValidatorCommission;
        // Add mapping for pending commission claims: validatorId => token => PendingCommissionClaim
        mapping(uint16 => mapping(address => PendingCommissionClaim)) pendingCommissionClaims;
    }
    // Add a constant for the commission claim timelock (7 days)

    uint256 constant COMMISSION_CLAIM_TIMELOCK = 7 days;

    // Validator info struct to store validator details
    struct ValidatorInfo {
        uint16 validatorId; // Validator ID
        uint256 commission; // Commission rate (BASE = 1e18, so 5% = 5e16)
        uint256 delegatedAmount; // Total amount delegated to this validator
        address l2AdminAddress; // Admin address (multisig)
        address l2WithdrawAddress; // Address for validator rewards
        string l1ValidatorAddress; // L1 validator address (for reference)
        string l1AccountAddress; // L1 account address (for reference)
        address l1AccountEvmAddress; // EVM address of account on L1 (for reference)
        bool active; // Whether the validator is active
        bool slashed; // Whether the validator has been slashed
        uint256 maxCapacity; // Maximum amount of PLUME that can be staked with this validator
    }

    struct StakeInfo {
        uint256 staked; // Amount staked
        uint256 cooled; // Amount in cooldown (sum of active userValidatorCooldowns for this user)
        uint256 parked; // Amount that can be withdrawn
        uint256 lastUpdateTimestamp; // Timestamp of last rewards update
    }

    struct PendingCommissionClaim {
        uint256 amount;
        uint256 requestTimestamp;
        address token;
        address recipient;
    }

    // Constants
    bytes32 public constant STORAGE_SLOT = keccak256("plume.storage.PlumeStaking");

    // Function to get storage
    function layout() internal pure returns (Layout storage s) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }

}
