//SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @notice State of a holder of the YieldDistributionToken
 * @param amountSeconds Cumulative sum of the amount of YieldDistributionTokens held by
 * the user, multiplied by the number of seconds that the user has had each balance for
 * @param lastUpdate Timestamp of the most recent update to amountSeconds, thereby balance of user
 * @param lastDepositIndex latest index of  Deposit array that user has accrued yield for
 * @param yieldAccrued Total amount of yield that is currently accrued to the user
 */
struct UserState {
    uint256 amountSeconds;
    uint256 amountSecondsDeduction;
    uint256 lastUpdate;
    uint256 lastDepositIndex;
    uint256 yieldAccrued;
    uint256 yieldWithdrawn;
}

/**
 * @notice Amount of yield deposited into the YieldDistributionToken at one point in time
 * @param currencyTokenPerAmountSecond Amount of CurrencyToken deposited as yield divided by the total amountSeconds
 * elapsed since last yield deposit
 * @param totalAmountSeconds Sum of amountSeconds for all users at that time
 * @param timestamp Timestamp in which deposit was made
 */
struct Deposit {
    uint256 scaledCurrencyTokenPerAmountSecond;
    uint256 totalAmountSeconds;
    uint256 timestamp;
}
