// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IAssetToken } from "./IAssetToken.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IYieldReceiver {

    function receiveYield(IAssetToken assetToken, IERC20 currencyToken, uint256 currencyTokenAmount) external;

}
