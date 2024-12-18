// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IYieldDistributionToken is IERC20 {

    /**
     * @notice Emitted when yield is deposited into the YieldDistributionToken
     * @param user Address of the user who deposited the yield
     * @param currencyTokenAmount Amount of CurrencyToken deposited as yield
     */
    event Deposited(address indexed user, uint256 currencyTokenAmount);

    /**
     * @notice Emitted when yield is claimed by a user
     * @param user Address of the user who claimed the yield
     * @param currencyTokenAmount Amount of CurrencyToken claimed as yield
     */
    event YieldClaimed(address indexed user, uint256 currencyTokenAmount);

    /**
     * @notice Emitted when yield is accrued to a user's balance
     * @param user Address of the user who accrued the yield
     * @param currencyTokenAmount Amount of CurrencyToken accrued as yield
     */
    event YieldAccrued(address indexed user, uint256 currencyTokenAmount);

    /// @notice Indicates a failure because a yield deposit is made in the same block as the last one
    error DepositSameBlock();

    /// @notice Indicates a failure because the transfer of CurrencyToken failed
    error TransferFailed(address user, uint256 currencyTokenAmount);

    /**
     * @notice Get the token used for yield distribution
     * @return currencyToken The ERC20 token used for yield payments
     */
    function getCurrencyToken() external view returns (IERC20 currencyToken);

    /**
     * @notice Claim accumulated yield for a user
     * @param user Address of the user to claim yield for
     * @return currencyToken Token in which yield is paid
     * @return currencyTokenAmount Amount of yield claimed
     */
    function claimYield(
        address user
    ) external returns (IERC20 currencyToken, uint256 currencyTokenAmount);

    /**
     * @notice Update and accrue yield for a specific user
     * @dev Anyone can call this function to update a user's yield
     * @param user Address of the user to accrue yield for
     */
    function accrueYield(
        address user
    ) external;

    /**
     * @notice Request yield distribution from a specific address
     * @dev Implementation depends on the specific yield source
     * @param from Address to request yield from
     */
    function requestYield(
        address from
    ) external;

    /**
     * @notice Get the URI for the token metadata
     * @return The URI string pointing to the token's metadata
     */
    function getTokenURI() external view returns (string memory);

    /**
     * @notice Calculate the pending yield for a user that hasn't been accrued yet
     * @param user Address of the user to check pending yield for
     * @return Amount of pending yield in CurrencyToken
     */
    function pendingYield(
        address user
    ) external view returns (uint256);

    /**
     * @notice Get the current yield rate per token
     * @return Current yield per token rate scaled by SCALE
     */
    function currentYieldPerToken() external view returns (uint256);

}
