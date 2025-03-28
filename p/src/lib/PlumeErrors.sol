// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title PlumeErrors
 * @notice Common errors used across Plume contracts
 */

// Errors

/**
 * @notice Thrown for an invalid amount
 * @param amount The amount that was provided
 * @param minAmount The minimum amount required
 */
error InvalidAmount(uint256 amount, uint256 minAmount);

/**
 * @notice Thrown when a user with cooling tokens tries to stake again
 * @dev TODO remove this restriction in the future
 * @param amount Amount of tokens in cooling period
 */
error TokensInCoolingPeriod(uint256 amount);

/**
 * @notice Indicates a failure because the cooldown period has not ended
 * @dev TODO remove this restriction in the future
 * @param endTime Timestamp at which the cooldown period ends
 */
error CooldownPeriodNotEnded(uint256 endTime);

/**
 * @notice Thrown when trying to perform an operation that requires an active stake, but user has none
 */
error NoActiveStake();

/**
 * @notice Thrown when a zero address is provided for a parameter that requires a valid address
 * @param parameter The name of the parameter that was zero
 */
error ZeroAddress(string parameter);

/**
 * @notice Thrown when attempting to add a token that is already in the rewards list
 * @param token The address of the token that already exists
 */
error TokenAlreadyExists(address token);

/**
 * @notice Thrown when attempting to interact with a token that is not in the rewards list
 * @param token The address of the non-existent reward token
 */
error TokenDoesNotExist(address token);

/**
 * @notice Thrown when the length of tokens array does not match the length of rates array
 * @dev This error occurs in setRewardRates when tokens.length != rewardRates_.length
 */
error ArrayLengthMismatch();

/**
 * @notice Thrown when attempting to set reward rates with empty arrays
 * @dev This error occurs in setRewardRates when tokens.length == 0
 */
error EmptyArray();

/**
 * @notice Thrown when trying to interact with a validator that doesn't exist
 * @param validatorId ID of the non-existent validator
 */
error ValidatorDoesNotExist(uint16 validatorId);

/**
 * @notice Thrown when trying to add a validator that already exists
 * @param validatorId ID of the already existing validator
 */
error ValidatorAlreadyExists(uint16 validatorId);

/**
 * @notice Thrown when commission is set too high
 * @param commission Specified commission rate
 * @param maxCommission Maximum allowed commission rate
 */
error CommissionTooHigh(uint256 commission, uint256 maxCommission);

/**
 * @notice Thrown when a non-admin tries to perform an admin action for a validator
 * @param caller Address that tried to perform the action
 * @param validatorId ID of the validator
 */
error NotValidatorAdmin(address caller, uint16 validatorId);

/**
 * @notice Thrown when trying to interact with an inactive validator
 * @param validatorId ID of the inactive validator
 */
error ValidatorInactive(uint16 validatorId);

/**
 * @notice Thrown when attempting to set a reward rate higher than the maximum allowed
 * @param rate The proposed reward rate
 * @param maxRate The maximum allowed reward rate
 */
error RewardRateExceedsMax(uint256 rate, uint256 maxRate);
