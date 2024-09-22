// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IYieldDistributionToken is IERC20 {

    function getCurrencyToken() external returns (ERC20 currencyToken);
    function claimYield(address user) external returns (ERC20 currencyToken, uint256 currencyTokenAmount);
    function accrueYield(address user) external;

}
