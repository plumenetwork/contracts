// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * @title PlumeStakingStorage
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Storage definitions for PlumeStaking system
 */
library PlumeStakingStorage {

    // --- BEGIN ADDED CONSTANTS ---
    address public constant PLUME_NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 public constant REWARD_PRECISION = 1e18;
    // --- END ADDED CONSTANTS ---

    // Storage position for the diamond storage
    bytes32 constant DIAMOND_STORAGE_POSITION = keccak256("plume.staking.storage");

    /**
     * @notice Represents a user's stake information with a specific validator
     */
    struct UserValidatorStake {
        uint256 staked; // Amount currently staked with this validator
    }

    /**
     * @notice Represents a user's global stake information across all validators
     */
    struct StakeInfo {
        uint256 staked; // Total amount staked across all validators
        uint256 cooled; // Total amount in cooling period across all validators
        uint256 parked; // Total amount ready for withdrawal
    }

    /**
     * @notice Represents a cooldown entry for a user with a specific validator
     */
    struct CooldownEntry {
        uint256 amount; // Amount in cooldown
        uint256 cooldownEndTime; // When the cooldown period ends
    }

    /**
     * @notice Represents a rate checkpoint for reward calculations
     */
    struct RateCheckpoint {
        uint256 timestamp; // When this rate was set
        uint256 rate; // The reward rate at this timestamp
        uint256 cumulativeIndex; // Cumulative reward index at this checkpoint
    }

    /**
     * @notice Main storage layout for the staking system
     */
    struct Layout {
        
        // === Core Staking State ===
        uint256 totalStaked; // Total amount staked across all validators
        uint256 totalCooling; // Total amount in cooling period
        uint256 totalWithdrawable; // Total amount available for withdrawal
        
        // === Reward Token Management ===
        address[] rewardTokens; // Array of all reward token addresses
        mapping(address => bool) isRewardToken; // token => whether it's an active reward token
        mapping(address => uint256) rewardRates; // token => reward rate
        mapping(address => uint256) maxRewardRates; // token => maximum allowed reward rate
        mapping(address => uint256) totalClaimableByToken; // token => total claimable amount

        // === User State Mappings ===
        mapping(address => StakeInfo) stakeInfo; // user => global stake info
        mapping(address => mapping(uint16 => UserValidatorStake)) userValidatorStakes; // user => validatorId => stake info
        mapping(address => mapping(uint16 => CooldownEntry)) userValidatorCooldowns; // user => validatorId => cooldown info
        mapping(address => uint16[]) userValidators; // user => list of validators they've staked with
        mapping(address => mapping(uint16 => bool)) userHasStakedWithValidator; // user => validatorId => has staked
        mapping(address => mapping(uint16 => uint256)) userValidatorStakeStartTime; // user => validatorId => stake start time

        // === Validator State ===
        mapping(uint16 => ValidatorInfo) validators; // validatorId => validator info
        uint16[] validatorIds; // Array of all validator IDs
        mapping(uint16 => bool) validatorExists; // validatorId => exists
        mapping(uint16 => uint256) validatorTotalStaked; // validatorId => total staked amount
        mapping(uint16 => uint256) validatorTotalCooling; // validatorId => total cooling amount
        mapping(uint16 => address[]) validatorStakers; // validatorId => list of stakers
        mapping(uint16 => mapping(address => bool)) isStakerForValidator; // validatorId => user => is staker
        mapping(address => mapping(uint16 => uint256)) userIndexInValidatorStakers; // user => validatorId => index in stakers array 

        // === Reward System ===
        mapping(uint16 => mapping(address => uint256)) validatorAccruedCommission; // validatorId => token => commission amount
        mapping(uint16 => mapping(address => uint256)) validatorRewardPerTokenCumulative; // validatorId => token => cumulative reward per token
        mapping(uint16 => mapping(address => uint256)) validatorLastUpdateTimes; // validatorId => token => last update time
        mapping(address => mapping(uint16 => mapping(address => uint256))) userRewards; // user => validatorId => token => reward amount
        mapping(address => mapping(uint16 => mapping(address => uint256))) userValidatorRewardPerTokenPaid; // user => validatorId => token => last paid rate
        mapping(address => mapping(uint16 => mapping(address => uint256))) userLastCheckpointIndex; // user => validatorId => token => checkpoint index
        mapping(address => mapping(uint16 => mapping(address => uint256))) userValidatorRewardPerTokenPaidTimestamp; // user => validatorId => token => timestamp
        mapping(address => mapping(uint16 => bool)) userHasPendingRewards; // user => validatorId => has pending rewards

        // === Reward Rate Checkpoints ===
        mapping(address => RateCheckpoint[]) rewardRateCheckpoints; // token => rate checkpoints
        mapping(uint16 => mapping(address => RateCheckpoint[])) validatorRewardRateCheckpoints; // validatorId => token => rate checkpoints
        mapping(uint16 => RateCheckpoint[]) validatorCommissionCheckpoints; // validatorId => commission checkpoints

        // === Configuration ===
        uint256 minStakeAmount; // Minimum staking amount
        uint256 cooldownInterval; // Duration of the cooldown period in seconds
        uint256 maxValidatorPercentage; // Maximum percentage of total stake a validator can have (in basis points)
        uint256 maxAllowedValidatorCommission; // Maximum allowed commission for any validator

        // === Access Control ===
        mapping(bytes32 => mapping(address => bool)) hasRole; // role => address => has role
        bool initialized; // Whether the contract has been initialized
        bool accessControlFacetInitialized; // Whether the AccessControlFacet has been initialized

        // === Validator Management ===
        mapping(uint16 => mapping(uint16 => uint256)) slashingVotes; // maliciousValidatorId => votingValidatorId => vote expiration
        uint256 maxSlashVoteDurationInSeconds; // Maximum duration for slash votes
        mapping(uint16 => uint256) slashVoteCounts; // validatorId => active vote count
        mapping(address => uint16) adminToValidatorId; // admin address => validatorId
        mapping(address => bool) isAdminAssigned; // admin address => is assigned to a validator

        // === Commission Claims ===
        mapping(uint16 => mapping(address => PendingCommissionClaim)) pendingCommissionClaims; // validatorId => token => pending claim
            
        // === Flags ===
        mapping(address => bool) hasPendingRewards; // user => whether they have pending rewards to claim
    }

    /**
     * @notice Information about a validator
     */
    struct ValidatorInfo {
        uint16 validatorId; // Validator ID
        bool active; // Whether the validator is currently active
        bool slashed; // Whether the validator has been slashed
        uint256 slashedAtTimestamp; // When the validator was slashed (0 if not slashed)
        uint256 maxCapacity; // Maximum amount that can be staked with this validator (0 = unlimited)
        uint256 delegatedAmount; // Total amount delegated to this validator
        uint256 commission; // Commission rate (using REWARD_PRECISION as base)
        address l2AdminAddress; // Admin address (multisig)
        address l2WithdrawAddress; // Address for validator rewards
        string l1ValidatorAddress; // L1 validator address (for reference)
        string l1AccountAddress; // L1 account address (for reference)
        address l1AccountEvmAddress; // EVM address of account on L1 (for reference)
    }

    /**
     * @notice Pending commission claim information
     */
    struct PendingCommissionClaim {
        uint256 amount; // Amount to be claimed
        uint256 requestTimestamp; // When the claim was requested
        address token; // Token being claimed
        address recipient; // Address to receive the claim
    }

    // Constants
    uint256 constant COMMISSION_CLAIM_TIMELOCK = 7 days;

    /**
     * @notice Returns the storage layout
     */
    function layout() internal pure returns (Layout storage l) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly {
            l.slot := position
        }
    }

}
