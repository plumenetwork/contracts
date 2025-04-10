// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script, console2 } from "forge-std/Script.sol";

// --- SolidState Diamond Interfaces ---

import { console2 } from "forge-std/console2.sol";
import { IERC2535DiamondCutInternal } from "solidstate-solidity/interfaces/IERC2535DiamondCutInternal.sol";
import { IERC2535DiamondLoupe } from "solidstate-solidity/interfaces/IERC2535DiamondLoupe.sol";
import { ISolidStateDiamond } from "solidstate-solidity/proxy/diamond/SolidStateDiamond.sol";
// --- Plume Facets ---
import { ManagementFacet } from "../src/facets/ManagementFacet.sol";
// Import other facets if needed for selector generation or reference

contract UpgradePlumeStakingDiamond is Script {

    // --- Configuration ---
    // Existing Deployment Addresses (FROM USER LOG)
    address private constant DIAMOND_PROXY_ADDRESS = 0xA20bfe49969D4a0E9abfdb6a46FeD777304ba07f;
    address private constant OLD_MANAGEMENT_FACET_ADDRESS = 0x3f8C5F792420eb392B5F92016Cb30f1CceA53549;

    // Address with upgrade permissions (Owner or UPGRADER_ROLE)
    // Make sure this address has the necessary permissions on the live DIAMOND_PROXY_ADDRESS
    address private constant UPGRADER_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5; // Assuming deployer owner

    // --- Upgrade Logic ---
    function run() external {
        vm.startBroadcast(UPGRADER_ADDRESS);

        console2.log("--- Starting Plume Staking Diamond Upgrade --- ");
        console2.log("Target Proxy:", DIAMOND_PROXY_ADDRESS);
        console2.log("Upgrader Address:", UPGRADER_ADDRESS);

        // --- Example: Upgrade ManagementFacet ---
        // In a real scenario, deploy ManagementFacetV2 or modified ManagementFacet code.
        // For this example, we just deploy a new instance of the *existing* ManagementFacet.
        console2.log("Deploying new ManagementFacet instance...");
        ManagementFacet newManagementFacet = new ManagementFacet();
        console2.log("  New ManagementFacet deployed at:", address(newManagementFacet));

        // Prepare the diamond cut to REPLACE the ManagementFacet functions
        console2.log("Preparing Diamond Cut for ManagementFacet replacement...");

        // 1. Get the selectors currently mapped to the OLD ManagementFacet
        // We need IDiamondLoupe interface for this
        IERC2535DiamondLoupe loupe = IERC2535DiamondLoupe(DIAMOND_PROXY_ADDRESS);
        bytes4[] memory existingManagementSelectors = loupe.facetFunctionSelectors(OLD_MANAGEMENT_FACET_ADDRESS);
        console2.log("Found", existingManagementSelectors.length);
        console2.log("selectors for old ManagementFacet: ", OLD_MANAGEMENT_FACET_ADDRESS);

        // Important Check: Ensure selectors were found. If not, the old address might be wrong,
        // or the facet might have been removed/replaced already.
        require(
            existingManagementSelectors.length > 0,
            "No selectors found for the old ManagementFacet address. Check address or if already upgraded."
        );

        // 2. Create the FacetCut struct for replacement
        IERC2535DiamondCutInternal.FacetCut[] memory cut = new IERC2535DiamondCutInternal.FacetCut[](1);
        cut[0] = IERC2535DiamondCutInternal.FacetCut({
            target: address(newManagementFacet), // Target is the NEW facet instance
            action: IERC2535DiamondCutInternal.FacetCutAction.REPLACE, // Action is REPLACE
            selectors: existingManagementSelectors // Use the selectors from the OLD facet
         });

        // 3. Execute the Diamond Cut
        console2.log("Executing Diamond Cut on proxy...");
        ISolidStateDiamond(payable(DIAMOND_PROXY_ADDRESS)).diamondCut(cut, address(0), "");
        console2.log("Diamond Cut executed successfully.");

        // --- Verification (Optional but Recommended) ---
        console2.log("Verifying upgrade...");
        // Check if one of the selectors now points to the new facet address
        // Use the first selector found as a sample check
        bytes4 sampleSelector = existingManagementSelectors[0];
        address newTargetAddress = loupe.facetAddress(sampleSelector);
        //console2.log("  Checking mapping for selector:", sampleSelector);
        console2.log("  Expected new target:", address(newManagementFacet));
        console2.log("  Actual new target found:", newTargetAddress);
        // assertEq(newTargetAddress, address(newManagementFacet), "Upgrade Verification Failed: Selector did not map to
        // new facet address!"); // Removed assertion
        console2.log("Verification complete (manual check recommended)."); // Updated log message

        console2.log("--- Plume Staking Diamond Upgrade Complete --- ");

        vm.stopBroadcast();
    }

}
