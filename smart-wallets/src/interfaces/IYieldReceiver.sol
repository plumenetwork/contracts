// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { IAssetToken } from "./IAssetToken.sol";

interface IYieldReceiver {

    function receiveYield(IAssetToken assetToken, ERC20 currencyToken, uint256 currencyTokenAmount) external;

}
