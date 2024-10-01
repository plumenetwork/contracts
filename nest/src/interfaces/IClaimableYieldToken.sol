// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IClaimableYieldToken is IERC20 {

    /**
     * @notice Claim all the remaining yield that has been accrued to a user
     * @dev Anyone can call this function to claim yield for any user
     * @param user Address of the user to claim yield for
     * @return amount Amount of CurrencyToken claimed as yield
     */
    function claimYield(address user) external returns (uint256 amount);

    /// @notice CurrencyToken in which both the ClaimableYieldToken and yield are denominated
    function getCurrencyToken() external view returns (IERC20 currencyToken);

    /// @notice Total yield distributed to the ClaimableYieldToken for all users
    function totalYield() external view returns (uint256 amount);

    /// @notice Claimed yield for the ClaimableYieldToken for all users
    function claimedYield() external view returns (uint256 amount);

    /// @notice Unclaimed yield for the ClaimableYieldToken for all users
    function unclaimedYield() external view returns (uint256 amount);

    /**
     * @notice Total yield distributed to a specific user
     * @param user Address of the user for which to get the total yield
     * @return amount Total yield distributed to the user
     */
    function totalYield(address user) external view returns (uint256 amount);

    /**
     * @notice Amount of yield that a specific user has claimed
     * @param user Address of the user for which to get the claimed yield
     * @return amount Amount of yield that the user has claimed
     */
    function claimedYield(address user) external view returns (uint256 amount);

    /**
     * @notice Amount of yield that a specific user has not yet claimed
     * @param user Address of the user for which to get the unclaimed yield
     * @return amount Amount of yield that the user has not yet claimed
     */
    function unclaimedYield(address user) external view returns (uint256 amount);

}
