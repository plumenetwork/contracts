// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script, console2 } from "forge-std/Script.sol";

// Diamond Proxy & Base
import { PlumeStaking } from "../src/PlumeStaking.sol";

import { IERC2535DiamondCutInternal } from "@solidstate/interfaces/IERC2535DiamondCutInternal.sol";
import { IERC2535DiamondLoupe } from "@solidstate/interfaces/IERC2535DiamondLoupe.sol";
import { ISolidStateDiamond } from "@solidstate/proxy/diamond/ISolidStateDiamond.sol";

// Facet and Roles
import { AccessControlFacet } from "../src/facets/AccessControlFacet.sol";

import { IAccessControl } from "../src/interfaces/IAccessControl.sol";
import { PlumeRoles } from "../src/lib/PlumeRoles.sol";

contract UpgradeAccessControlFacet is Script {

    // Configuration
    address private constant ADMIN = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;
    address private constant DIAMOND_PROXY = 0xA20bfe49969D4a0E9abfdb6a46FeD777304ba07f;
    address private constant IMPLEMENTATION = 0x05a6F61295223fBd83aDA18A485292C5D2502A2A;

    function run() external {
        vm.startBroadcast(ADMIN);

        // 1. Verify the existing implementation has code
        console2.log("\nVerifying implementation contract...");
        uint256 codeSize = address(IMPLEMENTATION).code.length;
        console2.log("Implementation code size:", codeSize);
        require(codeSize > 0, "Implementation has no code");

        // 2. Get function selectors from the AccessControlFacet
        bytes4[] memory existingSelectors = new bytes4[](7);
        bytes4[] memory newSelectors = new bytes4[](5);

        // Function selectors (existing)
        existingSelectors[0] = AccessControlFacet.initializeAccessControl.selector;
        existingSelectors[1] = AccessControlFacet.hasRole.selector;
        existingSelectors[2] = AccessControlFacet.getRoleAdmin.selector;
        existingSelectors[3] = AccessControlFacet.grantRole.selector;
        existingSelectors[4] = AccessControlFacet.revokeRole.selector;
        existingSelectors[5] = AccessControlFacet.renounceRole.selector;
        existingSelectors[6] = AccessControlFacet.setRoleAdmin.selector;

        // Role constant getters (new)
        newSelectors[0] = bytes4(keccak256("DEFAULT_ADMIN_ROLE()")); // 0xa217fddf
        newSelectors[1] = bytes4(keccak256("ADMIN_ROLE()")); // 0x75b238fc
        newSelectors[2] = bytes4(keccak256("UPGRADER_ROLE()")); // 0x189ab7a9
        newSelectors[3] = bytes4(keccak256("VALIDATOR_ROLE()")); // 0xb9f6a8ca
        newSelectors[4] = bytes4(keccak256("REWARD_MANAGER_ROLE()")); // 0x8f4c88d9

        // Print all selectors for verification
        console2.log("\nExisting Function Selectors:");
        for (uint256 i = 0; i < existingSelectors.length; i++) {
            console2.logBytes4(existingSelectors[i]);
        }

        console2.log("\nNew Role Constant Getters:");
        for (uint256 i = 0; i < newSelectors.length; i++) {
            console2.logBytes4(newSelectors[i]);
        }

        // 3. Check current facet implementation for each selector
        console2.log("\nCurrent implementations for selectors:");
        IERC2535DiamondLoupe diamond = IERC2535DiamondLoupe(DIAMOND_PROXY);

        console2.log("\nExisting selectors:");
        for (uint256 i = 0; i < existingSelectors.length; i++) {
            address currentImpl = diamond.facetAddress(existingSelectors[i]);
            console2.log("Selector:", uint32(existingSelectors[i]), "Current impl:", currentImpl);
        }

        console2.log("\nNew selectors:");
        for (uint256 i = 0; i < newSelectors.length; i++) {
            address currentImpl = diamond.facetAddress(newSelectors[i]);
            console2.log("Selector:", uint32(newSelectors[i]), "Current impl:", currentImpl);
        }

        // 4. Prepare the diamond cut for new selectors only
        IERC2535DiamondCutInternal.FacetCut[] memory cut = new IERC2535DiamondCutInternal.FacetCut[](1);
        cut[0] = IERC2535DiamondCutInternal.FacetCut({
            target: IMPLEMENTATION,
            action: IERC2535DiamondCutInternal.FacetCutAction.ADD,
            selectors: newSelectors
        });

        // 5. Execute the diamond cut
        console2.log("\nExecuting diamond cut to add role constant getters...");
        console2.log("Target implementation:", IMPLEMENTATION);
        ISolidStateDiamond(payable(DIAMOND_PROXY)).diamondCut(cut, address(0), "");
        console2.log("Diamond cut executed successfully.");

        // 6. Verify the facet was properly added to the diamond
        console2.log("\nVerifying new implementations:");
        for (uint256 i = 0; i < newSelectors.length; i++) {
            address facetAddress = diamond.facetAddress(newSelectors[i]);
            console2.log("Selector:", uint32(newSelectors[i]), "New impl:", facetAddress);
            require(
                facetAddress == IMPLEMENTATION,
                string.concat("Selector ", string(abi.encodePacked(newSelectors[i])), " points to wrong implementation")
            );
        }

        // 7. Try to call a view function to verify the facet is working
        console2.log("\nTesting facet functionality...");
        try IAccessControl(DIAMOND_PROXY).hasRole(PlumeRoles.ADMIN_ROLE, ADMIN) returns (bool hasRole) {
            console2.log("hasRole call successful. Admin has ADMIN_ROLE:", hasRole);
        } catch Error(string memory reason) {
            console2.log("hasRole call failed with reason:", reason);
            revert("Facet functionality test failed");
        } catch {
            console2.log("hasRole call failed with unknown reason");
            revert("Facet functionality test failed");
        }

        // 8. Verify and setup roles if needed
        console2.log("\nVerifying roles...");
        IAccessControl accessControl = IAccessControl(DIAMOND_PROXY);

        // Check if admin has ADMIN_ROLE
        if (!accessControl.hasRole(PlumeRoles.ADMIN_ROLE, ADMIN)) {
            console2.log("Setting up ADMIN_ROLE...");
            accessControl.grantRole(PlumeRoles.ADMIN_ROLE, ADMIN);
        }

        // Verify role hierarchy
        bytes32 adminRoleAdmin = accessControl.getRoleAdmin(PlumeRoles.ADMIN_ROLE);
        if (adminRoleAdmin != PlumeRoles.ADMIN_ROLE) {
            console2.log("Setting up ADMIN_ROLE as its own admin...");
            accessControl.setRoleAdmin(PlumeRoles.ADMIN_ROLE, PlumeRoles.ADMIN_ROLE);
        }

        // Setup other roles if needed
        bytes32[] memory rolesToCheck = new bytes32[](3);
        rolesToCheck[0] = PlumeRoles.UPGRADER_ROLE;
        rolesToCheck[1] = PlumeRoles.VALIDATOR_ROLE;
        rolesToCheck[2] = PlumeRoles.REWARD_MANAGER_ROLE;

        for (uint256 i = 0; i < rolesToCheck.length; i++) {
            bytes32 role = rolesToCheck[i];

            // Check if role admin is properly set
            if (accessControl.getRoleAdmin(role) != PlumeRoles.ADMIN_ROLE) {
                console2.log("Setting ADMIN_ROLE as admin for role:", uint256(role));
                accessControl.setRoleAdmin(role, PlumeRoles.ADMIN_ROLE);
            }

            // Grant role to admin if not already granted
            if (!accessControl.hasRole(role, ADMIN)) {
                console2.log("Granting role to admin:", uint256(role));
                accessControl.grantRole(role, ADMIN);
            }
        }

        // 9. Log upgrade summary
        console2.log("\nUpgrade Summary:");
        console2.log("--------------------");
        console2.log("Diamond Proxy:", DIAMOND_PROXY);
        console2.log("Implementation:", IMPLEMENTATION);
        console2.log("Number of new selectors added:", newSelectors.length);

        // Log role verification
        console2.log("\nRole Verification:");
        console2.log("--------------------");
        console2.log("ADMIN_ROLE granted to admin:", accessControl.hasRole(PlumeRoles.ADMIN_ROLE, ADMIN));
        console2.log("UPGRADER_ROLE granted to admin:", accessControl.hasRole(PlumeRoles.UPGRADER_ROLE, ADMIN));
        console2.log("VALIDATOR_ROLE granted to admin:", accessControl.hasRole(PlumeRoles.VALIDATOR_ROLE, ADMIN));
        console2.log(
            "REWARD_MANAGER_ROLE granted to admin:", accessControl.hasRole(PlumeRoles.REWARD_MANAGER_ROLE, ADMIN)
        );

        vm.stopBroadcast();
    }

}
