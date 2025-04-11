// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script, console2 } from "forge-std/Script.sol";

// --- SolidState Diamond Interfaces ---
import { IERC2535DiamondCutInternal } from "solidstate-solidity/interfaces/IERC2535DiamondCutInternal.sol";
import { IERC2535DiamondLoupe } from "solidstate-solidity/interfaces/IERC2535DiamondLoupe.sol";
import { ISolidStateDiamond } from "solidstate-solidity/proxy/diamond/SolidStateDiamond.sol";
import { IERC2535DiamondLoupeInternal } from "solidstate-solidity/interfaces/IERC2535DiamondLoupeInternal.sol";

// --- Plume Facets ---
import { ManagementFacet } from "../src/facets/ManagementFacet.sol";
import { AccessControlFacet } from "../src/facets/AccessControlFacet.sol";
import { ValidatorFacet } from "../src/facets/ValidatorFacet.sol";
import { StakingFacet } from "../src/facets/StakingFacet.sol";
import { RewardsFacet } from "../src/facets/RewardsFacet.sol";

// Import PlumeRoles for AccessControl selectors
import { PlumeRoles } from "../src/lib/PlumeRoles.sol";

// --- Plume Libraries ---
// Note: Libraries like PlumeErrors.sol and PlumeEvents.sol are imported by the facets
// We don't need to explicitly interact with them in the upgrade script
// They are automatically included when the facets that use them are deployed

contract UpgradePlumeStakingDiamond is Script {

    // --- Configuration ---
    // Existing Deployment Addresses (FROM USER LOG)
    address private constant DIAMOND_PROXY_ADDRESS = 0xA20bfe49969D4a0E9abfdb6a46FeD777304ba07f;
    
    // Current facet addresses (need to be updated with actual addresses from deployment)
    address private constant OLD_MANAGEMENT_FACET_ADDRESS = 0xa3f4eCaf23D44C2b5a470ea0cca390CDC39fA4Ac;
    // AccessControl is new - no existing address
    address private constant OLD_VALIDATOR_FACET_ADDRESS = 0x08e8fDE10B1431a5779Dd29476354a0CAb44fD64;
    address private constant OLD_STAKING_FACET_ADDRESS = 0xe2dB62b5C45b2B6B3285c764B2cC99cc0755f132;
    address private constant OLD_REWARDS_FACET_ADDRESS = 0xA107b42875C24ba5c43BFF916ca341283097Ca67;

    // Address with upgrade permissions (Owner or UPGRADER_ROLE)
    // Make sure this address has the necessary permissions on the live DIAMOND_PROXY_ADDRESS
    address private constant UPGRADER_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5; // Assuming deployer owner

    // --- Upgrade Logic ---
    function run() external {
        vm.startBroadcast(UPGRADER_ADDRESS);

        console2.log("--- Starting Plume Staking Diamond Upgrade --- ");
        console2.log("Target Proxy:", DIAMOND_PROXY_ADDRESS);
        console2.log("Upgrader Address:", UPGRADER_ADDRESS);

        // --- Step 1: Deploy New Facet Implementations ---
        console2.log("\n1. Deploying new facet implementations...");
        
        // Deploy new versions of all facets
        ManagementFacet newManagementFacet = new ManagementFacet();
        AccessControlFacet newAccessControlFacet = new AccessControlFacet();
        ValidatorFacet newValidatorFacet = new ValidatorFacet();
        StakingFacet newStakingFacet = new StakingFacet();
        RewardsFacet newRewardsFacet = new RewardsFacet();
        
        console2.log("  New ManagementFacet deployed at:", address(newManagementFacet));
        console2.log("  New AccessControlFacet deployed at:", address(newAccessControlFacet));
        console2.log("  New ValidatorFacet deployed at:", address(newValidatorFacet));
        console2.log("  New StakingFacet deployed at:", address(newStakingFacet));
        console2.log("  New RewardsFacet deployed at:", address(newRewardsFacet));

        // --- Step 2: Get Diamond Loupe for Selector Information ---
        console2.log("\n2. Getting existing facet information...");
        IERC2535DiamondLoupe loupe = IERC2535DiamondLoupe(DIAMOND_PROXY_ADDRESS);
        
        // Get all facets - using the correct struct to handle the return value
        IERC2535DiamondLoupeInternal.Facet[] memory facets = loupe.facets();
        console2.log("  Total facets in diamond:", facets.length);
        
        // --- Step 3: Prepare Diamond Cut for upgrades ---
        console2.log("\n3. Preparing Diamond Cut for facet upgrades...");
        
        // Create cut array (max 5 elements, one for each facet)
        uint256 cutCount = 0;
        IERC2535DiamondCutInternal.FacetCut[] memory cut = new IERC2535DiamondCutInternal.FacetCut[](5);
        
        // --- Handling ManagementFacet upgrade ---
        if (OLD_MANAGEMENT_FACET_ADDRESS != address(0)) {
            bytes4[] memory managementSelectors = loupe.facetFunctionSelectors(OLD_MANAGEMENT_FACET_ADDRESS);
            if (managementSelectors.length > 0) {
                cut[cutCount] = IERC2535DiamondCutInternal.FacetCut({
                    target: address(newManagementFacet),
                    action: IERC2535DiamondCutInternal.FacetCutAction.REPLACE,
                    selectors: managementSelectors
                });
                cutCount++;
                console2.log("  Added ManagementFacet upgrade with", managementSelectors.length, "selectors");
            }
        }
        
        // --- Handling AccessControlFacet ADDITION (not upgrade) ---
        // Define AccessControl selectors manually since it's new
        bytes4[] memory accessControlSelectors = new bytes4[](7);
        accessControlSelectors[0] = bytes4(keccak256(bytes("initializeAccessControl()")));
        accessControlSelectors[1] = bytes4(keccak256(bytes("hasRole(bytes32,address)")));
        accessControlSelectors[2] = bytes4(keccak256(bytes("getRoleAdmin(bytes32)")));
        accessControlSelectors[3] = bytes4(keccak256(bytes("grantRole(bytes32,address)")));
        accessControlSelectors[4] = bytes4(keccak256(bytes("revokeRole(bytes32,address)")));
        accessControlSelectors[5] = bytes4(keccak256(bytes("renounceRole(bytes32,address)")));
        accessControlSelectors[6] = bytes4(keccak256(bytes("setRoleAdmin(bytes32,bytes32)")));
        
        // Add the AccessControlFacet as a new facet (ADD operation)
        cut[cutCount] = IERC2535DiamondCutInternal.FacetCut({
            target: address(newAccessControlFacet),
            action: IERC2535DiamondCutInternal.FacetCutAction.ADD,
            selectors: accessControlSelectors
        });
        cutCount++;
        console2.log("  Added NEW AccessControlFacet with", accessControlSelectors.length, "selectors");
        
        // --- Handling ValidatorFacet upgrade ---
        if (OLD_VALIDATOR_FACET_ADDRESS != address(0)) {
            bytes4[] memory validatorSelectors = loupe.facetFunctionSelectors(OLD_VALIDATOR_FACET_ADDRESS);
            if (validatorSelectors.length > 0) {
                cut[cutCount] = IERC2535DiamondCutInternal.FacetCut({
                    target: address(newValidatorFacet),
                    action: IERC2535DiamondCutInternal.FacetCutAction.REPLACE,
                    selectors: validatorSelectors
                });
                cutCount++;
                console2.log("  Added ValidatorFacet upgrade with", validatorSelectors.length, "selectors");
            }
        }
        
        // --- Handling StakingFacet upgrade ---
        if (OLD_STAKING_FACET_ADDRESS != address(0)) {
            bytes4[] memory stakingSelectors = loupe.facetFunctionSelectors(OLD_STAKING_FACET_ADDRESS);
            if (stakingSelectors.length > 0) {
                cut[cutCount] = IERC2535DiamondCutInternal.FacetCut({
                    target: address(newStakingFacet),
                    action: IERC2535DiamondCutInternal.FacetCutAction.REPLACE,
                    selectors: stakingSelectors
                });
                cutCount++;
                console2.log("  Added StakingFacet upgrade with", stakingSelectors.length, "selectors");
            }
        }
        
        // --- Handling RewardsFacet upgrade ---
        if (OLD_REWARDS_FACET_ADDRESS != address(0)) {
            bytes4[] memory rewardsSelectors = loupe.facetFunctionSelectors(OLD_REWARDS_FACET_ADDRESS);
            if (rewardsSelectors.length > 0) {
                cut[cutCount] = IERC2535DiamondCutInternal.FacetCut({
                    target: address(newRewardsFacet),
                    action: IERC2535DiamondCutInternal.FacetCutAction.REPLACE,
                    selectors: rewardsSelectors
                });
                cutCount++;
                console2.log("  Added RewardsFacet upgrade with", rewardsSelectors.length, "selectors");
            }
        }

        // --- Step 4: Execute Diamond Cut (if any changes) ---
        if (cutCount > 0) {
            console2.log("\n4. Executing Diamond Cut with", cutCount, "facet upgrades...");
            
            // Create final cut array with exact length
            IERC2535DiamondCutInternal.FacetCut[] memory finalCut = new IERC2535DiamondCutInternal.FacetCut[](cutCount);
            for (uint256 i = 0; i < cutCount; i++) {
                finalCut[i] = cut[i];
            }
            
            // Execute the diamond cut
            ISolidStateDiamond(payable(DIAMOND_PROXY_ADDRESS)).diamondCut(finalCut, address(0), "");
            console2.log("  Diamond Cut executed successfully.");
            
            // --- Step 5: Verification (Optional but Recommended) ---
            console2.log("\n5. Verifying upgrades...");
            
            // Verify ManagementFacet
            if (OLD_MANAGEMENT_FACET_ADDRESS != address(0)) {
                bytes4[] memory managementSelectors = loupe.facetFunctionSelectors(OLD_MANAGEMENT_FACET_ADDRESS);
                if (managementSelectors.length > 0) {
                    address newAddress = loupe.facetAddress(managementSelectors[0]);
                    console2.log("  ManagementFacet now points to:", newAddress);
                    console2.log("  Expected:", address(newManagementFacet));
                    console2.log("  Verified:", newAddress == address(newManagementFacet));
                }
            }
            
            // Verify AccessControlFacet (new facet)
            address acAddress = loupe.facetAddress(accessControlSelectors[0]);
            console2.log("  AccessControlFacet points to:", acAddress);
            console2.log("  Expected:", address(newAccessControlFacet));
            console2.log("  Verified:", acAddress == address(newAccessControlFacet));
            
            // Add similar verification for other facets if needed
            
        } else {
            console2.log("\n4. No facet upgrades to execute.");
        }
        
        console2.log("\n--- Plume Staking Diamond Upgrade Complete --- ");
        console2.log("\nNote on library updates (PlumeErrors.sol, PlumeEvents.sol, etc.):");
        console2.log("  Libraries are automatically included with facet implementations.");
        console2.log("  When a facet that imports a library is upgraded, it uses the new library code.");
        console2.log("  No separate diamond cut needed for library changes.");

        // --- Step 6: Initialize AccessControl if it's new ---
        console2.log("\n6. Initializing AccessControl facet...");
        AccessControlFacet accessControl = AccessControlFacet(DIAMOND_PROXY_ADDRESS);
        accessControl.initializeAccessControl();
        console2.log("  AccessControl facet initialized");
        
        // --- Step 7: Set up initial roles ---
        console2.log("\n7. Setting up initial roles...");
        // Grant ADMIN_ROLE to the upgrader
        accessControl.grantRole(PlumeRoles.ADMIN_ROLE, UPGRADER_ADDRESS);
        console2.log("  ADMIN_ROLE granted to upgrader");
        
        // Set ADMIN_ROLE as the admin for itself and other roles
        accessControl.setRoleAdmin(PlumeRoles.ADMIN_ROLE, PlumeRoles.ADMIN_ROLE);
        accessControl.setRoleAdmin(PlumeRoles.UPGRADER_ROLE, PlumeRoles.ADMIN_ROLE);
        accessControl.setRoleAdmin(PlumeRoles.VALIDATOR_ROLE, PlumeRoles.ADMIN_ROLE);
        accessControl.setRoleAdmin(PlumeRoles.REWARD_MANAGER_ROLE, PlumeRoles.ADMIN_ROLE);
        console2.log("  Role admin relationships established");
        
        // Grant other roles to the upgrader
        accessControl.grantRole(PlumeRoles.UPGRADER_ROLE, UPGRADER_ADDRESS);
        accessControl.grantRole(PlumeRoles.VALIDATOR_ROLE, UPGRADER_ADDRESS);
        accessControl.grantRole(PlumeRoles.REWARD_MANAGER_ROLE, UPGRADER_ADDRESS);
        console2.log("  Additional roles granted to upgrader");

        vm.stopBroadcast();
    }

    // --- Helper Function for Adding New Selectors ---
    // This function shows how to add new functions to existing facets
    function addNewFunction() internal {
        // 1. Get existing selectors for the facet
        IERC2535DiamondLoupe loupe = IERC2535DiamondLoupe(DIAMOND_PROXY_ADDRESS);
        bytes4[] memory existingSelectors = loupe.facetFunctionSelectors(OLD_MANAGEMENT_FACET_ADDRESS);
        
        // 2. Create new selector array with additional function
        bytes4[] memory newSelectors = new bytes4[](1);
        newSelectors[0] = bytes4(keccak256(bytes("newFunction()"))); // Example new function
        
        // 3. Create diamond cut with ADD action for just the new selectors
        IERC2535DiamondCutInternal.FacetCut[] memory cut = new IERC2535DiamondCutInternal.FacetCut[](1);
        cut[0] = IERC2535DiamondCutInternal.FacetCut({
            target: address(new ManagementFacet()), // Points to new implementation
            action: IERC2535DiamondCutInternal.FacetCutAction.ADD, // ADD for new functions
            selectors: newSelectors // Only the new selectors
        });
        
        // 4. Execute diamond cut
        // ISolidStateDiamond(payable(DIAMOND_PROXY_ADDRESS)).diamondCut(cut, address(0), "");
    }

    // --- Helper Function for Removing Functions ---
    function removeFunction() internal {
        // To remove functions, use FacetCutAction.REMOVE with address(0) as target
        bytes4[] memory selectorsToRemove = new bytes4[](1);
        selectorsToRemove[0] = bytes4(keccak256(bytes("functionToRemove()"))); // Example function to remove
        
        IERC2535DiamondCutInternal.FacetCut[] memory cut = new IERC2535DiamondCutInternal.FacetCut[](1);
        cut[0] = IERC2535DiamondCutInternal.FacetCut({
            target: address(0), // Must be address(0) for removal
            action: IERC2535DiamondCutInternal.FacetCutAction.REMOVE, // REMOVE action
            selectors: selectorsToRemove
        });
        
        // Execute diamond cut
        // ISolidStateDiamond(payable(DIAMOND_PROXY_ADDRESS)).diamondCut(cut, address(0), "");
    }
}
