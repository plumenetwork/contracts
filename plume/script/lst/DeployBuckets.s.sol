// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script, console2 } from "forge-std/Script.sol";
import { stPlumeMinter } from "../../src/lst/stPlumeMinter.sol";

/// @title DeployBuckets
/// @notice Script stub to append staking buckets per validator for stPlumeMinter
/// @dev Usage (examples):
///   STPLUME_MINTER=0x... VALIDATOR_IDS="1001,1002" BUCKETS_PER_VALIDATOR=3 \
///     forge script plume/script/lst/DeployBuckets.s.sol:DeployBuckets --rpc-url $RPC --broadcast -vvvv
contract DeployBuckets is Script {

    function run() external {
        address minterAddr = vm.envAddress("STPLUME_MINTER");
        stPlumeMinter minter = stPlumeMinter(minterAddr);

        // default buckets per validator = 2
        uint256 bucketsPerVal = _envOrUint("BUCKETS_PER_VALIDATOR", 2);

        string memory idsCsv = _envOr("VALIDATOR_IDS", "");
        uint16[] memory ids = _parseIds(idsCsv);
        require(ids.length > 0, "Provide VALIDATOR_IDS env (comma-separated)");

        console2.log("stPlumeMinter:", minterAddr);
        console2.log("Buckets per validator:", bucketsPerVal);
        console2.log("Validators to configure:", ids.length);

        vm.startBroadcast();
        for (uint256 i = 0; i < ids.length; i++) {
            console2.log("Adding buckets for validator:", ids[i]);
            minter.addBuckets(ids[i], bucketsPerVal);
        }
        vm.stopBroadcast();
    }

    function _envOr(string memory key, string memory fallbackVal) internal view returns (string memory) {
        try vm.envString(key) returns (string memory v) {
            return v;
        } catch { return fallbackVal; }
    }

    function _envOrUint(string memory key, uint256 fallbackVal) internal view returns (uint256) {
        try vm.envUint(key) returns (uint256 v) {
            return v;
        } catch { return fallbackVal; }
    }

    function _parseIds(string memory csv) internal pure returns (uint16[] memory out) {
        bytes memory b = bytes(csv);
        if (b.length == 0) {
            return new uint16[](0);
        }
        // Count commas
        uint256 parts = 1;
        for (uint256 i = 0; i < b.length; i++) if (b[i] == ",") parts++;
        out = new uint16[](parts);
        uint256 idx = 0; uint256 acc = 0; bool seen = false;
        for (uint256 i = 0; i <= b.length; i++) {
            if (i == b.length || b[i] == ",") {
                if (seen) {
                    out[idx++] = uint16(acc);
                    acc = 0; seen = false;
                }
            } else {
                require(b[i] >= "0" && b[i] <= "9", "Invalid VALIDATOR_IDS char");
                acc = acc * 10 + (uint8(b[i]) - uint8(bytes1("0")));
                seen = true;
            }
        }
        // shrink if needed
        if (idx < parts) {
            uint16[] memory shr = new uint16[](idx);
            for (uint256 j = 0; j < idx; j++) shr[j] = out[j];
            out = shr;
        }
    }
}


