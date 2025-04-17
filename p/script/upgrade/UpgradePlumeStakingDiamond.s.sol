// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script, console2 } from "forge-std/Script.sol";

// --- SolidState Diamond Interfaces ---
import { IERC2535DiamondCutInternal } from "solidstate-solidity/interfaces/IERC2535DiamondCutInternal.sol";
import { IERC2535DiamondLoupe } from "solidstate-solidity/interfaces/IERC2535DiamondLoupe.sol";

import { IERC2535DiamondLoupeInternal } from "solidstate-solidity/interfaces/IERC2535DiamondLoupeInternal.sol";
import { ISolidStateDiamond } from "solidstate-solidity/proxy/diamond/SolidStateDiamond.sol";

// --- Plume Facets ---
import { AccessControlFacet } from "../../src/facets/AccessControlFacet.sol";
import { ManagementFacet } from "../../src/facets/ManagementFacet.sol";
import { RewardsFacet } from "../../src/facets/RewardsFacet.sol";
import { StakingFacet } from "../../src/facets/StakingFacet.sol";
import { ValidatorFacet } from "../../src/facets/ValidatorFacet.sol";

// Import PlumeRoles for AccessControl selectors
import { PlumeRoles } from "../../src/lib/PlumeRoles.sol";

contract UpgradePlumeStakingDiamond is Script {

    // --- Helper Functions for Selector Management ---

    /**
     * @dev Checks if a selector exists in an array.
     */
    function _contains(bytes4[] memory array, bytes4 selector) internal pure returns (bool) {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == selector) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev Combines multiple selector arrays into one, removing duplicates.
     */
    function _combineSelectors(
        bytes4[][] memory arrays
    ) internal pure returns (bytes4[] memory combined) {
        uint256 totalLength = 0;
        for (uint256 i = 0; i < arrays.length; i++) {
            totalLength += arrays[i].length;
        }

        bytes4[] memory temp = new bytes4[](totalLength);
        uint256 uniqueCount = 0;

        for (uint256 i = 0; i < arrays.length; i++) {
            for (uint256 j = 0; j < arrays[i].length; j++) {
                bytes4 currentSelector = arrays[i][j];
                bool found = false;
                for (uint256 k = 0; k < uniqueCount; k++) {
                    if (temp[k] == currentSelector) {
                        found = true;
                        break;
                    }
                }

                if (!found) {
                    temp[uniqueCount] = currentSelector;
                    uniqueCount++;
                }
            }
        }

        combined = new bytes4[](uniqueCount);
        for (uint256 i = 0; i < uniqueCount; i++) {
            combined[i] = temp[i];
        }
    }

    /**
     * @dev Filters selectorsToAdd, removing any present in selectorsToRemove.
     */
    function _filterSelectors(
        bytes4[] memory selectorsToAdd,
        bytes4[] memory selectorsToRemove
    ) internal pure returns (bytes4[] memory filtered) {
        uint256 count = 0;
        bytes4[] memory temp = new bytes4[](selectorsToAdd.length);

        for (uint256 i = 0; i < selectorsToAdd.length; i++) {
            if (!_contains(selectorsToRemove, selectorsToAdd[i])) {
                temp[count] = selectorsToAdd[i];
                count++;
            }
        }

        filtered = new bytes4[](count);
        for (uint256 i = 0; i < count; i++) {
            filtered[i] = temp[i];
        }
    }

    /**
     * @dev Finds selectors present in listA but not in listB (A - B).
     */
    function _difference(bytes4[] memory listA, bytes4[] memory listB) internal pure returns (bytes4[] memory diff) {
        uint256 count = 0;
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
        bytes4[] memory temp = new bytes4[](listA.length < listB.length ? listA.length : listB.length);

        for (uint256 i = 0; i < listA.length; i++) {
            bool foundInB = false;
            for (uint256 j = 0; j < listB.length; j++) {
                if (listA[i] == listB[j]) {
                    foundInB = true;
                    break;
                }
            }
            if (foundInB) {
                temp[count] = listA[i];
                count++;
            }
        }

        intersection = new bytes4[](count);
        for (uint256 i = 0; i < count; i++) {
            intersection[i] = temp[i];
        }
    }

    // --- Configuration ---
    // Existing Deployment Addresses (FROM USER LOG)
    address private constant DIAMOND_PROXY_ADDRESS = 0xA20bfe49969D4a0E9abfdb6a46FeD777304ba07f;

    // Current facet addresses
    address private constant OLD_MANAGEMENT_FACET_ADDRESS = 0xC6De90d79e6a9b1e35DeDB01BD16454413DAcD98;
    address private constant OLD_ACCESSCONTROL_FACET_ADDRESS = 0x0000000000000000000000000000000000000000;
    address private constant OLD_VALIDATOR_FACET_ADDRESS = 0xB779325c19Be479FF45438E04A584B32E9A02E1F;
    address private constant OLD_STAKING_FACET_ADDRESS = 0x65245c7F5310e485C0B9EFAA46E558C5a96A00F1;
    address private constant OLD_REWARDS_FACET_ADDRESS = 0x0630e14dABDb05Ca6d9A1Be40c6F996855e9c2cb;

    // Address with upgrade permissions (Owner or UPGRADER_ROLE)
    address private constant UPGRADER_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;

    // --- Helper Functions ---
    function getAllSelectors(
        address facet
    ) internal view returns (bytes4[] memory) {
        // Get all function selectors from the facet
        bytes4[] memory selectors;
        try ISolidStateDiamond(payable(facet)).supportsInterface("") returns (bool) {
            // If this fails, it means the contract doesn't implement ERC165
            selectors = new bytes4[](1);
        } catch {
            // Get selectors through other means (manual definition)
            if (facet == address(OLD_MANAGEMENT_FACET_ADDRESS)) {
                selectors = getManagementSelectors();
            } else if (facet == address(OLD_ACCESSCONTROL_FACET_ADDRESS)) {
                selectors = getAccessControlSelectors();
            } else if (facet == address(OLD_VALIDATOR_FACET_ADDRESS)) {
                selectors = getValidatorSelectors();
            } else if (facet == address(OLD_STAKING_FACET_ADDRESS)) {
                selectors = getStakingSelectors();
            } else if (facet == address(OLD_REWARDS_FACET_ADDRESS)) {
                selectors = getRewardsSelectors();
            }
        }
        return selectors;
    }

    function getManagementSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = bytes4(keccak256(bytes("setMinStakeAmount(uint256)")));
        selectors[1] = bytes4(keccak256(bytes("setCooldownInterval(uint256)")));
        selectors[2] = bytes4(keccak256(bytes("adminWithdraw(address,uint256,address)")));
        selectors[3] = bytes4(keccak256(bytes("updateTotalAmounts(uint256,uint256)")));
        selectors[4] = bytes4(keccak256(bytes("getMinStakeAmount()")));
        selectors[5] = bytes4(keccak256(bytes("getCooldownInterval()")));
        selectors[6] = bytes4(keccak256(bytes("setMaxSlashVoteDuration(uint256)")));
        selectors[7] = bytes4(keccak256(bytes("setMaxValidatorPercentage(uint256)")));
        return selectors;
    }

    function getAccessControlSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = bytes4(keccak256(bytes("initializeAccessControl()")));
        selectors[1] = bytes4(keccak256(bytes("hasRole(bytes32,address)")));
        selectors[2] = bytes4(keccak256(bytes("getRoleAdmin(bytes32)")));
        selectors[3] = bytes4(keccak256(bytes("grantRole(bytes32,address)")));
        selectors[4] = bytes4(keccak256(bytes("revokeRole(bytes32,address)")));
        selectors[5] = bytes4(keccak256(bytes("renounceRole(bytes32,address)")));
        selectors[6] = bytes4(keccak256(bytes("setRoleAdmin(bytes32,bytes32)")));
        selectors[7] = bytes4(keccak256(bytes("ADMIN_ROLE()")));
        selectors[8] = bytes4(keccak256(bytes("UPGRADER_ROLE()")));
        selectors[9] = bytes4(keccak256(bytes("VALIDATOR_ROLE()")));
        selectors[10] = bytes4(keccak256(bytes("REWARD_MANAGER_ROLE()")));
        return selectors;
    }

    function getValidatorSelectors() internal pure returns (bytes4[] memory) {
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
        bytes4[] memory selectors = new bytes4[](17);
        selectors[0] = bytes4(keccak256(bytes("stake(uint16)")));
        selectors[1] = bytes4(keccak256(bytes("restake(uint16,uint256)")));
        selectors[2] = bytes4(keccak256(bytes("unstake(uint16)")));
        selectors[3] = bytes4(keccak256(bytes("unstake(uint16,uint256)")));
        selectors[4] = bytes4(keccak256(bytes("withdraw()")));
        selectors[5] = bytes4(keccak256(bytes("stakeOnBehalf(uint16,address)")));
        selectors[6] = bytes4(keccak256(bytes("restakeRewards(uint16)")));
        selectors[7] = bytes4(keccak256(bytes("amountStaked()")));
        selectors[8] = bytes4(keccak256(bytes("amountCooling()")));
        selectors[9] = bytes4(keccak256(bytes("amountWithdrawable()")));
        selectors[10] = bytes4(keccak256(bytes("cooldownEndDate()")));
        selectors[11] = bytes4(keccak256(bytes("stakeInfo(address)")));
        selectors[12] = bytes4(keccak256(bytes("totalAmountStaked()")));
        selectors[13] = bytes4(keccak256(bytes("totalAmountCooling()")));
        selectors[14] = bytes4(keccak256(bytes("totalAmountWithdrawable()")));
        selectors[15] = bytes4(keccak256(bytes("totalAmountClaimable(address)")));
        selectors[16] = bytes4(keccak256(bytes("getUserValidatorStake(address,uint16)")));
        return selectors;
    }

    function getRewardsSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](20);
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
        return selectors;
    }

    function findNewSelectors(
        bytes4[] memory existingSelectors,
        bytes4[] memory allSelectors
    ) internal pure returns (bytes4[] memory) {
        // Count new selectors first
        uint256 newCount = 0;
        for (uint256 i = 0; i < allSelectors.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < existingSelectors.length; j++) {
                if (allSelectors[i] == existingSelectors[j]) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                newCount++;
            }
        }

        // Create array for new selectors
        bytes4[] memory newSelectors = new bytes4[](newCount);
        uint256 index = 0;
        for (uint256 i = 0; i < allSelectors.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < existingSelectors.length; j++) {
                if (allSelectors[i] == existingSelectors[j]) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                newSelectors[index] = allSelectors[i];
                index++;
            }
        }

        return newSelectors;
    }

    function run() external {
        vm.startBroadcast(UPGRADER_ADDRESS);

        console2.log("--- Starting Plume Staking Diamond Upgrade --- ");
        console2.log("Target Proxy: %s", DIAMOND_PROXY_ADDRESS);
        console2.log("Upgrader Address: %s", UPGRADER_ADDRESS);

        // --- Step 1: Deploy New Facet Implementations ---
        console2.log("\n1. Deploying new facet implementations...");

        // Deploy new versions of all facets
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

        // --- Step 2: Define Selectors for Precise Cut ---
        console2.log("\n2. Defining selectors for REMOVE and ADD cuts based on query results...");

        // Selectors currently pointing to OLD facets that need REMOVAL
        bytes4[] memory selectorsToRemove = new bytes4[](8);
        selectorsToRemove[0] = 0x611a0996; // Old Management
        selectorsToRemove[1] = 0x543eada9; // Old Validator
        selectorsToRemove[2] = 0xc8cf648f; // Old Staking
        selectorsToRemove[3] = 0xe5f9d436; // Old Rewards
        selectorsToRemove[4] = 0x630e9560; // Old Rewards
        selectorsToRemove[5] = 0x4b1328cc; // Old Rewards
        selectorsToRemove[6] = 0xcf07e31d; // Old Rewards
        selectorsToRemove[7] = 0xc1a6956d; // Old Rewards
        console2.log("  Identified %d selectors to REMOVE.", selectorsToRemove.length);

        // --- Step 3: Prepare Diamond Cut Data (REMOVE phase) ---
        console2.log("\n3. Preparing REMOVE Diamond Cut data...");

        IERC2535DiamondCutInternal.FacetCut[] memory removeCut = new IERC2535DiamondCutInternal.FacetCut[](1);
        removeCut[0] = IERC2535DiamondCutInternal.FacetCut({
            target: address(0), // Target address is ignored for REMOVE
            action: IERC2535DiamondCutInternal.FacetCutAction.REMOVE,
            selectors: selectorsToRemove
        });

        // --- Step 4: Execute REMOVE Diamond Cut ---
        console2.log("\n4. Executing REMOVE Diamond Cut...");
        ISolidStateDiamond(payable(DIAMOND_PROXY_ADDRESS)).diamondCut(removeCut, address(0), "");
        console2.log("  REMOVE Diamond Cut executed successfully.");

        // --- Step 5: Prepare Diamond Cut Data (ADD phase) ---
        console2.log("\n5. Preparing ADD Diamond Cut data...");

        address[5] memory newAddresses = [
            address(newManagementFacet),
            address(newAccessControlFacet),
            address(newValidatorFacet),
            address(newStakingFacet),
            address(newRewardsFacet)
        ];

        string[5] memory facetNames =
            ["ManagementFacet", "AccessControlFacet", "ValidatorFacet", "StakingFacet", "RewardsFacet"];

        // Prepare ADD cut for ALL expected selectors pointing to NEW facets
        IERC2535DiamondCutInternal.FacetCut[] memory addCut =
            new IERC2535DiamondCutInternal.FacetCut[](newAddresses.length);
        uint256 cutCount = 0; // Renamed to avoid conflict

        for (uint256 i = 0; i < newAddresses.length; i++) {
            console2.log("--- Processing Facet for ADD: %s ---", facetNames[i]);
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

            if (newSelectors.length > 0) {
                console2.log("  Preparing ADD cut for %s with %d selectors", facetNames[i], newSelectors.length);
                addCut[cutCount] = IERC2535DiamondCutInternal.FacetCut({
                    target: newAddresses[i],
                    action: IERC2535DiamondCutInternal.FacetCutAction.ADD,
                    selectors: newSelectors
                });
                cutCount++; // Increment addCut index
            } else {
                console2.log("  Skipping %s - New facet has no selectors defined.", facetNames[i]);
            }
        }

        // Resize addCut array if any facets were skipped (unlikely here)
        if (cutCount < addCut.length) {
            IERC2535DiamondCutInternal.FacetCut[] memory finalAddCut =
                new IERC2535DiamondCutInternal.FacetCut[](cutCount);
            for (uint256 i = 0; i < cutCount; i++) {
                finalAddCut[i] = addCut[i];
            }
            addCut = finalAddCut;
        }

        // --- Step 6: Execute ADD Diamond Cut ---
        if (addCut.length > 0) {
            console2.log("\n6. Executing ADD Diamond Cut...");
            ISolidStateDiamond(payable(DIAMOND_PROXY_ADDRESS)).diamondCut(addCut, address(0), "");
            console2.log("  ADD Diamond Cut executed successfully.");

            // --- Step 7: Verification --- (Get Loupe *after* cuts)
            console2.log("\n7. Verifying upgrades...");
            IERC2535DiamondLoupe loupe = IERC2535DiamondLoupe(DIAMOND_PROXY_ADDRESS);

            // Verify each facet points to the new address
            for (uint256 i = 0; i < newAddresses.length; i++) {
                bytes4[] memory allSelectorsForNewFacet;
                if (i == 0) {
                    allSelectorsForNewFacet = getManagementSelectors();
                } else if (i == 1) {
                    allSelectorsForNewFacet = getAccessControlSelectors();
                } else if (i == 2) {
                    allSelectorsForNewFacet = getValidatorSelectors();
                } else if (i == 3) {
                    allSelectorsForNewFacet = getStakingSelectors();
                } else if (i == 4) {
                    allSelectorsForNewFacet = getRewardsSelectors();
                }

                // Check first selector to verify facet address
                if (allSelectorsForNewFacet.length > 0) {
                    address currentFacetAddress = loupe.facetAddress(allSelectorsForNewFacet[0]);
                    console2.log(
                        "  %s selector %s now points to: %s",
                        facetNames[i],
                        vm.toString(allSelectorsForNewFacet[0]),
                        currentFacetAddress
                    );
                    console2.log("  Expected: %s", newAddresses[i]);
                    bool facetAddrCorrect = currentFacetAddress == newAddresses[i];
                    console2.log("  Facet Address Correct: %b", facetAddrCorrect);

                    // Verify all selectors point to the new implementation
                    bool allSelectorsValid = true;
                    uint256 mismatchedCount = 0;
                    for (uint256 j = 0; j < allSelectorsForNewFacet.length; j++) {
                        if (loupe.facetAddress(allSelectorsForNewFacet[j]) != newAddresses[i]) {
                            console2.log(
                                "    MISMATCH: Selector %s points to %s",
                                vm.toString(allSelectorsForNewFacet[j]),
                                loupe.facetAddress(allSelectorsForNewFacet[j])
                            );
                            allSelectorsValid = false;
                            mismatchedCount++;
                        }
                    }
                    if (mismatchedCount > 0) {
                        console2.log("    Found %d mismatched selectors for %s", mismatchedCount, facetNames[i]);
                    }
                    console2.log("  All selectors verified for %s: %b", facetNames[i], allSelectorsValid);
                } else {
                    console2.log("  Skipping verification for %s - No selectors found.", facetNames[i]);
                }
            }
        } else {
            console2.log("\n6. No ADD operations to execute.");
        }

        console2.log("\n--- Plume Staking Diamond Upgrade Complete --- ");
        console2.log("\nNote on library updates (PlumeErrors.sol, PlumeEvents.sol, etc.):");
        console2.log("  Libraries are automatically included with facet implementations.");
        console2.log("  When a facet that imports a library is upgraded, it uses the new library code.");
        console2.log("  No separate diamond cut needed for library changes.");

        vm.stopBroadcast();
    }

}
