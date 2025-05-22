// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/*
 * @title PlumeErrors
 * @notice Common errors used across Plume contracts
 */

// Core errors
/*
 * @notice Thrown when an invalid amount is provided
 * @param amount The invalid amount that was provided
 */
error InvalidAmount(uint256 amount);

error NoActiveStake();

/*
 * @notice Thrown when a zero address is provided for a parameter that cannot be zero
 * @param parameter The name of the parameter that was zero
 */
error ZeroAddress(string parameter);

/*
 * @notice Thrown when trying to perform an operation with a token that doesn't exist in the system
 * @param token The address of the non-existent token
 */
error TokenDoesNotExist(address token);

/*
 * @notice Thrown when a token transfer fails
 */
error TransferError();

// Staking errors
/*
 * @notice Thrown when trying to perform an operation on tokens that are still in cooling period
 */
error TokensInCoolingPeriod();

/*
 * @notice Thrown when trying to withdraw tokens before the cooldown period has ended
 */
error CooldownPeriodNotEnded();

/**
 * @notice Error thrown when stake amount is too small
 * @param providedAmount Amount attempted to stake
 * @param minAmount Minimum required stake amount
 */
error StakeAmountTooSmall(uint256 providedAmount, uint256 minAmount);

/**
 * @notice Error thrown when trying to restake more than available in cooldown
 * @param availableAmount Amount available in cooldown
 * @param requestedAmount Amount requested to restake
 */
error InsufficientCooldownBalance(uint256 availableAmount, uint256 requestedAmount);

/**
 * @notice Error thrown when trying to restake amount exceeds available cooled + parked balance.
 * @param available Total amount available in cooled and parked.
 * @param requested Amount requested to restake.
 */
error InsufficientCooledAndParkedBalance(uint256 available, uint256 requested);

/**
 * @notice Error thrown when trying to restake rewards but there are none available.
 */
error NoRewardsToRestake();

// Validator errors
/*
 * @notice Thrown when trying to interact with a validator that doesn't exist
 * @param validatorId The ID of the non-existent validator
 */
error ValidatorDoesNotExist(uint16 validatorId);

/*
 * @notice Thrown when trying to add a validator with an ID that already exists
 * @param validatorId The ID of the existing validator
 */
error ValidatorAlreadyExists(uint16 validatorId);

/*
 * @notice Thrown when trying to interact with an inactive validator
 * @param validatorId The ID of the inactive validator
 */
error ValidatorInactive(uint16 validatorId);

/*
 * @notice Thrown when a non-admin address tries to perform a validator admin operation
 * @param caller The address of the unauthorized caller
 */
error NotValidatorAdmin(address caller);

/*
 * @notice Thrown when a validator's capacity would be exceeded by an operation
 */
error ValidatorCapacityExceeded();

/*
 * @notice Thrown when a validator's percentage of the total stake would exceed the maximum
 */
error ValidatorPercentageExceeded();

/*
 * @notice Thrown when an operation would affect too many stakers at once
 */
error TooManyStakers();

// Reward errors
/*
 * @notice Thrown when trying to add a token that already exists in the reward token list
 */
error TokenAlreadyExists();

/*
 * @notice Thrown when array lengths don't match in a function that expects matching arrays
 */
error ArrayLengthMismatch();

/*
 * @notice Thrown when an empty array is provided but a non-empty array is required
 */
error EmptyArray();

/*
 * @notice Thrown when a validator commission exceeds the maximum allowed value
 */
error CommissionTooHigh();

/**
 * @notice Error thrown when commission rate exceeds maximum allowed (100%)
 * @param requested The commission rate requested (scaled by 1e18)
 * @param max The maximum allowed commission rate (1e18)
 */
error CommissionRateTooHigh(uint256 requested, uint256 max);

/*
 * @notice Thrown when a reward rate exceeds the maximum allowed value
 */
error RewardRateExceedsMax();

/*
 * @notice Thrown when a native token transfer fails
 */
error NativeTransferFailed();

/*
 * @notice Thrown when an array index is out of bounds
 * @param index The index that was out of bounds
 * @param length The length of the array
 */
error IndexOutOfRange(uint256 index, uint256 length);

/*
 * @notice Thrown when an index range is invalid
 * @param startIndex The start index
 * @param endIndex The end index
 */
error InvalidIndexRange(uint256 startIndex, uint256 endIndex);

/*
 * @notice Thrown when attempting to add a staker that already exists
 * @param staker The address of the staker that already exists
 */
error StakerExists(address staker);

/*
 * @notice Thrown when attempting to withdraw user funds
 * @param available The amount available for withdrawal
 * @param requested The amount requested for withdrawal
 */
error InsufficientFunds(uint256 available, uint256 requested);

/*
 * @notice Thrown when a native token transfer fails in an admin operation
 */
error AdminTransferFailed();

/*
 * @notice Thrown when an invalid reward rate checkpoint index is provided
 * @param token The token address
 * @param index The invalid index
 */
error InvalidRewardRateCheckpoint(address token, uint256 index);

/*
 * @notice Thrown when a slash vote duration is too long
 */
error SlashVoteDurationTooLong();

// Slashing Errors
error CannotVoteForSelf();
error AlreadyVotedToSlash(uint16 targetValidatorId, uint16 voterValidatorId);
error ValidatorAlreadySlashed(uint16 validatorId);
error UnanimityNotReached(uint256 votes, uint256 required);
error SlashVoteExpired(uint16 targetValidatorId, uint16 voterValidatorId);
error SlashConditionsNotMet(uint16 validatorId);

/// @param admin Address that is already assigned.
error AdminAlreadyAssigned(address admin);

// Treasury Errors
error ZeroAddressToken();
error TokenAlreadyAdded(address token);
error ZeroRecipientAddress();
error ZeroAmount();
error TokenNotRegistered(address token);
error InsufficientPlumeBalance(uint256 requested, uint256 available);
error InsufficientTokenBalance(address token, uint256 requested, uint256 available);
error PlumeTransferFailed(address recipient, uint256 amount);
error VotingPowerProxyCannotBeZero();
error TransferHelperCannotBeZero();
error InsufficientBalance(address token, uint256 available, uint256 required);
error InvalidToken();

/*
 * @dev Thrown when a function call fails to transfer tokens or ETH.
 * @param token The address of the token that failed to transfer, or the zero address for ETH.
 * @param recipient The address of the intended recipient.
 * @param amount The amount that failed to transfer.
 */
error TokenTransferFailed(address token, address recipient, uint256 amount);

/**
 * @dev Thrown when trying to interact with an invalid or unsupported token.
 * @param token The address of the invalid token.
 */
error UnsupportedToken(address token);

/**
 * @dev Thrown when an operation would result in a zero address.
 */
error ZeroAddressProvided();

/**
 * @dev Thrown when trying to withdraw more than the available balance from treasury.
 * @param token The address of the token.
 * @param requested The requested amount.
 * @param available The available amount.
 */
error TreasuryInsufficientBalance(address token, uint256 requested, uint256 available);

/**
 * Validator Errors **
 */

/**
 * @notice Error thrown when trying to create a validator with ID 0 that already exists
 */
error ValidatorIdExists();

/**
 * @notice Error thrown when validator capacity would be exceeded
 * @param validatorId ID of the validator
 * @param currentAmount Current delegated amount
 * @param maxCapacity Maximum capacity of the validator
 * @param requestedAmount Requested amount to add
 */
error ExceedsValidatorCapacity(uint16 validatorId, uint256 currentAmount, uint256 maxCapacity, uint256 requestedAmount);

/**
 * @notice Error thrown when trying to restake from parked/cooled but there is no balance.
 */
error NoWithdrawableBalanceToRestake();

/// @notice Emitted when trying to withdraw but the cooldown period is not complete.
error CooldownNotComplete(uint256 cooldownEnd, uint256 currentTime);

// Core errors
error Unauthorized(address caller, bytes32 requiredRole);
error TreasuryNotSet();
error InternalInconsistency(string message);

// Validator errors
error InvalidUpdateType(uint8 providedType);

// --- New Max Commission Errors ---
error CommissionExceedsMaxAllowed(uint256 requested, uint256 maxAllowed);
error InvalidMaxCommissionRate(uint256 requested, uint256 limit);

// --- Commission Claim Timelock Errors ---
error PendingClaimExists(uint16 validatorId, address token);
error NoPendingClaim(uint16 validatorId, address token);
error ClaimNotReady(uint16 validatorId, address token, uint256 readyTimestamp);

/// @notice Thrown when cooldown interval is too short relative to max slash vote duration.
/// @param newCooldownInterval The proposed cooldown interval.
/// @param currentMaxSlashVoteDuration The current maximum slash vote duration.
error CooldownTooShortForSlashVote(uint256 newCooldownInterval, uint256 currentMaxSlashVoteDuration);

/// @notice Thrown when max slash vote duration is too long relative to cooldown interval.
/// @param newMaxSlashVoteDuration The proposed maximum slash vote duration.
/// @param currentCooldownInterval The current cooldown interval.
error SlashVoteDurationTooLongForCooldown(uint256 newMaxSlashVoteDuration, uint256 currentCooldownInterval);

/// @notice Thrown when an invalid interval is provided (e.g. zero)
/// @param interval The invalid interval.
error InvalidInterval(uint256 interval);

/**
 * @notice Thrown when an action is attempted on a validator that has been slashed.
 * @param validatorId The ID of the slashed validator.
 */
error ActionOnSlashedValidatorError(uint16 validatorId);

/**
 * @notice Thrown when an admin tries to clear records for a validator that isn't actually slashed.
 * @param validatorId The ID of the validator that is not slashed.
 */
error ValidatorNotSlashed(uint16 validatorId);
