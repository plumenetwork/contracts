// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title PlumeEvents
 * @notice Common events used across Plume contracts
 */

// Core staking events
/**
 * @notice Emitted when a user stakes PLUME
 * @param user Address of the user
 * @param validatorId ID of the validator
 * @param amount Amount of $PLUME staked
 * @param fromCooling Amount taken from cooling
 * @param fromParked Amount taken from parked
 * @param fromWallet Amount taken from wallet
 */
event Staked(
    address indexed user,
    uint16 indexed validatorId,
    uint256 amount,
    uint256 fromCooling,
    uint256 fromParked,
    uint256 fromWallet
);

/**
 * @notice Emitted when a user unstakes PLUME
 * @param user Address of the user
 * @param validatorId ID of the validator
 * @param amount Amount of PLUME unstaked
 */
event Unstaked(address indexed user, uint16 indexed validatorId, uint256 amount);

/**
 * @notice Emitted when a user withdraws their cooled-down PLUME
 * @param user Address of the user
 * @param amount Amount of PLUME withdrawn
 */
event Withdrawn(address indexed user, uint256 amount);

/**
 * @notice Emitted when a user claims a reward
 * @param user Address of the user
 * @param token Address of the reward token
 * @param amount Amount of reward token claimed
 */
event RewardClaimed(address indexed user, address indexed token, uint256 amount);

/**
 * @notice Emitted when tokens move from cooling to withdrawable (cooling period ends)
 * @param user Address of the user
 * @param amount Amount of tokens moved from cooling to withdrawable
 */
event CoolingCompleted(address indexed user, uint256 amount);

// Administrative events
/**
 * @notice Emitted when the minimum stake amount is set
 * @param amount New minimum stake amount
 */
event MinStakeAmountSet(uint256 amount);

/**
 * @notice Emitted when the cooldown interval is set
 * @param interval New cooldown interval
 */
event CooldownIntervalSet(uint256 interval);

/**
 * @notice Emitted when admin withdraws tokens from the contract
 * @param token Address of the token withdrawn
 * @param amount Amount of tokens withdrawn
 * @param recipient Address that received the tokens
 */
event AdminWithdraw(address indexed token, uint256 amount, address indexed recipient);

/**
 * @notice Emitted when total amounts are updated by admin
 * @param totalStaked New total staked amount
 * @param totalCooling New total cooling amount
 * @param totalWithdrawable New total withdrawable amount
 */
event TotalAmountsUpdated(uint256 totalStaked, uint256 totalCooling, uint256 totalWithdrawable);

/**
 * @notice Emitted when total amounts are partially updated by admin
 * @param startIndex The starting index for processing
 * @param endIndex The ending index for processing
 * @param processedStaked Staked amount processed in this batch
 * @param processedCooling Cooling amount processed in this batch
 * @param processedWithdrawable Withdrawable amount processed in this batch
 */
event PartialTotalAmountsUpdated(
    uint256 startIndex,
    uint256 endIndex,
    uint256 processedStaked,
    uint256 processedCooling,
    uint256 processedWithdrawable
);

/**
 * @notice Emitted when admin updates a user's stake info
 * @param user Address of the user
 * @param staked New staked amount
 * @param cooled New cooling amount
 * @param parked New parked amount
 * @param cooldownEnd New cooldown end timestamp
 * @param lastUpdateTimestamp New last update timestamp
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
 * @notice Emitted when admin manually adds a staker
 * @param staker Address of the staker that was added
 */
event StakerAdded(address indexed staker);

// Reward-related events
/**
 * @notice Emitted when reward rates are updated
 * @param tokens Array of token addresses
 * @param rates Array of reward rates
 */
event RewardRatesSet(address[] tokens, uint256[] rates);

/**
 * @notice Emitted when rewards are added to the rewards pool
 * @param token Address of the token
 * @param amount Amount of tokens added
 */
event RewardsAdded(address indexed token, uint256 amount);

/**
 * @notice Emitted when a new token is added to the rewards list
 * @param token The address of the newly added reward token
 */
event RewardTokenAdded(address indexed token);

/**
 * @notice Emitted when a token is removed from the rewards list
 * @param token The address of the removed reward token
 */
event RewardTokenRemoved(address indexed token);

/**
 * @notice Emitted when the maximum reward rate for a token is updated
 * @param token Address of the token
 * @param newMaxRate New maximum reward rate
 */
event MaxRewardRateUpdated(address indexed token, uint256 newMaxRate);

// Validator-related events
/**
 * @notice Emitted when a user stakes PLUME to a validator
 * @param user Address of the user
 * @param validatorId ID of the validator
 * @param amount Total amount staked
 * @param fromCooling Amount taken from cooling
 * @param fromParked Amount taken from parked
 * @param fromWallet Amount taken from wallet
 */
event StakedToValidator(
    address indexed user,
    uint16 indexed validatorId,
    uint256 amount,
    uint256 fromCooling,
    uint256 fromParked,
    uint256 fromWallet
);

/**
 * @notice Emitted when a user unstakes PLUME from a validator
 * @param user Address of the user
 * @param validatorId ID of the validator
 * @param amount Amount unstaked
 */
event UnstakedFromValidator(address indexed user, uint16 indexed validatorId, uint256 amount);

/**
 * @notice Emitted when a user claims rewards from a validator
 * @param user Address of the user
 * @param token Address of the reward token
 * @param validatorId ID of the validator
 * @param amount Amount claimed
 */
event RewardClaimedFromValidator(
    address indexed user, address indexed token, uint16 indexed validatorId, uint256 amount
);

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
 */
event ValidatorAdded(
    uint16 indexed validatorId,
    uint256 commission,
    address l2AdminAddress,
    address l2WithdrawAddress,
    string l1ValidatorAddress,
    string l1AccountAddress
);

/**
 * @notice Emitted when a validator is updated
 * @param validatorId ID of the validator
 * @param commission New commission rate
 * @param l2AdminAddress New admin address
 * @param l2WithdrawAddress New withdrawal address
 * @param l1ValidatorAddress New L1 validator address
 * @param l1AccountAddress New L1 account address
 */
event ValidatorUpdated(
    uint16 indexed validatorId,
    uint256 commission,
    address l2AdminAddress,
    address l2WithdrawAddress,
    string l1ValidatorAddress,
    string l1AccountAddress
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
