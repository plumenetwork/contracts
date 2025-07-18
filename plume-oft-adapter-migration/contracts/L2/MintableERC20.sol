// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

abstract contract MintableERC20 is ERC20 {
    function mint(address to, uint256 amount) external virtual;
}