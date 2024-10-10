// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC7540 } from "./IERC7540.sol";

interface IComponentToken is IERC7540 {

    // Events

    /**
     * @notice Emitted when the vault has been notified of the completion of a deposit request
     * @param controller Controller of the request
     * @param assets Amount of `asset` that has been deposited
     * @param shares Amount of shares that to receive in exchange
     */
    event DepositNotified(address indexed controller, uint256 assets, uint256 shares);

    /**
     * @notice Emitted when the vault has been notified of the completion of a redeem request
     * @param controller Controller of the request
     * @param assets Amount of `asset` to receive in exchange
     * @param shares Amount of shares that has been redeemed
     */
    event RedeemNotified(address indexed controller, uint256 assets, uint256 shares);

    // User Functions

    /**
     * @notice Notify the vault that the async request to buy shares has been completed
     * @param assets Amount of `asset` that was deposited by `requestDeposit`
     * @param shares Amount of shares to receive in exchange
     * @param controller Controller of the request
     */
    function notifyDeposit(uint256 assets, uint256 shares, address controller) external;

    /**
     * @notice Notify the vault that the async request to redeem assets has been completed
     * @param assets Amount of `asset` to receive in exchange
     * @param shares Amount of shares that was redeemed by `requestRedeem`
     * @param controller Controller of the request
     */
    function notifyRedeem(uint256 assets, uint256 shares, address controller) external;

}
