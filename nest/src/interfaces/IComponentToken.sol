// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

interface IComponentToken is IERC20 {

    function buy(address currencyAddress, uint256 amount) external;
    function sell(address currencyAddress, uint256 amount) external;

}
