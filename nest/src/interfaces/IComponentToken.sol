// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IComponentToken is IERC20 {
    function buy(uint256 amount) external;
    function sell(uint256 amount) external;
    function claim(uint256 amount) external;
    function claimAll() external;
}