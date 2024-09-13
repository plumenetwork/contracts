// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IComponentToken is IERC20 {

    function buy(IERC20 currencyToken, uint256 currencyTokenAmount) external returns (uint256 componentTokenAmount);
    function sell(IERC20 currencyToken, uint256 currencyTokenAmount) external returns (uint256 componentTokenAmount);

}
