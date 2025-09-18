// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script, console2 } from "forge-std/Script.sol";
import { stPlumeMinter } from "../../src/lst/stPlumeMinter.sol";

interface IValidatorFacetView {
    struct ValidatorListData { uint16 id; uint256 totalStaked; uint256 commission; }
    function getValidatorsList() external view returns (ValidatorListData[] memory list);
}

/// @title SyncValidators
/// @notice Sync diamond validator IDs into stPlumeMinter's local registry
contract SyncValidators is Script {
    function run() external {
        address minterAddr = vm.envAddress("STPLUME_MINTER");
        address diamondAddr = vm.envAddress("DIAMOND_PROXY");
        stPlumeMinter minter = stPlumeMinter(minterAddr);
        IValidatorFacetView dia = IValidatorFacetView(diamondAddr);

        IValidatorFacetView.ValidatorListData[] memory list = dia.getValidatorsList();
        console2.log("Diamond validators:", list.length);

        // Build a set of current minter validators
        uint256 cur = minter.numValidators();
        console2.log("Minter validators (before):", cur);
        mapping(uint256 => bool) storagePresent;
        // Can't use storage in script context; build memory set
        // Pull into memory array
        uint256[] memory existing = new uint256[](cur);
        for (uint256 i = 0; i < cur; i++) {
            existing[i] = minter.getValidator(i);
        }

        vm.startBroadcast();
        uint256 added = 0;
        for (uint256 i = 0; i < list.length; i++) {
            uint256 vid = list[i].id;
            bool found = false;
            for (uint256 j = 0; j < existing.length; j++) {
                if (existing[j] == vid) { found = true; break; }
            }
            if (!found) {
                console2.log("Adding validator to minter:", vid);
                minter.addValidator(minter.getValidatorStruct(vid));
                added++;
            }
        }
        vm.stopBroadcast();

        console2.log("Added:", added);
        console2.log("Minter validators (after):", minter.numValidators());
    }
}


