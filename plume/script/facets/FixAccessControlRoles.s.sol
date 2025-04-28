// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script, console2 } from "forge-std/Script.sol";

// --- SolidState Diamond Interfaces ---
import { IERC2535DiamondCutInternal } from "solidstate-solidity/interfaces/IERC2535DiamondCutInternal.sol";

import { IERC2535DiamondLoupe } from "solidstate-solidity/interfaces/IERC2535DiamondLoupe.sol";
import { ISolidStateDiamond } from "solidstate-solidity/proxy/diamond/SolidStateDiamond.sol"; // For verification

contract FixAccessControlRoles is Script {

    // --- Configuration ---
    address private constant DIAMOND_PROXY_ADDRESS = 0xA20bfe49969D4a0E9abfdb6a46FeD777304ba07f;
    // Address of the *NEW* AccessControlFacet deployed in the last upgrade attempt
    address private constant NEW_ACCESS_CONTROL_FACET_ADDRESS = 0x5948C896c1bFB1484786dDE70C0c6F1f1dbCb1aF;
    // Address with upgrade permissions
    address private constant UPGRADER_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;

    function run() external {
        vm.startBroadcast(UPGRADER_ADDRESS);

        console2.log("--- Fixing AccessControlFacet Role Selectors --- ");
        console2.log("Target Proxy: %s", DIAMOND_PROXY_ADDRESS);
        console2.log("AccessControlFacet Address: %s", NEW_ACCESS_CONTROL_FACET_ADDRESS);
        console2.log("Upgrader Address: %s", UPGRADER_ADDRESS);

        // --- Define Missing Role Selectors ---
        bytes4[] memory roleSelectorsToAdd = new bytes4[](5);
        roleSelectorsToAdd[0] = bytes4(keccak256(bytes("ADMIN_ROLE()"))); // 0x49c51f90
        roleSelectorsToAdd[1] = bytes4(keccak256(bytes("UPGRADER_ROLE()"))); // 0xb4a0247d
        roleSelectorsToAdd[2] = bytes4(keccak256(bytes("VALIDATOR_ROLE()"))); // 0x189594a9
        roleSelectorsToAdd[3] = bytes4(keccak256(bytes("REWARD_MANAGER_ROLE()"))); // 0x13f32dd9
        roleSelectorsToAdd[4] = bytes4(keccak256(bytes("DEFAULT_ADMIN_ROLE()"))); // 0x2491e5e1

        console2.log("\nPreparing to ADD %d role selectors...", roleSelectorsToAdd.length);

        // --- Prepare Diamond Cut Data (ADD phase) ---
        IERC2535DiamondCutInternal.FacetCut[] memory addCut = new IERC2535DiamondCutInternal.FacetCut[](1);
        addCut[0] = IERC2535DiamondCutInternal.FacetCut({
            target: NEW_ACCESS_CONTROL_FACET_ADDRESS, // Point selectors to the correct, new facet
            action: IERC2535DiamondCutInternal.FacetCutAction.ADD,
            selectors: roleSelectorsToAdd
        });

        // --- Execute ADD Diamond Cut ---
        console2.log("\nExecuting ADD Diamond Cut...");
        ISolidStateDiamond(payable(DIAMOND_PROXY_ADDRESS)).diamondCut(addCut, address(0), "");
        console2.log("  ADD Diamond Cut executed successfully.");

        // --- Verification (Optional but Recommended) ---
        console2.log("\nVerifying role selector mappings...");
        IERC2535DiamondLoupe loupe = IERC2535DiamondLoupe(DIAMOND_PROXY_ADDRESS);
        bool allVerified = true;
        for (uint256 i = 0; i < roleSelectorsToAdd.length; i++) {
            bytes4 selector = roleSelectorsToAdd[i];
            address currentTarget = loupe.facetAddress(selector);
            if (currentTarget != NEW_ACCESS_CONTROL_FACET_ADDRESS) {
                console2.log(
                    "  ERROR: Selector %s points to %s, expected %s",
                    vm.toString(selector),
                    vm.toString(currentTarget),
                    vm.toString(NEW_ACCESS_CONTROL_FACET_ADDRESS)
                );
                allVerified = false;
            } else {
                console2.log(
                    "  OK: Selector %s correctly points to %s", vm.toString(selector), vm.toString(currentTarget)
                );
            }
        }

        if (allVerified) {
            console2.log("\nVerification Successful: All role selectors point to the correct AccessControlFacet.");
        } else {
            console2.log("\nVerification FAILED: One or more role selectors are incorrectly mapped.");
        }

        console2.log("\n--- Role Selector Fix Complete --- ");

        vm.stopBroadcast();
    }

}
