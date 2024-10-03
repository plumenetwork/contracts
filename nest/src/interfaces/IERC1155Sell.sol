// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IComponentToken } from "./IComponentToken.sol";

/**
 * @title IERC1155Sell
 * Example for a Deposit-Aware sell in a MultiToken vault
 */
interface IERC1155Sell is IComponentToken {

    /**
     * @notice Submit a request to sell shares at the given deposit periods
     * @param shares The amount of shares to sell.
     * @param depositPeriods The deposit periods when the shares were issued.
     * @return requestId Unique identifier for the sell request
     * @return assets The equivalent amount of assets for the shares
     */
    function requestSell(
        uint256[] memory shares,
        uint256[] memory depositPeriods
    ) external view returns (uint256 requestId, uint256[] memory assets);

}