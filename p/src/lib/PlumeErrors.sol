// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @notice Common errors used across Plume contracts
 */

// Core errors
error InvalidAmount(uint256 amount);
error NoActiveStake();
error ZeroAddress(string parameter);
error TokenDoesNotExist(address token);

// Staking errors
error TokensInCoolingPeriod();
error CooldownPeriodNotEnded();

// Validator errors
error ValidatorDoesNotExist(uint16 validatorId);
error ValidatorAlreadyExists(uint16 validatorId);
error ValidatorInactive(uint16 validatorId);
error NotValidatorAdmin(address caller);
error ValidatorCapacityExceeded();
error ValidatorPercentageExceeded();
error TooManyStakers();

// Reward errors
error TokenAlreadyExists();
error ArrayLengthMismatch();
error EmptyArray();
error CommissionTooHigh();
error RewardRateExceedsMax();
error NativeTransferFailed();
