// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IComponentToken } from "./IComponentToken.sol";

interface IAggregateToken is IComponentToken {

    // ========== PUBLIC VIEW FUNCTIONS ==========

    /**
     * @notice Get the current ask price for buying the AggregateToken
     * @return uint256 Current ask price
     */
    function getAskPrice() external view returns (uint256);

    /**
     * @notice Get the current bid price for selling the AggregateToken
     * @return uint256 Current bid price
     */
    function getBidPrice() external view returns (uint256);

    /**
     * @notice Get the list of all component tokens ever added
     * @return IComponentToken[] Array of component token addresses
     */
    function getComponentTokenList() external view returns (IComponentToken[] memory);

    /**
     * @notice Check if an address is a registered component token
     * @param componentToken ComponentToken to check
     * @return bool indicating whether the address is a component token
     */
    function getComponentToken(
        IComponentToken componentToken
    ) external view returns (bool);

    /**
     * @notice Check if trading operations are paused
     * @return bool indicating whether trading is paused
     */
    function isPaused() external view returns (bool);

    // ========== ADMIN FUNCTIONS ==========

    /**
     * @notice Add a new component token to the aggregate token
     * @dev Only callable by ADMIN_ROLE
     * @param componentToken Address of the component token to add
     */
    function addComponentToken(
        IComponentToken componentToken
    ) external;

    /**
     * @notice Approve a component token to spend aggregate token's assets
     * @dev Only callable by ADMIN_ROLE
     * @param componentToken Address of the component token to approve
     * @param amount Amount of assets to approve
     */
    function approveComponentToken(IComponentToken componentToken, uint256 amount) external;

    /**
     * @notice Buy component tokens using the aggregate token's assets
     * @dev Only callable by ADMIN_ROLE
     * @param componentToken Address of the component token to buy
     * @param assets Amount of assets to spend
     */
    function buyComponentToken(IComponentToken componentToken, uint256 assets) external;

    /**
     * @notice Sell component tokens to receive aggregate token's assets
     * @dev Only callable by ADMIN_ROLE
     * @param componentToken Address of the component token to sell
     * @param componentTokenAmount Amount of component tokens to sell
     */
    function sellComponentToken(IComponentToken componentToken, uint256 componentTokenAmount) external;

    /**
     * @notice Request to buy component tokens (for async operations)
     * @dev Only callable by ADMIN_ROLE
     * @param componentToken Address of the component token to buy
     * @param assets Amount of assets to spend
     */
    function requestBuyComponentToken(IComponentToken componentToken, uint256 assets) external;

    /**
     * @notice Request to sell component tokens (for async operations)
     * @dev Only callable by ADMIN_ROLE
     * @param componentToken Address of the component token to sell
     * @param componentTokenAmount Amount of component tokens to sell
     */
    function requestSellComponentToken(IComponentToken componentToken, uint256 componentTokenAmount) external;

    /**
     * @notice Set the ask price for the aggregate token
     * @dev Only callable by PRICE_UPDATER_ROLE
     * @param newAskPrice New ask price to set
     */
    function setAskPrice(
        uint256 newAskPrice
    ) external;

    /**
     * @notice Set the bid price for the aggregate token
     * @dev Only callable by PRICE_UPDATER_ROLE
     * @param newBidPrice New bid price to set
     */
    function setBidPrice(
        uint256 newBidPrice
    ) external;

    /**
     * @notice Pause all trading operations
     * @dev Only callable by ADMIN_ROLE
     */
    function pause() external;

    /**
     * @notice Unpause all trading operations
     * @dev Only callable by ADMIN_ROLE
     */
    function unpause() external;

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
