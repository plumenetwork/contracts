// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script, console2 } from "forge-std/Script.sol";
import { stPlumeMinter } from "../../src/lst/stPlumeMinter.sol";

/// @title FulfillAndSweep
/// @notice Example ops script to sweep matured buckets and fulfill a small FIFO slice from buffer
contract FulfillAndSweep is Script {
    function run() external {
        address minterAddr = vm.envAddress("STPLUME_MINTER");
        stPlumeMinter minter = stPlumeMinter(minterAddr);

        // Optional: target a single validator sweep with bounded cap
        uint16 validatorId = uint16(vm.envUint("VALIDATOR_ID"));
        uint256 maxSweep = _envOrUint("MAX_SWEEP", 3);

        vm.startBroadcast();
        if (validatorId != 0 && maxSweep > 0) {
            (uint256 swept, uint256 gained) = minter.sweepMaturedBuckets(validatorId, maxSweep);
            console2.log("sweep: swept", swept, "gained", gained);
        }

        // Build a small FIFO slice for a single user (example)
        address user = vm.envAddress("USER");
        uint256 startId = _envOrUint("START_ID", 0);
        (uint256[] memory ids, bool[] memory inst, uint256[] memory amts, uint256[] memory defs, uint256 count) =
            minter.getReadyRequestsForUser(user, startId, 10);
        if (count > 0) {
            // Trim arrays to count
            address[] memory users = new address[](count);
            uint256[] memory useIds = new uint256[](count);
            for (uint256 i = 0; i < count; i++) { users[i] = user; useIds[i] = ids[i]; }
            (uint256 processed, uint256 totalPaid) = minter.fulfillRequests(users, useIds);
            console2.log("fulfill: processed", processed, "paid", totalPaid);
        }
        vm.stopBroadcast();
    }

    function _envOrUint(string memory key, uint256 fallbackVal) internal view returns (uint256) {
        try vm.envUint(key) returns (uint256 v) { return v; } catch { return fallbackVal; }
    }
}


