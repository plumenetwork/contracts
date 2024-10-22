// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IYieldDistributionToken is IERC20 {

    function getCurrencyToken() external returns (IERC20 currencyToken);
    function claimYield(
        address user
    ) external returns (IERC20 currencyToken, uint256 currencyTokenAmount);
    function accrueYield(
        address user
    ) external;
    function requestYield(
        address from
    ) external;

}
