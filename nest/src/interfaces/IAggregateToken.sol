// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IComponentToken } from "./IComponentToken.sol";

interface IAggregateToken is IComponentToken {

    // Events

    /**
     * @notice Emitted when a ComponentToken is added to the component token list
     * @param componentToken ComponentToken that is added to the component token list
     */
    event ComponentTokenListed(IComponentToken componentToken);

    /**
     * @notice Emitted when a ComponentToken is removed from the component token list
     * @param componentToken ComponentToken that is removed from the component token list
     */
    event ComponentTokenUnlisted(IComponentToken componentToken);

    /**
     * @notice Emitted when the owner buys ComponentToken using `asset`
     * @param owner Address of the owner who bought the ComponentToken
     * @param componentToken ComponentToken that was bought
     * @param componentTokenAmount Amount of ComponentToken received in exchange
     * @param assets Amount of `asset` paid
     */
    event ComponentTokenBought(
        address indexed owner, IComponentToken indexed componentToken, uint256 componentTokenAmount, uint256 assets
    );

    /**
     * @notice Emitted when the owner sells ComponentToken to receive `asset`
     * @param owner Address of the owner who sold the ComponentToken
     * @param componentToken ComponentToken that was sold
     * @param componentTokenAmount Amount of ComponentToken sold
     * @param assets Amount of `asset` received in exchange
     */
    event ComponentTokenSold(
        address indexed owner, IComponentToken indexed componentToken, uint256 componentTokenAmount, uint256 assets
    );

    /**
     * @notice Emitted when the owner requests to buy a ComponentToken.
     * @param owner Address of the owner who requested to buy the ComponentToken.
     * @param componentToken ComponentToken that was requested to be bought.
     * @param assets Amount of `asset` requested to be paid.
     * @param requestId The ID of the buy request.
     */
    event ComponentTokenBuyRequested(
        address indexed owner, IComponentToken indexed componentToken, uint256 assets, uint256 requestId
    );

    /**
     * @notice Emitted when the owner requests to sell a ComponentToken.
     * @param owner Address of the owner who requested to sell the ComponentToken.
     * @param componentToken ComponentToken that was requested to be sold.
     * @param componentTokenAmount Amount of ComponentToken requested to be sold.
     * @param requestId The ID of the sell request.
     */
    event ComponentTokenSellRequested(
        address indexed owner, IComponentToken indexed componentToken, uint256 componentTokenAmount, uint256 requestId
    );

}
