// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IComponentToken is IERC20 {

    function buy(IERC20 currencyToken, uint256 currencyTokenAmount) external returns (uint256 componentTokenAmount);
    function sell(IERC20 currencyToken, uint256 currencyTokenAmount) external returns (uint256 componentTokenAmount);
    function totalYield() external view returns (uint256 amount);
    function claimedYield() external view returns (uint256 amount);
    function unclaimedYield() external view returns (uint256 amount);
    function totalYield(address user) external view returns (uint256 amount);
    function claimedYield(address user) external view returns (uint256 amount);
    function unclaimedYield(address user) external view returns (uint256 amount);

}
