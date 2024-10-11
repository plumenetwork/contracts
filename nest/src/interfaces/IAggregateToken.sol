// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IComponentToken } from "./IComponentToken.sol";

interface IAggregateToken {

    function buyComponentToken(IComponentToken componentToken, uint256 currencyTokenAmount) external;
    function sellComponentToken(IComponentToken componentToken, uint256 currencyTokenAmount) external;

}
