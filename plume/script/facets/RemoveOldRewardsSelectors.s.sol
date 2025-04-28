// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script, console2 } from "forge-std/Script.sol";

// --- SolidState Diamond Interfaces ---

import { IERC2535DiamondCutInternal } from "@solidstate/interfaces/IERC2535DiamondCutInternal.sol";
import { IERC2535DiamondLoupe } from "@solidstate/interfaces/IERC2535DiamondLoupe.sol";
import { ISolidStateDiamond } from "@solidstate/proxy/diamond/ISolidStateDiamond.sol";

/**
 * @title RemoveOldRewardsSelectors
 * @notice Script to REMOVE 5 specific selectors (old checkpoint views) from the PlumeStaking Diamond.
 */
contract RemoveOldRewardsSelectors is Script {

    // --- Configuration ---
    address private constant UPGRADER_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;
    address private constant DIAMOND_PROXY_ADDRESS = 0xA20bfe49969D4a0E9abfdb6a46FeD777304ba07f;

    function run() external {
        vm.startBroadcast(UPGRADER_ADDRESS);

        console2.log("--- Starting Removal of Old Rewards Selectors --- ");
        console2.log("Target Proxy:", DIAMOND_PROXY_ADDRESS);
        console2.log("Upgrader Address:", UPGRADER_ADDRESS);

        // --- Define Selectors to Remove ---
        bytes4[] memory selectorsToRemove = new bytes4[](5);
        selectorsToRemove[0] = 0xe5f9d436; // getRewardRateCheckpointCount(address)
        selectorsToRemove[1] = 0x630e9560; // getValidatorRewardRateCheckpointCount(uint16,address)
        selectorsToRemove[2] = 0x4b1328cc; // getUserLastCheckpointIndex(address,uint16,address)
        selectorsToRemove[3] = 0xcf07e31d; // getRewardRateCheckpoint(address,uint256)
        selectorsToRemove[4] = 0xc1a6956d; // getValidatorRewardRateCheckpoint(uint16,address,uint256)

        console2.log("\n1. Preparing to remove", selectorsToRemove.length, "selectors...");

        // --- Step 2: Prepare Diamond Cut ---
        console2.log("\n2. Preparing Diamond Cut (REMOVE)...");
        IERC2535DiamondCutInternal.FacetCut[] memory cut = new IERC2535DiamondCutInternal.FacetCut[](1);

        cut[0] = IERC2535DiamondCutInternal.FacetCut({
            target: address(0), // Target is address(0) for REMOVE
            action: IERC2535DiamondCutInternal.FacetCutAction.REMOVE,
            selectors: selectorsToRemove
        });
        console2.log("  Prepared REMOVE cut for 5 selectors.");

        // --- Step 3: Execute Diamond Cut ---
        console2.log("\n3. Executing Diamond Cut...");
        ISolidStateDiamond(payable(DIAMOND_PROXY_ADDRESS)).diamondCut(cut, address(0), "");
        console2.log("  Diamond Cut executed successfully.");

        // --- Step 4: Verification ---
        console2.log("\n4. Verifying removal...");
        IERC2535DiamondLoupe loupe = IERC2535DiamondLoupe(DIAMOND_PROXY_ADDRESS);
        bool removalVerified = true;
        console2.log("  Verifying removed selectors now point to address(0)...");

        for (uint256 i = 0; i < selectorsToRemove.length; i++) {
            bytes4 selector = selectorsToRemove[i];
            address currentImpl = loupe.facetAddress(selector);
            if (currentImpl != address(0)) {
                //console2.log("    REMOVAL FAILED! Selector", selector, "still points to", currentImpl, "Expected:
                // address(0)");
                removalVerified = false;
            }
        }
        console2.log("  Removal verification result:", removalVerified ? "Passed" : "Failed");
        require(removalVerified, "Selector removal verification failed");

        // Optional: Verify the old facet address no longer appears in facets() output,
        // although this depends on the specific diamond implementation's behavior.
        // console2.log("\nChecking reported facets...");
        // IERC2535DiamondLoupe.Facet[] memory reportedFacets = loupe.facets();
        // bool oldFacetFound = false;
        // for (uint i = 0; i < reportedFacets.length; i++) {
        //     if (reportedFacets[i].target == 0x817D37e0C3BCfecC713158A4366186FbBea071C3) {
        //         oldFacetFound = true;
        //         console2.log("  WARNING: Old facet address still reported by facets(), check its selector list.");
        //         break;
        //     }
        // }
        // if (!oldFacetFound) {
        //     console2.log("  Old facet address no longer reported by facets().");
        // }

        console2.log("\n--- Old Rewards Selectors Removal Complete --- ");

        vm.stopBroadcast();
    }

}
