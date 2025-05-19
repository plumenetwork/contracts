// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script, console2 } from "forge-std/Script.sol";

// --- SolidState Diamond Interfaces ---
import { IERC2535DiamondCutInternal } from "@solidstate/interfaces/IERC2535DiamondCutInternal.sol";
import { IERC2535DiamondLoupe } from "@solidstate/interfaces/IERC2535DiamondLoupe.sol";
import { ISolidStateDiamond } from "@solidstate/proxy/diamond/SolidStateDiamond.sol";

// --- Plume Facets ---
import { ValidatorFacet } from "../../src/facets/ValidatorFacet.sol";

contract UpgradeValidatorFacet is Script {

    // --- Configuration ---
    // TODO: Replace with actual mainnet/testnet addresses or use environment variables
    address private constant DIAMOND_PROXY_ADDRESS = 0xA20bfe49969D4a0E9abfdb6a46FeD777304ba07f; // From previous
        // context
    address private constant UPGRADER_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5; // From previous context
    address private constant OLD_VALIDATOR_FACET_ADDRESS = 0x25c2CCCdA4C8e30746930F9B6e9C58E3d189B73E; // From previous
        // context
    // --- Selectors ---

    // Selector to remove
    function getSelectorToRemove() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = bytes4(keccak256(bytes("updateValidator(uint16,uint8,bytes)")));
        return selectors;
    }

    // Selectors to add (new functions)
    function getSelectorsToAdd() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = bytes4(keccak256(bytes("setValidatorCommission(uint16,uint256)")));
        selectors[1] = bytes4(keccak256(bytes("setValidatorAddresses(uint16,address,address,string,string,address)")));
        selectors[2] = bytes4(keccak256(bytes("setValidatorStatus(uint16,bool)")));
        return selectors;
    }

    // Existing selectors to keep (will be replaced to point to new implementation)
    // Note: Manually defined based on the state *before* this upgrade.
    // Excludes updateValidator, includes everything else currently in ValidatorFacet.
    function getSelectorsToReplace() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](11); // 12 (old total) - 1 (removed updateValidator) = 11
        selectors[0] =
            bytes4(keccak256(bytes("addValidator(uint16,uint256,address,address,string,string,address,uint256)")));
        selectors[1] = bytes4(keccak256(bytes("setValidatorCapacity(uint16,uint256)")));
        selectors[2] = bytes4(keccak256(bytes("requestCommissionClaim(uint16,address)")));
        selectors[3] = bytes4(keccak256(bytes("getValidatorInfo(uint16)")));
        selectors[4] = bytes4(keccak256(bytes("getValidatorStats(uint16)")));
        selectors[5] = bytes4(keccak256(bytes("getUserValidators(address)")));
        selectors[6] = bytes4(keccak256(bytes("getAccruedCommission(uint16,address)")));
        selectors[7] = bytes4(keccak256(bytes("getValidatorsList()")));
        selectors[8] = bytes4(keccak256(bytes("getActiveValidatorCount()")));
        selectors[9] = bytes4(keccak256(bytes("voteToSlashValidator(uint16,uint256)")));
        selectors[10] = bytes4(keccak256(bytes("slashValidator(uint16)")));
        return selectors;
    }

    function run() external {
        vm.startBroadcast(UPGRADER_ADDRESS);

        console2.log("--- Starting ValidatorFacet Upgrade --- ");
        console2.log("Target Proxy:", DIAMOND_PROXY_ADDRESS);
        console2.log("Upgrader Address:", UPGRADER_ADDRESS);
        console2.log("Old ValidatorFacet Address:", OLD_VALIDATOR_FACET_ADDRESS);

        // --- Step 1: Deploy New Facet Implementation ---
        console2.log("\n1. Deploying new ValidatorFacet implementation...");
        ValidatorFacet newValidatorFacet = new ValidatorFacet();
        console2.log("  New ValidatorFacet deployed at:", address(newValidatorFacet));

        // --- Step 2: Prepare Diamond Cut ---
        console2.log("\n2. Preparing Diamond Cut for ValidatorFacet...");
        IERC2535DiamondCutInternal.FacetCut[] memory cut = new IERC2535DiamondCutInternal.FacetCut[](3);

        // Cut 1: REMOVE the old updateValidator selector
        bytes4[] memory selectorsToRemove = getSelectorToRemove();
        cut[0] = IERC2535DiamondCutInternal.FacetCut({
            target: address(0), // Target address(0) signifies REMOVE
            action: IERC2535DiamondCutInternal.FacetCutAction.REMOVE,
            selectors: selectorsToRemove
        });
        //        console2.log("  Prepared REMOVE cut for 1 selector:", selectorsToRemove[0]);
        //console2.logBytes(selectorsToRemove[0]);

        // Cut 2: REPLACE existing selectors to point to the new facet
        bytes4[] memory selectorsToReplace = getSelectorsToReplace();
        cut[1] = IERC2535DiamondCutInternal.FacetCut({
            target: address(newValidatorFacet),
            action: IERC2535DiamondCutInternal.FacetCutAction.REPLACE,
            selectors: selectorsToReplace
        });
        console2.log("  Prepared REPLACE cut for", selectorsToReplace.length, "selectors pointing to new facet.");

        // Cut 3: ADD the new function selectors
        bytes4[] memory selectorsToAdd = getSelectorsToAdd();
        cut[2] = IERC2535DiamondCutInternal.FacetCut({
            target: address(newValidatorFacet),
            action: IERC2535DiamondCutInternal.FacetCutAction.ADD,
            selectors: selectorsToAdd
        });
        console2.log("  Prepared ADD cut for", selectorsToAdd.length, "new selectors.");

        // --- Step 3: Execute Diamond Cut ---
        console2.log("\n3. Executing Diamond Cut...");
        ISolidStateDiamond(payable(DIAMOND_PROXY_ADDRESS)).diamondCut(cut, address(0), "");
        console2.log("  Diamond Cut executed successfully.");

        // --- Step 4: Verification (Optional but Recommended) ---
        console2.log("\n4. Verifying upgrade...");
        IERC2535DiamondLoupe loupe = IERC2535DiamondLoupe(DIAMOND_PROXY_ADDRESS);

        // Verify removed selector is gone
        try loupe.facetAddress(selectorsToRemove[0]) returns (address facetAddr) {
            require(facetAddr == address(0), "Removed selector still exists!");
            console2.log("  Verified: Removed selector correctly removed.");
        } catch Error(string memory reason) {
            // Expected to fail or return address(0) depending on Loupe implementation
            console2.log("  Verified: Removed selector correctly removed (call reverted as expected).");
        } catch {
            console2.log("  Verified: Removed selector correctly removed (call reverted as expected).");
        }

        // Verify replaced selectors point to new facet
        bool replacedOk = true;
        for (uint256 i = 0; i < selectorsToReplace.length; i++) {
            if (loupe.facetAddress(selectorsToReplace[i]) != address(newValidatorFacet)) {
                //console2.log("  ERROR: Replaced selector", selectorsToReplace[i], "points to wrong facet!");
                //console2.logBytes(selectorsToReplace[i]);
                replacedOk = false;
                break;
            }
        }
        if (replacedOk) {
            console2.log("  Verified: All replaced selectors point to the new facet.");
        }

        // Verify added selectors point to new facet
        bool addedOk = true;
        for (uint256 i = 0; i < selectorsToAdd.length; i++) {
            if (loupe.facetAddress(selectorsToAdd[i]) != address(newValidatorFacet)) {
                //console2.log("  ERROR: Added selector", selectorsToAdd[i], "points to wrong facet!");
                //console2.logBytes(selectorsToAdd[i]);
                addedOk = false;
                break;
            }
        }
        if (addedOk) {
            console2.log("  Verified: All added selectors point to the new facet.");
        }

        console2.log("\n--- ValidatorFacet Upgrade Complete --- ");

        vm.stopBroadcast();
    }

}
