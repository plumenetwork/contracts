// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title PlumeEvents
 * @notice Common events used across Plume contracts
 */

/**
 * @notice Emitted when tokens are staked in the contract
 * @param staker Address of the staker
 * @param validatorId ID of the validator receiving the stake
 * @param amount Amount of tokens staked
 * @param fromCooled Amount of tokens used from cooled tokens
 * @param fromParked Amount of tokens used from parked (withdrawn) tokens
 * @param pendingRewards Amount of tokens staked from pending rewards
 */
event Staked(
    address indexed staker,
    uint16 indexed validatorId,
    uint256 amount,
    uint256 fromCooled,
    uint256 fromParked,
    uint256 pendingRewards
);

/**
 * @notice Emitted when stake is started to cool
 * @param staker Address of the staker
 * @param validatorId ID of the validator
 * @param amount Amount moved to cooling
 * @param cooldownEnd Timestamp when cooldown ends
 */
event CooldownStarted(address indexed staker, uint16 indexed validatorId, uint256 amount, uint256 cooldownEnd);

/**
 * @notice Emitted when cooling period is completed for tokens
 * @param staker Address of the staker
 * @param amount Amount that completed cooling
 */
event CoolingCompleted(address indexed staker, uint256 amount);

/**
 * @notice Emitted when tokens are unstaked from the contract (legacy)
 * @param user Address of the user
 * @param validatorId ID of the validator
 * @param amount Amount unstaked
 */
event Unstaked(address indexed user, uint16 indexed validatorId, uint256 amount);

/**
 * @notice Emitted when tokens are unstaked from a specific validator
 * @param user Address of the user
 * @param validatorId ID of the validator
 * @param amount Amount unstaked
 */
event UnstakedFromValidator(address indexed user, uint16 indexed validatorId, uint256 amount);

/**
 * @notice Emitted when stake is forced to cool without a cooldown period
 * @param staker Address of the staker
 * @param validatorId ID of the validator
 * @param amount Amount moved directly to parked status
 */
event ForceUnstaked(address indexed staker, uint16 indexed validatorId, uint256 amount);

/**
 * @notice Emitted when cooled tokens are parked (ready for withdrawal)
 * @param staker Address of the staker
 * @param validatorId ID of the validator
 * @param amount Amount moved to parked status
 */
event TokensParked(address indexed staker, uint16 indexed validatorId, uint256 amount);

/**
 * @notice Emitted when tokens are withdrawn from the contract
 * @param staker Address of the staker
 * @param amount Amount withdrawn
 */
event Withdrawn(address indexed staker, uint256 amount);

/**
 * @notice Emitted when a reward token is added
 * @param token Address of the token
 */
event RewardTokenAdded(address indexed token);

/**
 * @notice Emitted when a reward token is removed
 * @param token Address of the token
 */
event RewardTokenRemoved(address indexed token);

/**
 * @notice Emitted when reward rates are updated
 * @param tokens Array of token addresses
 * @param rates Array of new rates
 */
event RewardRatesSet(address[] tokens, uint256[] rates);

/**
 * @notice Emitted when a new reward rate checkpoint is created
 * @param token Address of the token
 * @param rate New reward rate
 * @param timestamp Timestamp when the checkpoint was created
 * @param index Index of the checkpoint
 * @param cumulativeIndex Cumulative reward index at this checkpoint
 */
event RewardRateCheckpointCreated(
    address indexed token, uint256 rate, uint256 timestamp, uint256 indexed index, uint256 cumulativeIndex
);

/**
 * @notice Emitted when rewards are added to the contract
 * @param token Address of the token
 * @param amount Amount of rewards added
 */
event RewardsAdded(address indexed token, uint256 amount);

/**
 * @notice Emitted when max reward rates are set
 * @param tokens Array of token addresses
 * @param maxRates Array of max rates
 */
event MaxRewardRatesSet(address[] tokens, uint256[] maxRates);

/**
 * @notice Emitted when the maximum reward rate for a token is updated
 * @param token Address of the token
 * @param newRate New maximum rate
 */
event MaxRewardRateUpdated(address indexed token, uint256 newRate);

/**
 * @notice Emitted when a reward is claimed
 * @param user Address of the user
 * @param token Address of the token
 * @param amount Amount claimed
 */
event RewardClaimed(address indexed user, address indexed token, uint256 amount);

/**
 * @notice Emitted when a reward is claimed from a specific validator
 * @param user Address of the user
 * @param token Address of the token
 * @param validatorId ID of the validator
 * @param amount Amount claimed
 */
event RewardClaimedFromValidator(
    address indexed user, address indexed token, uint16 indexed validatorId, uint256 amount
);

/**
 * @notice Emitted when admin withdraws user's unclaimed rewards
 * @param user Address of the user
 * @param token Address of the token
 * @param amount Amount withdrawn
 */
event AdminWithdrewUserRewards(address indexed user, address indexed token, uint256 amount);

/**
 * @notice Emitted when the minimum stake amount is updated
 * @param oldAmount Old minimum amount
 * @param newAmount New minimum amount
 */
event MinStakeAmountUpdated(uint256 oldAmount, uint256 newAmount);

/**
 * @notice Emitted when the cooldown interval is updated
 * @param oldInterval Old cooldown interval
 * @param newInterval New cooldown interval
 */
event CooldownIntervalUpdated(uint256 oldInterval, uint256 newInterval);

/**
 * @notice Emitted when a new staker is added to the system
 * @param staker Address of the staker
 */
event StakerAdded(address indexed staker);

/**
 * @notice Emitted when validator commission is claimed
 * @param validatorId ID of the validator
 * @param token Address of the token
 * @param amount Amount of commission claimed
 */
event ValidatorCommissionClaimed(uint16 indexed validatorId, address indexed token, uint256 amount);

/**
 * @notice Emitted when a validator is added
 * @param validatorId ID of the validator
 * @param commission Commission rate
 * @param l2AdminAddress Admin address
 * @param l2WithdrawAddress Withdrawal address
 * @param l1ValidatorAddress L1 validator address
 * @param l1AccountAddress L1 account address
 * @param l1AccountEvmAddress EVM address of account on L1 (informational)
 */
event ValidatorAdded(
    uint16 indexed validatorId,
    uint256 commission,
    address l2AdminAddress,
    address l2WithdrawAddress,
    string l1ValidatorAddress,
    string l1AccountAddress,
    address l1AccountEvmAddress
);

/**
 * @notice Emitted when a validator is updated
 * @param validatorId ID of the validator
 * @param commission New commission rate
 * @param l2AdminAddress New admin address
 * @param l2WithdrawAddress New withdrawal address
 * @param l1ValidatorAddress New L1 validator address
 * @param l1AccountAddress New L1 account address
 * @param l1AccountEvmAddress New EVM address of account on L1 (informational)
 */
event ValidatorUpdated(
    uint16 indexed validatorId,
    uint256 commission,
    address l2AdminAddress,
    address l2WithdrawAddress,
    string l1ValidatorAddress,
    string l1AccountAddress,
    address l1AccountEvmAddress
);

/**
 * @notice Emitted when a validator is deactivated
 * @param validatorId ID of the validator
 */
event ValidatorDeactivated(uint16 indexed validatorId);

/**
 * @notice Emitted when a validator is activated
 * @param validatorId ID of the validator
 */
event ValidatorActivated(uint16 indexed validatorId);

/**
 * @notice Emitted when validator stakers' rewards are updated in a batch
 * @param validatorId ID of the validator
 * @param startIndex The starting index for processing
 * @param endIndex The ending index for processing
 */
event ValidatorStakersRewardsUpdated(uint16 validatorId, uint256 startIndex, uint256 endIndex);

/**
 * @notice Emitted when a validator is removed from the system
 * @param validatorId ID of the validator removed
 */
event ValidatorRemoved(uint16 indexed validatorId);

/**
 * @notice Emitted when the maximum validator commission is updated
 * @param oldMaxCommission Old maximum commission rate
 * @param newMaxCommission New maximum commission rate
 */
event MaxValidatorCommissionUpdated(uint256 oldMaxCommission, uint256 newMaxCommission);

/**
 * @notice Emitted when the validator capacity is updated
 * @param validatorId ID of the validator
 * @param oldCapacity Old capacity
 * @param newCapacity New capacity
 */
event ValidatorCapacityUpdated(uint16 indexed validatorId, uint256 oldCapacity, uint256 newCapacity);

/**
 * @notice Emitted when the maximum validator percentage is updated
 * @param oldPercentage Old maximum percentage (in basis points)
 * @param newPercentage New maximum percentage (in basis points)
 */
event MaxValidatorPercentageUpdated(uint256 oldPercentage, uint256 newPercentage);

/**
 * @notice Emitted when emergency funds are transferred from one validator to another for a specific staker
 * @param staker Address of the staker whose funds were transferred
 * @param fromValidatorId Source validator ID
 * @param toValidatorId Destination validator ID
 * @param amount Amount of funds transferred
 */
event EmergencyFundsTransferred(
    address indexed staker, uint16 indexed fromValidatorId, uint16 indexed toValidatorId, uint256 amount
);

/**
 * @notice Emitted when validator emergency transfer is completed
 * @param fromValidatorId Source validator ID
 * @param toValidatorId Destination validator ID
 * @param amount Amount of funds transferred
 * @param stakerCount Number of stakers affected
 */
event ValidatorEmergencyTransfer(
    uint16 indexed fromValidatorId, uint16 indexed toValidatorId, uint256 amount, uint256 stakerCount
);

/**
 * @notice Emitted when a user stakes PLUME on behalf of another user
 * @param sender Address of the sender who initiated the stake
 * @param staker Address of the staker who receives the stake
 * @param validatorId ID of the validator
 * @param amount Amount of $PLUME staked
 */
event StakedOnBehalf(address indexed sender, address indexed staker, uint16 indexed validatorId, uint256 amount);

/**
 * @notice Emitted when admin withdraws tokens from the contract
 * @param token Address of the token withdrawn
 * @param amount Amount withdrawn
 * @param recipient Address receiving the tokens
 */
event AdminWithdraw(address indexed token, uint256 amount, address indexed recipient);

/**
 * @notice Emitted when cooldown interval is set
 * @param interval New cooldown interval in seconds
 */
event CooldownIntervalSet(uint256 interval);

/**
 * @notice Emitted when minimum stake amount is set
 * @param amount New minimum stake amount
 */
event MinStakeAmountSet(uint256 amount);

/**
 * @notice Emitted when partial total amounts are updated in a batch process
 * @param startIndex Starting index for processing
 * @param endIndex Ending index for processing
 * @param totalStaked Processed staked amount
 * @param totalCooling Processed cooling amount
 * @param totalWithdrawable Processed withdrawable amount
 */
event PartialTotalAmountsUpdated(
    uint256 startIndex, uint256 endIndex, uint256 totalStaked, uint256 totalCooling, uint256 totalWithdrawable
);

/**
 * @notice Emitted when stake info is updated by admin
 * @param user Address of the user
 * @param staked Updated staked amount
 * @param cooled Updated cooling amount
 * @param parked Updated parked amount
 * @param cooldownEnd Updated cooldown end timestamp
 * @param lastUpdateTimestamp Last reward update timestamp
 */
event StakeInfoUpdated(
    address indexed user,
    uint256 staked,
    uint256 cooled,
    uint256 parked,
    uint256 cooldownEnd,
    uint256 lastUpdateTimestamp
);

/**
 * @notice Emitted when total amounts are updated
 * @param totalStaked Updated total staked amount
 * @param totalCooling Updated total cooling amount
 * @param totalWithdrawable Updated total withdrawable amount
 */
event TotalAmountsUpdated(uint256 totalStaked, uint256 totalCooling, uint256 totalWithdrawable);

/**
 * @notice Emitted when a vote to slash a validator is cast
 * @param targetValidatorId ID of the validator being voted against
 * @param voterValidatorId ID of the validator casting the vote
 * @param voteExpiration Timestamp when the vote expires
 */
event SlashVoteCast(uint16 indexed targetValidatorId, uint16 indexed voterValidatorId, uint256 voteExpiration);

/**
 * @notice Emitted when a validator is slashed
 * @param validatorId ID of the slashed validator
 * @param slasher Address that triggered the slash
 * @param penaltyAmount Amount of stake potentially burned or redistributed (TBD)
 */
event ValidatorSlashed(uint16 indexed validatorId, address indexed slasher, uint256 penaltyAmount);

/**
 * @notice Emitted when the maximum slash vote duration is set
 * @param duration New maximum duration in seconds
 */
event MaxSlashVoteDurationSet(uint256 duration);

/**
 * @notice Emitted when the treasury address is set
 * @param treasury Address of the new treasury
 */
event TreasurySet(address indexed treasury);

// Treasury Events
event RewardDistributed(address indexed token, uint256 amount, address indexed recipient);

/**
 * @notice Emitted when Plume (native) tokens are received by the treasury
 * @param sender Address of the sender
 * @param amount Amount of Plume received
 */
event PlumeReceived(address indexed sender, uint256 amount);

/**
 * @notice Emitted when native tokens are deposited to the treasury
 * @param sender Address of the sender
 * @param amount Amount of tokens deposited
 */
event NativeTokenDeposited(address indexed sender, uint256 amount);

/**
 * @notice Emitted when an ERC20 token is received by the treasury
 * @param token Address of the token
 * @param sender Address of the sender
 * @param amount Amount of tokens received
 */
event TokenReceived(address indexed token, address indexed sender, uint256 amount);

/**
 * @notice Emitted when a token transfer fails
 * @param token Address of the token (PLUME_NATIVE for native token)
 * @param recipient Address of the intended recipient
 * @param amount Amount that failed to transfer
 */
event TransferFailed(address indexed token, address indexed recipient, uint256 amount);

/**
 * @notice Emitted when a user restakes their rewards
 * @param staker Address of the staker who restaked
 * @param validatorId Validator ID restaked to
 * @param amount Amount of rewards restaked
 */
event RewardsRestaked(address indexed staker, uint16 indexed validatorId, uint256 amount);

/**
 * @notice Emitted when a user restakes their parked/cooled balance.
 * @param user The address of the user.
 * @param validatorId The ID of the validator the user restaked to.
 * @param amount The amount of PLUME restaked.
 */
event ParkedRestaked(address indexed user, uint16 indexed validatorId, uint256 amount);

// --- Management Facet Events ---
event AdminStakeCorrection(address indexed user, uint256 oldTotalStake, uint256 newTotalStake);

/**
 * @notice Emitted when a validator's active/slashed status is updated
 * @param validatorId ID of the validator
 * @param active The new active status
 * @param slashed The current slashed status
 */
event ValidatorStatusUpdated(uint16 indexed validatorId, bool active, bool slashed);

// Validator Events
event ValidatorCommissionSet(uint16 indexed validatorId, uint256 oldCommission, uint256 newCommission);

event ValidatorAddressesSet(
    uint16 indexed validatorId,
    address oldL2Admin,
    address newL2Admin,
    address oldL2Withdraw,
    address newL2Withdraw,
    string oldL1Validator,
    string newL1Validator,
    string oldL1Account,
    string newL1Account,
    address oldL1AccountEvm,
    address newL1AccountEvm
);
