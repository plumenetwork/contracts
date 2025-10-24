// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import { StdCheats } from "forge-std/StdCheats.sol";

contract MockNativeTokenManager is StdCheats {
    uint256 public burnedAmount;
    uint256 public mintedAmount;

    function mintNativeToken(uint256 amount) external {
        mintedAmount += amount;
        deal(msg.sender, amount);
    }

    function burnNativeToken(uint256 amount) external {
        burnedAmount += amount;
        deal(msg.sender, msg.sender.balance - amount);
    }
}