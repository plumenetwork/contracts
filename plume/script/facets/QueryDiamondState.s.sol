// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC2535DiamondLoupe } from "@solidstate/interfaces/IERC2535DiamondLoupe.sol";
import { IERC2535DiamondLoupeInternal } from "@solidstate/interfaces/IERC2535DiamondLoupeInternal.sol";
import { Script, console2 } from "forge-std/Script.sol"; // Needed for Facet struct

contract QueryDiamondState is Script {

    // --- Configuration ---
    // *** UPDATE THIS WITH THE ACTUAL DEPLOYED DIAMOND ADDRESS ***
    address private constant DIAMOND_PROXY_ADDRESS = 0xA20bfe49969D4a0E9abfdb6a46FeD777304ba07f; // Replace if needed

    // --- Selector Helper Functions (Copied from Upgrade Script) ---
    // These define the *EXPECTED* selectors based on the current facet code

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
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = bytes4(keccak256(bytes("initializeAccessControl()")));
        selectors[1] = bytes4(keccak256(bytes("hasRole(bytes32,address)")));
        selectors[2] = bytes4(keccak256(bytes("getRoleAdmin(bytes32)")));
        selectors[3] = bytes4(keccak256(bytes("grantRole(bytes32,address)")));
        selectors[4] = bytes4(keccak256(bytes("revokeRole(bytes32,address)")));
        selectors[5] = bytes4(keccak256(bytes("renounceRole(bytes32,address)")));
        selectors[6] = bytes4(keccak256(bytes("setRoleAdmin(bytes32,bytes32)")));
        return selectors;
    }

    function getValidatorSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](12);
        selectors[0] =
            bytes4(keccak256(bytes("addValidator(uint16,uint256,address,address,string,string,address,uint256)")));
        selectors[1] = bytes4(keccak256(bytes("setValidatorCapacity(uint16,uint256)")));
        selectors[2] = bytes4(keccak256(bytes("updateValidator(uint16,uint8,bytes)")));
        selectors[3] = bytes4(keccak256(bytes("requestCommissionClaim(uint16,address)")));
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

    // Structure to hold expected facet info
    struct ExpectedFacet {
        string name;
        bytes4[] selectors;
    }

    function run() external view {
        console2.log("--- Querying and Comparing Diamond State ---");
        console2.log("Diamond Proxy Address:", DIAMOND_PROXY_ADDRESS);

        // --- 1. Get Expected State ---
        ExpectedFacet[] memory expectedFacets = new ExpectedFacet[](5);
        expectedFacets[0] = ExpectedFacet("ManagementFacet", getManagementSelectors());
        expectedFacets[1] = ExpectedFacet("AccessControlFacet", getAccessControlSelectors());
        expectedFacets[2] = ExpectedFacet("ValidatorFacet", getValidatorSelectors());
        expectedFacets[3] = ExpectedFacet("StakingFacet", getStakingSelectors());
        expectedFacets[4] = ExpectedFacet("RewardsFacet", getRewardsSelectors());

        uint256 totalExpectedSelectors = 0;
        for (uint256 i = 0; i < expectedFacets.length; i++) {
            totalExpectedSelectors += expectedFacets[i].selectors.length;
        }
        console2.log(
            "\\nDefined %d expected selectors across %d facets.", totalExpectedSelectors, expectedFacets.length
        );

        // --- 2. Get Currently Registered State ---
        IERC2535DiamondLoupe loupe = IERC2535DiamondLoupe(DIAMOND_PROXY_ADDRESS);
        IERC2535DiamondLoupeInternal.Facet[] memory registeredFacets = loupe.facets();

        uint256 totalRegisteredSelectors = 0;
        for (uint256 i = 0; i < registeredFacets.length; i++) {
            totalRegisteredSelectors += registeredFacets[i].selectors.length;
        }
        console2.log(
            "Found %d selectors currently registered in the diamond across %d facets.",
            totalRegisteredSelectors,
            registeredFacets.length
        );

        // --- 3. Compare and Report ---
        console2.log("\\n--- Comparison Report ---");

        // Check status of all *expected* selectors
        console2.log("\\nChecking Expected Selectors:");
        uint256 missingCount = 0;
        for (uint256 i = 0; i < expectedFacets.length; i++) {
            string memory expectedName = expectedFacets[i].name;
            bytes4[] memory expectedSels = expectedFacets[i].selectors;

            for (uint256 j = 0; j < expectedSels.length; j++) {
                bytes4 expectedSelector = expectedSels[j];
                bool found = false;
                address foundAddress = address(0);

                // Search for this expected selector in the registered facets
                for (uint256 k = 0; k < registeredFacets.length; k++) {
                    bytes4[] memory registeredSels = registeredFacets[k].selectors;
                    for (uint256 l = 0; l < registeredSels.length; l++) {
                        if (registeredSels[l] == expectedSelector) {
                            found = true;
                            foundAddress = registeredFacets[k].target;
                            break; // Found in this registered facet
                        }
                    }
                    if (found) {
                        break;
                    } // Found in the diamond
                }

                if (!found) {
                    console2.log("  - Selector %s (Expected: %s): MISSING", vm.toString(expectedSelector), expectedName);
                    missingCount++;
                } else {
                    console2.log(
                        "  - Selector %s (Expected: %s): FOUND -> %s",
                        vm.toString(expectedSelector),
                        expectedName,
                        vm.toString(foundAddress)
                    );
                    // Future enhancement: Compare foundAddress to the *intended* new address for expectedName
                }
            }
        }
        console2.log("  Total Missing Expected Selectors: %d", missingCount);

        // Check for orphaned selectors (registered but not expected)
        console2.log("\\nChecking for Orphaned/Unexpected Selectors:");
        uint256 orphanCount = 0;
        for (uint256 i = 0; i < registeredFacets.length; i++) {
            address registeredAddress = registeredFacets[i].target;
            bytes4[] memory registeredSels = registeredFacets[i].selectors;

            for (uint256 j = 0; j < registeredSels.length; j++) {
                bytes4 registeredSelector = registeredSels[j];
                bool isExpected = false;

                // Search for this registered selector in the expected facets
                for (uint256 k = 0; k < expectedFacets.length; k++) {
                    bytes4[] memory expectedSels = expectedFacets[k].selectors;
                    for (uint256 l = 0; l < expectedSels.length; l++) {
                        if (expectedSels[l] == registeredSelector) {
                            isExpected = true;
                            break; // Found in this expected facet
                        }
                    }
                    if (isExpected) {
                        break;
                    } // Found it in the expected list
                }

                if (!isExpected) {
                    console2.log(
                        "  - Selector %s: ORPHANED (Points to %s)",
                        vm.toString(registeredSelector),
                        vm.toString(registeredAddress)
                    );
                    orphanCount++;
                }
            }
        }
        if (orphanCount == 0) {
            console2.log("  (None found)");
        }

        console2.log("\\n--- Diamond Query & Comparison Complete ---");
    }

}
