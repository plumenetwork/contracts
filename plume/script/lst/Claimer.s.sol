// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script, console2 } from "forge-std/Script.sol";
import { stPlumeMinter } from "../../src/lst/stPlumeMinter.sol";

/// @title Claimer
/// @notice Periodic claim and load rewards runner for stPlumeMinter
contract Claimer is Script {
    function run() external {
        address minterAddr = vm.envAddress("STPLUME_MINTER");
        stPlumeMinter minter = stPlumeMinter(minterAddr);

        vm.startBroadcast();
        // Let minter decide whether to claim per-validator or claimAll; here use claimAll
        uint256[] memory amounts = minter.claimAll();
        console2.log("claimAll tokens:", amounts.length);
        for (uint256 i = 0; i < amounts.length; i++) {
            console2.log("token idx", i, "amount", amounts[i]);
        }
        vm.stopBroadcast();
    }
}


