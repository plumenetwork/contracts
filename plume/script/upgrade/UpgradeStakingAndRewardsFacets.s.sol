// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script, console2 } from "forge-std/Script.sol";

// --- SolidState Diamond Interfaces ---
import { IERC2535DiamondCutInternal } from "@solidstate/interfaces/IERC2535DiamondCutInternal.sol";
import { IERC2535DiamondLoupe } from "@solidstate/interfaces/IERC2535DiamondLoupe.sol";
import { IERC2535DiamondLoupeInternal } from "@solidstate/interfaces/IERC2535DiamondLoupeInternal.sol";
import { ISolidStateDiamond } from "@solidstate/proxy/diamond/ISolidStateDiamond.sol";

// --- Plume Facets ---
import { AccessControlFacet } from "../../src/facets/AccessControlFacet.sol";
import { ManagementFacet } from "../../src/facets/ManagementFacet.sol";
import { RewardsFacet } from "../../src/facets/RewardsFacet.sol";
import { StakingFacet } from "../../src/facets/StakingFacet.sol";
import { ValidatorFacet } from "../../src/facets/ValidatorFacet.sol";

// Import PlumeRoles for AccessControl selectors
import { PlumeRoles } from "../../src/lib/PlumeRoles.sol";

/**
 * @title UpgradeStakingAndRewardsFacets
 * @notice Script to upgrade StakingFacet and RewardsFacet and ensure other core facets are up-to-date.
 */
contract UpgradeStakingAndRewardsFacets is Script {

    // --- Helper Functions for Selector Management ---

    /**
     * @dev Finds selectors present in listA but not in listB (A - B).
     */
    function _difference(bytes4[] memory listA, bytes4[] memory listB) internal pure returns (bytes4[] memory diff) {
        uint256 count = 0;
        // Allocate temporary array with max possible size
        bytes4[] memory temp = new bytes4[](listA.length);

        for (uint256 i = 0; i < listA.length; i++) {
            bool foundInB = false;
            for (uint256 j = 0; j < listB.length; j++) {
                if (listA[i] == listB[j]) {
                    foundInB = true;
                    break;
                }
            }
            if (!foundInB) {
                temp[count] = listA[i];
                count++;
            }
        }

        // Resize the array to the actual number of different selectors
        diff = new bytes4[](count);
        for (uint256 i = 0; i < count; i++) {
            diff[i] = temp[i];
        }
    }

    /**
     * @dev Finds selectors present in both listA and listB (Intersection).
     */
    function _intersection(
        bytes4[] memory listA,
        bytes4[] memory listB
    ) internal pure returns (bytes4[] memory intersection) {
        uint256 count = 0;
        // Allocate temporary array with max possible size (smaller of the two)
        uint256 maxIntersectionSize = listA.length < listB.length ? listA.length : listB.length;
        bytes4[] memory temp = new bytes4[](maxIntersectionSize);

        for (uint256 i = 0; i < listA.length; i++) {
            bool foundInB = false;
            for (uint256 j = 0; j < listB.length; j++) {
                if (listA[i] == listB[j]) {
                    foundInB = true;
                    break;
                }
            }
            // Only add if found in B AND not already added to temp
            if (foundInB) {
                bool alreadyAdded = false;
                for (uint256 k = 0; k < count; k++) {
                    if (temp[k] == listA[i]) {
                        alreadyAdded = true;
                        break;
                    }
                }
                if (!alreadyAdded) {
                    temp[count] = listA[i];
                    count++;
                }
            }
        }

        // Resize the array to the actual number of common selectors
        intersection = new bytes4[](count);
        for (uint256 i = 0; i < count; i++) {
            intersection[i] = temp[i];
        }
    }

    // --- Configuration ---
    // !!! IMPORTANT: Set the correct Diamond Proxy address before running !!!
    // address private constant DIAMOND_PROXY_ADDRESS = 0xA20bfe49969D4a0E9abfdb6a46FeD777304ba07f; // Example address
    address private constant DIAMOND_PROXY_ADDRESS = 0xA20bfe49969D4a0E9abfdb6a46FeD777304ba07f; // Replace with actual
        // proxy address

    // Address with upgrade permissions (Owner or UPGRADER_ROLE)
    address private constant UPGRADER_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5; // Replace if needed

    // --- Helper Functions to Get Selectors for NEW Facets ---

    function getManagementSelectors() internal pure returns (bytes4[] memory) {
        // From p/src/facets/ManagementFacet.sol
        bytes4[] memory selectors = new bytes4[](8); // Updated count based on current facet
        selectors[0] = bytes4(keccak256(bytes("setMinStakeAmount(uint256)")));
        selectors[1] = bytes4(keccak256(bytes("setCooldownInterval(uint256)")));
        selectors[2] = bytes4(keccak256(bytes("adminWithdraw(address,uint256,address)")));
        selectors[3] = bytes4(keccak256(bytes("updateTotalAmounts(uint256,uint256)")));
        selectors[4] = bytes4(keccak256(bytes("getMinStakeAmount()")));
        selectors[5] = bytes4(keccak256(bytes("getCooldownInterval()")));
        selectors[6] = bytes4(keccak256(bytes("setMaxSlashVoteDuration(uint256)")));
        selectors[7] = bytes4(keccak256(bytes("adminCorrectUserStakeInfo(address)")));
        return selectors;
    }

    function getAccessControlSelectors() internal pure returns (bytes4[] memory) {
        // From p/src/facets/AccessControlFacet.sol
        bytes4[] memory selectors = new bytes4[](7); // Updated count based on current facet
        selectors[0] = bytes4(keccak256(bytes("initializeAccessControl()")));
        selectors[1] = bytes4(keccak256(bytes("hasRole(bytes32,address)")));
        selectors[2] = bytes4(keccak256(bytes("getRoleAdmin(bytes32)")));
        selectors[3] = bytes4(keccak256(bytes("grantRole(bytes32,address)")));
        selectors[4] = bytes4(keccak256(bytes("revokeRole(bytes32,address)")));
        selectors[5] = bytes4(keccak256(bytes("renounceRole(bytes32,address)")));
        selectors[6] = bytes4(keccak256(bytes("setRoleAdmin(bytes32,bytes32)")));
        // Removed role constants as they are not external functions
        return selectors;
    }

    function getValidatorSelectors() internal pure returns (bytes4[] memory) {
        // From p/src/facets/ValidatorFacet.sol
        bytes4[] memory selectors = new bytes4[](12);
        selectors[0] =
            bytes4(keccak256(bytes("addValidator(uint16,uint256,address,address,string,string,address,uint256)")));
        selectors[1] = bytes4(keccak256(bytes("setValidatorCapacity(uint16,uint256)")));
        selectors[2] = bytes4(keccak256(bytes("updateValidator(uint16,uint8,bytes)")));
        selectors[3] = bytes4(keccak256(bytes("claimValidatorCommission(uint16,address)")));
        selectors[4] = bytes4(keccak256(bytes("getValidatorInfo(uint16)")));
        selectors[5] = bytes4(keccak256(bytes("getValidatorStats(uint16)")));
        selectors[6] = bytes4(keccak256(bytes("getUserValidators(address)")));
        selectors[7] = bytes4(keccak256(bytes("getAccruedCommission(uint16,address)")));
        selectors[8] = bytes4(keccak256(bytes("getValidatorsList()")));
        selectors[9] = bytes4(keccak256(bytes("getActiveValidatorCount()")));
        selectors[10] = bytes4(keccak256(bytes("voteToSlashValidator(uint16,uint256)")));
        selectors[11] = bytes4(keccak256(bytes("slashValidator(uint16)")));
        return selectors;
    }

    function getStakingSelectors() internal pure returns (bytes4[] memory) {
        // From p/src/facets/StakingFacet.sol
        bytes4[] memory selectors = new bytes4[](16); // Updated count based on current facet
        selectors[0] = bytes4(keccak256(bytes("stake(uint16)")));
        selectors[1] = bytes4(keccak256(bytes("restake(uint16,uint256)")));
        selectors[2] = bytes4(keccak256(bytes("unstake(uint16)")));
        selectors[3] = bytes4(keccak256(bytes("unstake(uint16,uint256)")));
        selectors[4] = bytes4(keccak256(bytes("withdraw()")));
        selectors[5] = bytes4(keccak256(bytes("stakeOnBehalf(uint16,address)")));
        selectors[6] = bytes4(keccak256(bytes("stakeInfo(address)")));
        selectors[7] = bytes4(keccak256(bytes("amountStaked()")));
        selectors[8] = bytes4(keccak256(bytes("amountCooling()")));
        selectors[9] = bytes4(keccak256(bytes("amountWithdrawable()")));
        selectors[10] = bytes4(keccak256(bytes("cooldownEndDate()")));
        selectors[11] = bytes4(keccak256(bytes("getUserValidatorStake(address,uint16)")));
        selectors[12] = bytes4(keccak256(bytes("restakeRewards(uint16)")));
        selectors[13] = bytes4(keccak256(bytes("totalAmountStaked()")));
        selectors[14] = bytes4(keccak256(bytes("totalAmountCooling()")));
        selectors[15] = bytes4(keccak256(bytes("totalAmountWithdrawable()")));
        return selectors;
    }

    function getRewardsSelectors() internal pure returns (bytes4[] memory) {
        // From p/src/facets/RewardsFacet.sol
        bytes4[] memory selectors = new bytes4[](21); // Updated count based on current facet
        selectors[0] = bytes4(keccak256(bytes("addRewardToken(address)")));
        selectors[1] = bytes4(keccak256(bytes("removeRewardToken(address)")));
        selectors[2] = bytes4(keccak256(bytes("setRewardRates(address[],uint256[])")));
        selectors[3] = bytes4(keccak256(bytes("setMaxRewardRate(address,uint256)")));
        selectors[4] = bytes4(keccak256(bytes("addRewards(address,uint256)")));
        selectors[5] = bytes4(keccak256(bytes("claim(address)")));
        selectors[6] = bytes4(keccak256(bytes("claim(address,uint16)")));
        selectors[7] = bytes4(keccak256(bytes("claimAll()")));
        selectors[8] = bytes4(keccak256(bytes("earned(address,address)")));
        selectors[9] = bytes4(keccak256(bytes("getClaimableReward(address,address)")));
        selectors[10] = bytes4(keccak256(bytes("getRewardTokens()")));
        selectors[11] = bytes4(keccak256(bytes("getMaxRewardRate(address)")));
        selectors[12] = bytes4(keccak256(bytes("tokenRewardInfo(address)")));
        selectors[13] = bytes4(keccak256(bytes("getRewardRateCheckpointCount(address)")));
        selectors[14] = bytes4(keccak256(bytes("getValidatorRewardRateCheckpointCount(uint16,address)")));
        selectors[15] = bytes4(keccak256(bytes("getUserLastCheckpointIndex(address,uint16,address)")));
        selectors[16] = bytes4(keccak256(bytes("getRewardRateCheckpoint(address,uint256)")));
        selectors[17] = bytes4(keccak256(bytes("getValidatorRewardRateCheckpoint(uint16,address,uint256)")));
        selectors[18] = bytes4(keccak256(bytes("setTreasury(address)")));
        selectors[19] = bytes4(keccak256(bytes("getTreasury()")));
        selectors[20] = bytes4(keccak256(bytes("getPendingRewardForValidator(address,uint16,address)"))); // Added this
            // function
        return selectors;
    }

    function run() external {
        // Ensure proxy address is set
        if (DIAMOND_PROXY_ADDRESS == address(0)) {
            console2.log("ERROR: DIAMOND_PROXY_ADDRESS is not set in the script!");
            return;
        }

        vm.startBroadcast(UPGRADER_ADDRESS);

        console2.log("--- Starting Plume Staking Diamond Upgrade (Staking & Rewards Facets) --- ");
        console2.log("Target Proxy: %s", DIAMOND_PROXY_ADDRESS);
        console2.log("Upgrader Address: %s", UPGRADER_ADDRESS);

        // --- Step 1: Deploy New Facet Implementations ---
        console2.log("\n1. Deploying new facet implementations...");

        // Deploy new versions of ALL core facets for consistency
        ManagementFacet newManagementFacet = new ManagementFacet();
        AccessControlFacet newAccessControlFacet = new AccessControlFacet();
        ValidatorFacet newValidatorFacet = new ValidatorFacet();
        StakingFacet newStakingFacet = new StakingFacet();
        RewardsFacet newRewardsFacet = new RewardsFacet();

        console2.log("  New ManagementFacet deployed at: %s", address(newManagementFacet));
        console2.log("  New AccessControlFacet deployed at: %s", address(newAccessControlFacet));
        console2.log("  New ValidatorFacet deployed at: %s", address(newValidatorFacet));
        console2.log("  New StakingFacet deployed at: %s", address(newStakingFacet));
        console2.log("  New RewardsFacet deployed at: %s", address(newRewardsFacet));

        // --- Step 2: Prepare Diamond Cut ---
        console2.log("\n2. Preparing Diamond Cut data...");

        IERC2535DiamondLoupe loupe = IERC2535DiamondLoupe(DIAMOND_PROXY_ADDRESS);

        // Array to hold all cut operations (ADD, REMOVE, REPLACE)
        IERC2535DiamondCutInternal.FacetCut[] memory combinedCut = new IERC2535DiamondCutInternal.FacetCut[](15); // Max
            // 3 ops per 5 facets
        uint256 cutIndex = 0;

        // Define facets to upgrade
        address[5] memory newFacetAddresses = [
            address(newManagementFacet),
            address(newAccessControlFacet),
            address(newValidatorFacet),
            address(newStakingFacet),
            address(newRewardsFacet)
        ];

        string[5] memory facetNames = ["Management", "AccessControl", "Validator", "Staking", "Rewards"];

        bytes4[5] memory facetFirstSelectors = [
            newManagementFacet.getMinStakeAmount.selector,
            newAccessControlFacet.hasRole.selector,
            newValidatorFacet.getValidatorInfo.selector,
            newStakingFacet.stakeInfo.selector,
            newRewardsFacet.getRewardTokens.selector
        ];

        // Loop through each facet, calculate differences, and prepare cuts
        for (uint256 i = 0; i < newFacetAddresses.length; i++) {
            console2.log("  Calculating cut for %s Facet...", facetNames[i]);

            address newFacetAddr = newFacetAddresses[i];
            bytes4 firstSelector = facetFirstSelectors[i]; // A known selector for this facet
            address oldFacetAddr;

            // Get old facet address using a known selector (handle potential initial deployment where facet might not
            // exist)
            try loupe.facetAddress(firstSelector) returns (address currentAddr) {
                oldFacetAddr = currentAddr;
                console2.log("    Found old %s address: %s", facetNames[i], oldFacetAddr);
            } catch {
                oldFacetAddr = address(0);
                console2.log("    Old %s address not found via Loupe (assuming initial add).", facetNames[i]);
            }

            // Get selectors for the new facet version
            bytes4[] memory newSelectors;
            if (i == 0) {
                newSelectors = getManagementSelectors();
            } else if (i == 1) {
                newSelectors = getAccessControlSelectors();
            } else if (i == 2) {
                newSelectors = getValidatorSelectors();
            } else if (i == 3) {
                newSelectors = getStakingSelectors();
            } else if (i == 4) {
                newSelectors = getRewardsSelectors();
            }

            // Get selectors currently registered for the old facet address
            bytes4[] memory oldSelectors;
            if (oldFacetAddr != address(0) && oldFacetAddr != address(this)) {
                // Avoid querying zero address or the script itself
                try loupe.facetFunctionSelectors(oldFacetAddr) returns (bytes4[] memory currentSelectors) {
                    oldSelectors = currentSelectors;
                    console2.log("    Found %d selectors for old %s address.", oldSelectors.length, facetNames[i]);
                } catch Error(string memory reason) {
                    console2.log("    WARN: Could not get selectors for old %s: %s", facetNames[i], reason);
                    oldSelectors = new bytes4[](0);
                } catch {
                    console2.log("    WARN: Could not get selectors for old %s (Unknown error).", facetNames[i]);
                    oldSelectors = new bytes4[](0);
                }
            } else {
                oldSelectors = new bytes4[](0); // No old selectors if address was 0
            }

            // Calculate differences
            bytes4[] memory selectorsToRemove = _difference(oldSelectors, newSelectors);
            bytes4[] memory selectorsToAdd = _difference(newSelectors, oldSelectors);
            bytes4[] memory selectorsToReplace = _intersection(oldSelectors, newSelectors);

            console2.log(
                "    Calculated: %d REMOVE, %d ADD, %d REPLACE",
                selectorsToRemove.length,
                selectorsToAdd.length,
                selectorsToReplace.length
            );

            // Prepare REMOVE cut (if necessary)
            if (selectorsToRemove.length > 0) {
                require(cutIndex < combinedCut.length, "Cut array overflow");
                combinedCut[cutIndex++] = IERC2535DiamondCutInternal.FacetCut({
                    target: address(0), // Target ignored for REMOVE
                    action: IERC2535DiamondCutInternal.FacetCutAction.REMOVE,
                    selectors: selectorsToRemove
                });
                console2.log("      Added REMOVE cut.");
            }

            // Prepare ADD cut (if necessary)
            if (selectorsToAdd.length > 0) {
                require(cutIndex < combinedCut.length, "Cut array overflow");
                combinedCut[cutIndex++] = IERC2535DiamondCutInternal.FacetCut({
                    target: newFacetAddr,
                    action: IERC2535DiamondCutInternal.FacetCutAction.ADD,
                    selectors: selectorsToAdd
                });
                console2.log("      Added ADD cut.");
            }

            // Prepare REPLACE cut (if necessary)
            if (selectorsToReplace.length > 0) {
                require(cutIndex < combinedCut.length, "Cut array overflow");
                combinedCut[cutIndex++] = IERC2535DiamondCutInternal.FacetCut({
                    target: newFacetAddr,
                    action: IERC2535DiamondCutInternal.FacetCutAction.REPLACE,
                    selectors: selectorsToReplace
                });
                console2.log("      Added REPLACE cut.");
            }
        }

        // Resize the combinedCut array to the actual number of operations
        IERC2535DiamondCutInternal.FacetCut[] memory finalCut = new IERC2535DiamondCutInternal.FacetCut[](cutIndex);
        for (uint256 i = 0; i < cutIndex; i++) {
            finalCut[i] = combinedCut[i];
        }

        // --- Step 3: Execute Diamond Cut ---
        if (finalCut.length > 0) {
            console2.log("\n3. Executing Diamond Cut with %d operations...", finalCut.length);
            ISolidStateDiamond(payable(DIAMOND_PROXY_ADDRESS)).diamondCut(finalCut, address(0), "");
            console2.log("  Diamond Cut executed successfully.");
        } else {
            console2.log("\n3. No Diamond Cut operations required.");
        }

        // --- Step 4: Verification (Optional but Recommended) ---
        console2.log("\n4. Verifying facet addresses and selectors...");
        IERC2535DiamondLoupe finalLoupe = IERC2535DiamondLoupe(DIAMOND_PROXY_ADDRESS);
        bool verificationPassed = true;

        for (uint256 i = 0; i < newFacetAddresses.length; i++) {
            bytes4[] memory expectedSelectors;
            if (i == 0) {
                expectedSelectors = getManagementSelectors();
            } else if (i == 1) {
                expectedSelectors = getAccessControlSelectors();
            } else if (i == 2) {
                expectedSelectors = getValidatorSelectors();
            } else if (i == 3) {
                expectedSelectors = getStakingSelectors();
            } else if (i == 4) {
                expectedSelectors = getRewardsSelectors();
            }

            console2.log("  Verifying %s Facet (%s)...", facetNames[i], newFacetAddresses[i]);
            for (uint256 j = 0; j < expectedSelectors.length; j++) {
                bytes4 selector = expectedSelectors[j];
                address currentAddr = finalLoupe.facetAddress(selector);
                if (currentAddr != newFacetAddresses[i]) {
                    console2.log(
                        "    ERROR: Selector %s points to %s, expected %s",
                        vm.toString(selector),
                        currentAddr,
                        newFacetAddresses[i]
                    );
                    verificationPassed = false;
                }
            }
            if (expectedSelectors.length == 0) {
                console2.log("    Skipping selector verification (no expected selectors).");
            }
        }

        if (verificationPassed) {
            console2.log("  Verification successful: All expected selectors point to the correct new facet addresses.");
        } else {
            console2.log("  VERIFICATION FAILED: Some selectors do not point to the expected new facet addresses!");
        }

        console2.log("\n--- Plume Staking Diamond Upgrade Complete --- ");

        vm.stopBroadcast();
    }

}
