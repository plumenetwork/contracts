// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script, console2 } from "forge-std/Script.sol";

// --- SolidState Diamond Interfaces ---
import { IERC2535DiamondCutInternal } from "@solidstate/interfaces/IERC2535DiamondCutInternal.sol";
import { IERC2535DiamondLoupe } from "@solidstate/interfaces/IERC2535DiamondLoupe.sol";
import { ISolidStateDiamondProxy} from "@solidstate/proxy/diamond/ISolidStateDiamondProxysol";

import { IERC2535DiamondLoupeInternal } from "solidstate-solidity/interfaces/IERC2535DiamondLoupeInternal.sol";
import { ISolidStateDiamondProxy} from "solidstate-solidity/proxy/diamond/SolidStateDiamondProxysol";

// --- Plume Facets ---
import { AccessControlFacet } from "../../src/facets/AccessControlFacet.sol";
import { ManagementFacet } from "../../src/facets/ManagementFacet.sol";
import { RewardsFacet } from "../../src/facets/RewardsFacet.sol";
import { StakingFacet } from "../../src/facets/StakingFacet.sol";
import { ValidatorFacet } from "../../src/facets/ValidatorFacet.sol";

// Import PlumeRoles for AccessControl selectors
import { PlumeRoles } from "../../src/lib/PlumeRoles.sol";

/**
 * @title UpgradePlumeStakingDiamond
 * @notice Script to perform a comprehensive upgrade of all core facets.
 * @dev Deploys new facet implementations and replaces all their functions in the diamond.
 *      Run this script against a network using:
 *      forge script p/script/upgrade/UpgradePlumeStakingDiamond.s.sol:UpgradePlumeStakingDiamond --rpc-url
 * <your_rpc_url> --private-key <your_private_key> --broadcast -vvv
 */
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
            if (!_contains(listB, listA[i])) {
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
            if (_contains(listB, listA[i])) {
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
    address private constant OLD_MANAGEMENT_FACET_ADDRESS = 0x3e4BE54F1BbB11F3c36D4ab990030d1b5DBD3C40;
    address private constant OLD_ACCESSCONTROL_FACET_ADDRESS = 0x7e66f2F6fd551e92B4A23306AA4F8f21e44a1359;
    address private constant OLD_VALIDATOR_FACET_ADDRESS = 0x25c2CCCdA4C8e30746930F9B6e9C58E3d189B73E;
    address private constant OLD_STAKING_FACET_ADDRESS = 0x76eF355e6DdB834640a6924957D5B1d87b639375;
    address private constant OLD_REWARDS_FACET_ADDRESS = 0x431E7b32634dbefF77111c36A720945a3791aC85;

    // Address with upgrade permissions (Owner or UPGRADER_ROLE)
    address private constant UPGRADER_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;

    // --- Helper Functions ---
    function getAllSelectors(
        address facet
    ) internal view returns (bytes4[] memory) {
        // Get all function selectors from the facet
        bytes4[] memory selectors;
        try ISolidStateDiamondProxypayable(facet)).supportsInterface("") returns (bool) {
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
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = ManagementFacet.setMinStakeAmount.selector; // setMinStakeAmount(uint256)
        selectors[1] = ManagementFacet.setCooldownInterval.selector; // setCooldownInterval(uint256)
        selectors[2] = ManagementFacet.adminWithdraw.selector; // adminWithdraw(address,uint256,address)
        selectors[3] = ManagementFacet.updateTotalAmounts.selector; // updateTotalAmounts(uint256,uint256)
        selectors[4] = ManagementFacet.getMinStakeAmount.selector; // getMinStakeAmount()
        selectors[5] = ManagementFacet.getCooldownInterval.selector; // getCooldownInterval()
        selectors[6] = ManagementFacet.setMaxSlashVoteDuration.selector; // setMaxSlashVoteDuration(uint256)
        return selectors;
    }

    function getAccessControlSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = AccessControlFacet.initializeAccessControl.selector; // initializeAccessControl()
        selectors[1] = AccessControlFacet.hasRole.selector; // hasRole(bytes32,address)
        selectors[2] = AccessControlFacet.getRoleAdmin.selector; // getRoleAdmin(bytes32)
        selectors[3] = AccessControlFacet.grantRole.selector; // grantRole(bytes32,address)
        selectors[4] = AccessControlFacet.revokeRole.selector; // revokeRole(bytes32,address)
        selectors[5] = AccessControlFacet.renounceRole.selector; // renounceRole(bytes32,address)
        selectors[6] = AccessControlFacet.setRoleAdmin.selector; // setRoleAdmin(bytes32,bytes32)
        // PlumeRoles constants (assuming these are public view functions)
        selectors[7] = bytes4(keccak256(bytes("ADMIN_ROLE()")));
        selectors[8] = bytes4(keccak256(bytes("UPGRADER_ROLE()")));
        selectors[9] = bytes4(keccak256(bytes("VALIDATOR_ROLE()")));
        selectors[10] = bytes4(keccak256(bytes("REWARD_MANAGER_ROLE()")));
        return selectors;
    }

    function getValidatorSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](12);
        selectors[0] = ValidatorFacet.addValidator.selector; // addValidator(uint16,uint256,address,address,string,string,address,uint256)
        selectors[1] = ValidatorFacet.setValidatorCapacity.selector; // setValidatorCapacity(uint16,uint256)
        selectors[2] = ValidatorFacet.updateValidator.selector; // updateValidator(uint16,uint8,bytes)
        selectors[3] = ValidatorFacet.claimValidatorCommission.selector; // claimValidatorCommission(uint16,address)
        selectors[4] = ValidatorFacet.getValidatorInfo.selector; // getValidatorInfo(uint16)
        selectors[5] = ValidatorFacet.getValidatorStats.selector; // getValidatorStats(uint16)
        selectors[6] = ValidatorFacet.getUserValidators.selector; // getUserValidators(address)
        selectors[7] = ValidatorFacet.getAccruedCommission.selector; // getAccruedCommission(uint16,address)
        selectors[8] = ValidatorFacet.getValidatorsList.selector; // getValidatorsList()
        selectors[9] = ValidatorFacet.getActiveValidatorCount.selector; // getActiveValidatorCount()
        selectors[10] = ValidatorFacet.voteToSlashValidator.selector; // voteToSlashValidator(uint16,uint256)
        selectors[11] = ValidatorFacet.slashValidator.selector; // slashValidator(uint16)
        return selectors;
    }

    function getStakingSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](16);
        selectors[0] = StakingFacet.stake.selector; // stake(uint16)
        selectors[1] = StakingFacet.stakeOnBehalf.selector; // stakeOnBehalf(uint16,address)
        selectors[2] = StakingFacet.restake.selector; // restake(uint16,uint256)
        selectors[3] = bytes4(keccak256("unstake(uint16)")); // unstake(uint16) (Overload 1)
        selectors[4] = bytes4(keccak256("unstake(uint16,uint256)")); // unstake(uint16,uint256) (Overload 2)
        selectors[5] = StakingFacet.withdraw.selector; // withdraw()
        selectors[6] = StakingFacet.restakeRewards.selector; // restakeRewards(uint16)
        selectors[7] = StakingFacet.stakeInfo.selector; // stakeInfo(address)
        selectors[8] = StakingFacet.amountStaked.selector; // amountStaked()
        selectors[9] = StakingFacet.amountCooling.selector; // amountCooling()
        selectors[10] = StakingFacet.amountWithdrawable.selector; // amountWithdrawable()
        selectors[11] = StakingFacet.cooldownEndDate.selector; // cooldownEndDate()
        selectors[12] = StakingFacet.getUserValidatorStake.selector; // getUserValidatorStake(address,uint16)
        selectors[13] = StakingFacet.totalAmountStaked.selector; // totalAmountStaked()
        selectors[14] = StakingFacet.totalAmountCooling.selector; // totalAmountCooling()
        selectors[15] = StakingFacet.totalAmountWithdrawable.selector; // totalAmountWithdrawable()
        return selectors;
    }

    function getRewardsSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](22);
        selectors[0] = RewardsFacet.addRewardToken.selector; // addRewardToken(address)
        selectors[1] = RewardsFacet.removeRewardToken.selector; // removeRewardToken(address)
        selectors[2] = RewardsFacet.setRewardRates.selector; // setRewardRates(address[],uint256[])
        selectors[3] = RewardsFacet.setMaxRewardRate.selector; // setMaxRewardRate(address,uint256)
        selectors[4] = RewardsFacet.addRewards.selector; // addRewards(address,uint256)
        selectors[5] = bytes4(keccak256("claim(address)")); // claim(address) overload
        selectors[6] = bytes4(keccak256("claim(address,uint16)")); // claim(address,uint16) overload
        selectors[7] = RewardsFacet.claimAll.selector; // claimAll()
        selectors[8] = RewardsFacet.earned.selector; // earned(address,address)
        selectors[9] = RewardsFacet.getClaimableReward.selector; // getClaimableReward(address,address)
        selectors[10] = RewardsFacet.getRewardTokens.selector; // getRewardTokens()
        selectors[11] = RewardsFacet.getMaxRewardRate.selector; // getMaxRewardRate(address)
        selectors[12] = RewardsFacet.tokenRewardInfo.selector; // tokenRewardInfo(address)
        selectors[13] = RewardsFacet.getRewardRateCheckpointCount.selector; // getRewardRateCheckpointCount(address)
        selectors[14] = RewardsFacet.getValidatorRewardRateCheckpointCount.selector; // getValidatorRewardRateCheckpointCount(uint16,address)
        selectors[15] = RewardsFacet.getUserLastCheckpointIndex.selector; // getUserLastCheckpointIndex(address,uint16,address)
        selectors[16] = RewardsFacet.getRewardRateCheckpoint.selector; // getRewardRateCheckpoint(address,uint256)
        selectors[17] = RewardsFacet.getValidatorRewardRateCheckpoint.selector; // getValidatorRewardRateCheckpoint(uint16,address,uint256)
        selectors[18] = RewardsFacet.setTreasury.selector; // setTreasury(address)
        selectors[19] = RewardsFacet.getTreasury.selector; // getTreasury()
        selectors[20] = RewardsFacet.getPendingRewardForValidator.selector; // getPendingRewardForValidator(address,uint16,address)
        selectors[21] = bytes4(keccak256("getRewardRate(address)"));
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

    /**
     * @dev Gets the CURRENTLY registered selectors for a given facet address from the diamond.
     * Requires the diamond to implement DiamondLoupe.
     */
    function getSelectorsForFacet(
        address _facetAddress
    ) internal view returns (bytes4[] memory) {
        IERC2535DiamondLoupe loupe = IERC2535DiamondLoupe(DIAMOND_PROXY_ADDRESS);
        return loupe.facetFunctionSelectors(_facetAddress);
    }

    /**
     * @dev Helper to log details of a FacetCut array.
     */
    function logFacetCut(string memory prefix, IERC2535DiamondCutInternal.FacetCut[] memory cut) internal {
        console2.log("%s (%d cuts):", prefix, cut.length);
        for (uint256 i = 0; i < cut.length; i++) {
            string memory actionStr;
            if (cut[i].action == IERC2535DiamondCutInternal.FacetCutAction.ADD) {
                actionStr = "ADD";
            } else if (cut[i].action == IERC2535DiamondCutInternal.FacetCutAction.REPLACE) {
                actionStr = "REPLACE";
            } else if (cut[i].action == IERC2535DiamondCutInternal.FacetCutAction.REMOVE) {
                actionStr = "REMOVE";
            } else {
                actionStr = "UNKNOWN";
            }

            console2.log("  Cut %d:", i);
            console2.log("    Action: %s", actionStr);
            console2.log("    Target: %s", cut[i].target);
            console2.log("    Selectors (%d):", cut[i].selectors.length);
            for (uint256 j = 0; j < cut[i].selectors.length; j++) {
                console2.log("      - %s", vm.toString(cut[i].selectors[j]));
            }
        }
    }

    function run() external {
        vm.startBroadcast(UPGRADER_ADDRESS);

        console2.log("--- Starting Plume Staking Diamond Comprehensive Upgrade --- ");
        console2.log("Target Proxy: %s", DIAMOND_PROXY_ADDRESS);
        console2.log("Upgrader Address (msg.sender): %s", msg.sender);
        console2.log("Make sure OLD_FACET_ADDRESS constants are correct!");

        // --- Step 1: Deploy New Facet Implementations ---
        console2.log("\n1. Deploying new facet implementations...");

        AccessControlFacet newAccessControlFacet = new AccessControlFacet();
        ManagementFacet newManagementFacet = new ManagementFacet();
        ValidatorFacet newValidatorFacet = new ValidatorFacet();
        StakingFacet newStakingFacet = new StakingFacet();
        RewardsFacet newRewardsFacet = new RewardsFacet();

        console2.log("  New AccessControlFacet deployed at: %s", address(newAccessControlFacet));
        console2.log("  New ManagementFacet deployed at: %s", address(newManagementFacet));
        console2.log("  New ValidatorFacet deployed at: %s", address(newValidatorFacet));
        console2.log("  New StakingFacet deployed at: %s", address(newStakingFacet));
        console2.log("  New RewardsFacet deployed at: %s", address(newRewardsFacet));

        // --- Step 2: Calculate Selector Changes ---
        console2.log("\n2. Calculating selector changes...");

        // --- Prepare data structures ---
        address[] memory oldAddresses = new address[](5);
        oldAddresses[0] = OLD_ACCESSCONTROL_FACET_ADDRESS;
        oldAddresses[1] = OLD_MANAGEMENT_FACET_ADDRESS;
        oldAddresses[2] = OLD_VALIDATOR_FACET_ADDRESS;
        oldAddresses[3] = OLD_STAKING_FACET_ADDRESS;
        oldAddresses[4] = OLD_REWARDS_FACET_ADDRESS;

        address[] memory newAddresses = new address[](5);
        newAddresses[0] = address(newAccessControlFacet);
        newAddresses[1] = address(newManagementFacet);
        newAddresses[2] = address(newValidatorFacet);
        newAddresses[3] = address(newStakingFacet);
        newAddresses[4] = address(newRewardsFacet);

        string[5] memory facetNames = ["AccessControl", "Management", "Validator", "Staking", "Rewards"];

        // --- Aggregate all old selectors and all new selectors ---
        bytes4[] memory allOldSelectors;
        bytes4[] memory allNewSelectors;

        for (uint256 i = 0; i < 5; i++) {
            bytes4[] memory oldSigs;
            bytes4[] memory newSigs;

            // Get OLD selectors (handle potential zero address for initial deploy/missing facets)
            if (oldAddresses[i] != address(0)) {
                oldSigs = getSelectorsForFacet(oldAddresses[i]);
            } else {
                console2.log("  Skipping old selector fetch for %s (address is 0x0)", facetNames[i]);
            }

            // Get NEW selectors from helper functions
            if (i == 0) {
                newSigs = getAccessControlSelectors();
            } else if (i == 1) {
                newSigs = getManagementSelectors();
            } else if (i == 2) {
                newSigs = getValidatorSelectors();
            } else if (i == 3) {
                newSigs = getStakingSelectors();
            } else if (i == 4) {
                newSigs = getRewardsSelectors();
            }

            console2.log(
                "  %s: Found %d OLD selectors, %d NEW selectors.", facetNames[i], oldSigs.length, newSigs.length
            );

            // Combine into master lists
            bytes4[] memory combinedOld = new bytes4[](allOldSelectors.length + oldSigs.length);
            for (uint256 k = 0; k < allOldSelectors.length; k++) {
                combinedOld[k] = allOldSelectors[k];
            }
            for (uint256 k = 0; k < oldSigs.length; k++) {
                combinedOld[allOldSelectors.length + k] = oldSigs[k];
            }
            allOldSelectors = combinedOld;

            bytes4[] memory combinedNew = new bytes4[](allNewSelectors.length + newSigs.length);
            for (uint256 k = 0; k < allNewSelectors.length; k++) {
                combinedNew[k] = allNewSelectors[k];
            }
            for (uint256 k = 0; k < newSigs.length; k++) {
                combinedNew[allNewSelectors.length + k] = newSigs[k];
            }
            allNewSelectors = combinedNew;
        }

        // --- Calculate ADD, REMOVE, REPLACE ---
        bytes4[] memory selectorsToAdd = _difference(allNewSelectors, allOldSelectors);
        bytes4[] memory selectorsToRemove = _difference(allOldSelectors, allNewSelectors);
        bytes4[] memory selectorsToReplace = _intersection(allNewSelectors, allOldSelectors);

        // FIX: Use correct console log format
        console2.log("  Total Selectors Calculated:");
        console2.log("    ADD: %d", selectorsToAdd.length);
        console2.log("    REMOVE: %d", selectorsToRemove.length);
        console2.log("    REPLACE: %d", selectorsToReplace.length);

        // --- Step 3: Prepare Diamond Cut Data ---
        console2.log("\n3. Preparing combined Diamond Cut data...");

        // We need cuts for: ADD, REMOVE, and REPLACE for each facet
        // Maximum possible cuts: 1 REMOVE + 5 ADD + 5 REPLACE = 11
        IERC2535DiamondCutInternal.FacetCut[] memory cut = new IERC2535DiamondCutInternal.FacetCut[](11);
        uint256 cutIndex = 0;

        // REMOVE Cut (only one needed for all removals)
        if (selectorsToRemove.length > 0) {
            console2.log("  - Preparing REMOVE cut for %d selectors", selectorsToRemove.length);
            cut[cutIndex] = IERC2535DiamondCutInternal.FacetCut({
                target: address(0), // Target is ignored for REMOVE
                action: IERC2535DiamondCutInternal.FacetCutAction.REMOVE,
                selectors: selectorsToRemove
            });
            cutIndex++;
        }

        // ADD and REPLACE Cuts (one per facet)
        for (uint256 i = 0; i < 5; i++) {
            bytes4[] memory facetNewSelectors;
            if (i == 0) {
                facetNewSelectors = getAccessControlSelectors();
            } else if (i == 1) {
                facetNewSelectors = getManagementSelectors();
            } else if (i == 2) {
                facetNewSelectors = getValidatorSelectors();
            } else if (i == 3) {
                facetNewSelectors = getStakingSelectors();
            } else if (i == 4) {
                facetNewSelectors = getRewardsSelectors();
            }

            bytes4[] memory facetToAdd = _intersection(selectorsToAdd, facetNewSelectors);
            bytes4[] memory facetToReplace = _intersection(selectorsToReplace, facetNewSelectors);

            if (facetToAdd.length > 0) {
                console2.log("  - Preparing ADD cut for %s (%d selectors)", facetNames[i], facetToAdd.length);
                cut[cutIndex] = IERC2535DiamondCutInternal.FacetCut({
                    target: newAddresses[i],
                    action: IERC2535DiamondCutInternal.FacetCutAction.ADD,
                    selectors: facetToAdd
                });
                cutIndex++;
            }
            if (facetToReplace.length > 0) {
                console2.log("  - Preparing REPLACE cut for %s (%d selectors)", facetNames[i], facetToReplace.length);
                cut[cutIndex] = IERC2535DiamondCutInternal.FacetCut({
                    target: newAddresses[i],
                    action: IERC2535DiamondCutInternal.FacetCutAction.REPLACE,
                    selectors: facetToReplace
                });
                cutIndex++;
            }
        }

        // Resize the cut array to the actual number of cuts needed
        IERC2535DiamondCutInternal.FacetCut[] memory finalCut = new IERC2535DiamondCutInternal.FacetCut[](cutIndex);
        for (uint256 i = 0; i < cutIndex; i++) {
            finalCut[i] = cut[i];
        }

        // --- SIMULATION: Log the proposed cut and exit ---
        console2.log("\n--- !!! SIMULATION MODE !!! ---");
        logFacetCut("Proposed Diamond Cut", finalCut);
        console2.log("--- !!! SIMULATION COMPLETE - NO TRANSACTION SENT !!! ---");
        console2.log("--- !!! To execute, comment out the SIMULATION block and uncomment Step 4 & 5 !!! ---");

        vm.stopBroadcast(); // Stop broadcast as we are only simulating
        return; // Exit the script here for simulation

        // --- Step 4: Execute Diamond Cut ---
        // !!! UNCOMMENT THIS BLOCK TO EXECUTE THE ACTUAL UPGRADE !!!
        if (finalCut.length > 0) {
            console2.log("\n4. Executing Diamond Cut with %d operations...", finalCut.length);
            ISolidStateDiamondProxypayable(DIAMOND_PROXY_ADDRESS)).diamondCut(finalCut, address(0), "");
            console2.log("  Diamond Cut executed successfully.");
        } else {
            console2.log("\n4. No changes detected. Skipping Diamond Cut.");
        }

        // --- Step 5: Verification ---
        // !!! UNCOMMENT THIS BLOCK TO EXECUTE THE ACTUAL UPGRADE !!!
        console2.log("\n5. Verifying upgrade...");
        IERC2535DiamondLoupe loupe = IERC2535DiamondLoupe(DIAMOND_PROXY_ADDRESS);

        bool overallSuccess = true;

        for (uint256 i = 0; i < 5; i++) {
            console2.log("--- Verifying Facet: %s ---", facetNames[i]);
            bytes4[] memory expectedSelectors;
            if (i == 0) {
                expectedSelectors = getAccessControlSelectors();
            } else if (i == 1) {
                expectedSelectors = getManagementSelectors();
            } else if (i == 2) {
                expectedSelectors = getValidatorSelectors();
            } else if (i == 3) {
                expectedSelectors = getStakingSelectors();
            } else if (i == 4) {
                expectedSelectors = getRewardsSelectors();
            }

            if (expectedSelectors.length == 0) {
                console2.log("  Skipping verification (no expected selectors).");
                continue;
            }

            address expectedAddress = newAddresses[i];
            bool facetVerified = true;
            uint256 mismatchCount = 0;

            for (uint256 j = 0; j < expectedSelectors.length; j++) {
                bytes4 sel = expectedSelectors[j];
                address actualAddress = address(0);
                try loupe.facetAddress(sel) returns (address addr) {
                    actualAddress = addr;
                } catch Error(string memory reason) {
                    console2.log("    ERROR: Loupe call failed for selector %s. Reason: %s", vm.toString(sel), reason);
                    facetVerified = false;
                    mismatchCount++;
                    continue;
                } catch Panic(uint256 code) {
                    console2.log("    ERROR: Loupe call PANICKED for selector %s. Code: %d", vm.toString(sel), code);
                    facetVerified = false;
                    mismatchCount++;
                    continue;
                }

                if (actualAddress != expectedAddress) {
                    console2.log(
                        "    MISMATCH: Selector %s points to %s (Expected %s)",
                        vm.toString(sel),
                        actualAddress,
                        expectedAddress
                    );
                    facetVerified = false;
                    mismatchCount++;
                }
            }

            if (facetVerified) {
                console2.log("  OK: All %d selectors point to %s", expectedSelectors.length, expectedAddress);
            } else {
                console2.log("  FAILED: Found %d mismatched selectors for %s", mismatchCount, facetNames[i]);
                overallSuccess = false;
            }
        }

        console2.log("\n--- Upgrade Verification Complete ---");
        if (overallSuccess) {
            console2.log("Result: SUCCESS");
        } else {
            console2.log("Result: FAILED - Check logs for mismatches.");
            // Consider reverting the transaction if verification fails in a real deployment
            // revert("Upgrade verification failed.");
        }

        vm.stopBroadcast();
    }

}
