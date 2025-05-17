// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script, console2 } from "forge-std/Script.sol";

// --- SolidState Diamond Interfaces ---
import { IERC2535DiamondLoupe } from "@solidstate/interfaces/IERC2535DiamondLoupe.sol";

// --- Plume Facet (Needed for selectors) ---
import { RewardsFacet } from "../../src/facets/RewardsFacet.sol";

/**
 * @title VerifyRewardsFacetSelectors
 * @notice Script to VERIFY where the RewardsFacet selectors currently point in the live Diamond.
 */
contract VerifyRewardsFacetSelectors is Script {

    // --- Configuration ---
    address private constant DIAMOND_PROXY_ADDRESS = 0xA20bfe49969D4a0E9abfdb6a46FeD777304ba07f;
    // Address of the *new* RewardsFacet implementation (where selectors SHOULD point)
    address private constant EXPECTED_REWARDS_FACET_ADDRESS = 0xfE673A14eB95657Ed676982Ba875cAbE32c710e6;
    // Address of the *old* RewardsFacet implementation (where some might still point)
    address private constant OLD_REWARDS_FACET_ADDRESS = 0x817D37e0C3BCfecC713158A4366186FbBea071C3;

    // --- Selector Helper Function ---
    function getAllRewardsSelectors() internal pure returns (bytes4[] memory) {
        // Expected 21 Selectors (16 original base + 1 restake + 4 global getters)
        bytes4[] memory selectors = new bytes4[](21);

        // Admin/Setup (Indices 0-5)
        selectors[0] = RewardsFacet.setTreasury.selector;
        selectors[1] = RewardsFacet.addRewardToken.selector;
        selectors[2] = RewardsFacet.removeRewardToken.selector;
        selectors[3] = RewardsFacet.setRewardRates.selector;
        selectors[4] = RewardsFacet.setMaxRewardRate.selector;

        // Claiming & Restaking (Indices 6-9)
        selectors[5] = bytes4(keccak256(bytes("claim(address)")));
        selectors[6] = bytes4(keccak256(bytes("claim(address,uint16)")));
        selectors[7] = RewardsFacet.claimAll.selector;
        selectors[8] = bytes4(keccak256(bytes("restakeRewards(uint16)")));

        // View Functions (User-specific) (Indices 10-11)
        selectors[9] = RewardsFacet.earned.selector;
        selectors[10] = RewardsFacet.getClaimableReward.selector;

        // View Functions (General Reward Info) (Indices 12-15)
        selectors[11] = RewardsFacet.getRewardTokens.selector;
        selectors[12] = RewardsFacet.getMaxRewardRate.selector;
        selectors[13] = RewardsFacet.tokenRewardInfo.selector;
        selectors[14] = RewardsFacet.getTreasury.selector;

        // Global View Functions (Added) (Indices 16-19)
        selectors[15] = bytes4(keccak256(bytes("totalAmountStaked()"))); // This function is now in StakingFacet
        selectors[16] = bytes4(keccak256(bytes("totalAmountCooling()"))); // This function is now in StakingFacet
        selectors[17] = bytes4(keccak256(bytes("totalAmountWithdrawable()"))); // This function is now in StakingFacet
        selectors[18] = bytes4(keccak256(bytes("totalAmountClaimable(address)"))); // This function is now in
            // StakingFacet

        // Index 20 is the last assigned.
        return selectors;
    }

    function run() external {
        // No broadcast needed for view calls

        console2.log("--- Verifying Rewards Facet Selectors & Reported Facets --- ");
        console2.log("Target Proxy:        ", DIAMOND_PROXY_ADDRESS);
        console2.log("Expected New Facet:  ", EXPECTED_REWARDS_FACET_ADDRESS);
        console2.log("Known Old Facet:     ", OLD_REWARDS_FACET_ADDRESS);

        // --- Get Loupe Interface ---
        IERC2535DiamondLoupe loupe = IERC2535DiamondLoupe(DIAMOND_PROXY_ADDRESS);

        // --- Step 1: Query and Log Reported Facets ---
        console2.log("\n1. Querying facets() reported by the diamond...");
        IERC2535DiamondLoupe.Facet[] memory reportedFacets = loupe.facets();
        console2.log("  Diamond reports", reportedFacets.length, "facet entries:");
        for (uint256 i = 0; i < reportedFacets.length; i++) {
            console2.log("    Entry", i + 1, ":");
            console2.log("      Facet Address:", reportedFacets[i].target);
            console2.log("      Selector Count:", reportedFacets[i].selectors.length);
            // Optionally log selectors (can be very verbose)
            // for (uint j = 0; j < reportedFacets[i].selectors.length; j++) {
            //     console2.log("        Selector:", reportedFacets[i].selectors[j]);
            // }
        }

        // --- Step 2: Get Target Selectors for RewardsFacet ---
        console2.log("\n2. Gathering target function selectors for RewardsFacet...");
        bytes4[] memory allTargetSelectors = getAllRewardsSelectors();
        console2.log("  Target RewardsFacet selectors gathered:", allTargetSelectors.length);
        require(allTargetSelectors.length == 21, "Incorrect number of Rewards selectors defined in script");

        // --- Step 3: Query Current Implementations via facetAddress ---
        console2.log("\n3. Querying current implementation for each target selector via facetAddress()...");
        uint256 mismatchCount = 0;

        for (uint256 i = 0; i < allTargetSelectors.length; i++) {
            bytes4 selector = allTargetSelectors[i];
            address currentImpl = loupe.facetAddress(selector);
            string memory status;
            if (currentImpl == EXPECTED_REWARDS_FACET_ADDRESS) {
                status = "OK (Points to New Facet)";
            } else if (currentImpl == OLD_REWARDS_FACET_ADDRESS) {
                status = "MISMATCH (Points to OLD Facet!)";
                mismatchCount++;
            } else if (currentImpl == address(0)) {
                status = "MISMATCH (Selector Not Found!)";
                mismatchCount++;
            } else {
                status = "MISMATCH (Points to Unexpected Address!)";
                mismatchCount++;
            }
            // Log points to and status on separate lines for clarity
            console2.logBytes4(selector);
            console2.log("    points to", currentImpl);
            console2.log("    Status:", status);
        }

        console2.log("\n--- Verification Complete --- ");
        if (mismatchCount == 0) {
            console2.log("Result: ALL target selectors point correctly to the new implementation.");
        } else {
            console2.log("Result: FAILED.", mismatchCount, "selector(s) do not point to the new implementation.");
            console2.log("Action Required: A corrective diamond cut is needed.");
        }
    }

}
