// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IComponentToken } from "./IComponentToken.sol";

interface IAggregateToken is IComponentToken {

    /**
     * @notice Buy ComponentToken using CurrencyToken
     * @dev Only the owner can call this function, will revert if
     *   the AggregateToken does not have enough CurrencyToken to buy the ComponentToken
     * @param componentToken ComponentToken to buy
     * @param currencyTokenAmount Amount of CurrencyToken to pay to receive the ComponentToken
     */
    function buyComponentToken(IComponentToken componentToken, uint256 currencyTokenAmount) external;

    /**
     * @notice Sell ComponentToken to receive CurrencyToken
     * @dev Only the owner can call this function, will revert if
     *   the ComponentToken does not have enough CurrencyToken to sell to the AggregateToken
     * @param componentToken ComponentToken to sell
     * @param currencyTokenAmount Amount of CurrencyToken to receive in exchange for the ComponentToken
     */
    function sellComponentToken(IComponentToken componentToken, uint256 currencyTokenAmount) external;

    /**
     * @notice Claim yield for all ComponentTokens into the AggregateToken
     * @dev Anyone can call this function to claim yield for all ComponentTokens
     */
    function claimComponentsYield() external returns (uint256 amount);
    function requestYield(address from) external;

}
