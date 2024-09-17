// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IYieldDistributionToken is IERC20 {

    function claimYield() external returns (address currency, uint256 amount);
    function processYield(address user) external;
    function _depositYield(uint256 timestamp, uint256 amount) internal;

}
