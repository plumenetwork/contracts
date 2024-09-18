// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IComponentToken } from "./IComponentToken.sol";

interface IAggregateToken is IComponentToken {

    function buyComponentToken(IComponentToken componentToken, uint256 currencyTokenAmount) external;
    function sellComponentToken(IComponentToken componentToken, uint256 currencyTokenAmount) external;
    function getAskPrice() external view returns (uint256 askPrice);
    function getBidPrice() external view returns (uint256 bidPrice);
    function getTokenURI() external view returns (string memory tokenURI);
    function getComponentTokenList() external view returns (IComponentToken[] memory componentTokenList);

}
