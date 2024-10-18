// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IYieldDistributionToken } from "./IYieldDistributionToken.sol";

interface IAssetToken is IYieldDistributionToken {

    function depositYield(uint256 currencyTokenAmount) external;
    function getBalanceAvailable(address user) external view returns (uint256 balanceAvailable);

}
