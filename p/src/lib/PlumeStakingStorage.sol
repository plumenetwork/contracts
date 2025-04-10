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

    // Main storage struct using ERC-7201 namespaced storage pattern
    struct Layout {
        /// @notice Array of all staker addresses
        address[] stakers;
        /// @notice Array of all reward token addresses
        address[] rewardTokens;
        /// @notice Maps a token address to its reward rate in tokens per second per staked token
        mapping(address => uint256) rewardRates;
        /// @notice Maps a token address to its maximum allowed reward rate
        mapping(address => uint256) maxRewardRates;
        /// @notice Maps a token address to the last time its reward was globally updated
        mapping(address => uint256) lastUpdateTimes;
        /// @notice Maps a token address to the reward per token accumulated so far
        mapping(address => uint256) rewardPerTokenCumulative;
        /// @notice Maps a token address to the amount of rewards still to be distributed
        mapping(address => uint256) rewardsAvailable;
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
        /// @notice Mapping to track if an address is already in stakers array
        mapping(address => bool) isStaker;
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
        /// @notice Maps a validator to its total staked amount
        mapping(uint16 => uint256) validatorTotalStaked;
        /// @notice Maps a validator to its total cooling amount
        mapping(uint16 => uint256) validatorTotalCooling;
        /// @notice Maps a validator to its total withdrawable amount
        mapping(uint16 => uint256) validatorTotalWithdrawable;
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
        /// @notice Maximum stake capacity for a validator
        mapping(uint16 => uint256) validatorCapacity;
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
        /// @notice Maps a malicious validator ID to the validator that voted to slash it
        mapping(uint16 maliciousValidatorId => mapping(uint16 votingValidatorId => uint256 voteExpiration)) slashingVotes;
        /// @notice The maximum length of time for which a validator's vote to slash another validator is valid
        // TODO - check where we set this
        uint256 maxSlashVoteDurationInSeconds;
    }

    // Validator info struct to store validator details
    struct ValidatorInfo {
        uint16 validatorId; // Fixed UUID for the validator
        uint256 commission; // Commission rate (BASE = 1e18, so 5% = 5e16)
        uint256 delegatedAmount; // Total amount delegated to this validator
        address l2AdminAddress; // Admin address (multisig)
        address l2WithdrawAddress; // Address for validator rewards
        string l1ValidatorAddress; // L1 validator address (for reference)
        string l1AccountAddress; // L1 account address (for reference)
        uint256 l1AccountEvmAddress; // EVM address of account on L1 (for reference)
        bool active; // Whether the validator is active
        uint256 maxCapacity; // Maximum amount of PLUME that can be staked with this validator
    }

    struct StakeInfo {
        uint256 staked; // Amount staked
        uint256 cooled; // Amount in cooldown
        uint256 parked; // Amount that can be withdrawn
        uint256 cooldownEnd; // Timestamp when cooldown ends
        uint256 lastUpdateTimestamp; // Timestamp of last rewards update
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
