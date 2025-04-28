// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script, console2 } from "forge-std/Script.sol";

// --- SolidState Diamond Interfaces ---
import { IERC2535DiamondCutInternal } from "solidstate-solidity/interfaces/IERC2535DiamondCutInternal.sol";
import { IERC2535DiamondLoupe } from "solidstate-solidity/interfaces/IERC2535DiamondLoupe.sol";

import { IERC2535DiamondLoupeInternal } from "solidstate-solidity/interfaces/IERC2535DiamondLoupeInternal.sol";
import { ISolidStateDiamondProxy} from "solidstate-solidity/proxy/diamond/SolidStateDiamondProxysol";

// --- Plume Facets ---
import { AccessControlFacet } from "../src/facets/AccessControlFacet.sol";
import { ManagementFacet } from "../src/facets/ManagementFacet.sol";
import { RewardsFacet } from "../src/facets/RewardsFacet.sol";
import { StakingFacet } from "../src/facets/StakingFacet.sol";
import { ValidatorFacet } from "../src/facets/ValidatorFacet.sol";

// Import PlumeRoles for AccessControl selectors
import { PlumeRoles } from "../src/lib/PlumeRoles.sol";

contract UpgradePlumeStakingDiamond is Script {

    // --- Configuration ---
    // Existing Deployment Addresses (FROM USER LOG)
    address private constant DIAMOND_PROXY_ADDRESS = 0xA20bfe49969D4a0E9abfdb6a46FeD777304ba07f;

    // Current facet addresses
    address private constant OLD_MANAGEMENT_FACET_ADDRESS = 0x2B52edbDA1604DE6068C82a7A80eE33A4506486a;
    address private constant OLD_ACCESSCONTROL_FACET_ADDRESS = 0xc72060f628c3E5463394E28b5a4e173897F0C95B;
    address private constant OLD_VALIDATOR_FACET_ADDRESS = 0x7994D58fCEb3d28B4D87ffC60DD959d0b3654c6B;
    address private constant OLD_STAKING_FACET_ADDRESS = 0xDD47B4F3daA01fBB732705Dc6Ec2b6c19DB70540;
    address private constant OLD_REWARDS_FACET_ADDRESS = 0xF19623C612a40E60A3d11bA648920B9c8f9438A5;

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
        selectors[0] = bytes4(keccak256(bytes("setMinStakeAmount(uint256)")));
        selectors[1] = bytes4(keccak256(bytes("setCooldownInterval(uint256)")));
        selectors[2] = bytes4(keccak256(bytes("adminWithdraw(address,uint256,address)")));
        selectors[3] = bytes4(keccak256(bytes("updateTotalAmounts(uint256,uint256)")));
        selectors[4] = bytes4(keccak256(bytes("getMinStakeAmount()")));
        selectors[5] = bytes4(keccak256(bytes("getCooldownInterval()")));
        selectors[6] = bytes4(keccak256(bytes("setMaxSlashVoteDuration(uint256)")));
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
        selectors[0] = bytes4(keccak256(bytes("addValidator(uint16,uint256,address,address,string,string,uint256)")));
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
        bytes4[] memory selectors = new bytes4[](11);
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
        return selectors;
    }

    function getRewardsSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](21);
        selectors[0] = bytes4(keccak256(bytes("addRewardToken(address)")));
        selectors[1] = bytes4(keccak256(bytes("removeRewardToken(address)")));
        selectors[2] = bytes4(keccak256(bytes("setRewardRates(address[],uint256[])")));
        selectors[3] = bytes4(keccak256(bytes("setMaxRewardRate(address,uint256)")));
        selectors[4] = bytes4(keccak256(bytes("addRewards(address,uint256)")));
        selectors[5] = bytes4(keccak256(bytes("claim(address)")));
        selectors[6] = bytes4(keccak256(bytes("claim(address,uint16)")));
        selectors[7] = bytes4(keccak256(bytes("claimAll()")));
        selectors[8] = bytes4(keccak256(bytes("restakeRewards(uint16)")));
        selectors[9] = bytes4(keccak256(bytes("earned(address,address)")));
        selectors[10] = bytes4(keccak256(bytes("getClaimableReward(address,address)")));
        selectors[11] = bytes4(keccak256(bytes("getRewardTokens()")));
        selectors[12] = bytes4(keccak256(bytes("getMaxRewardRate(address)")));
        selectors[13] = bytes4(keccak256(bytes("tokenRewardInfo(address)")));
        selectors[14] = bytes4(keccak256(bytes("getRewardRateCheckpointCount(address)")));
        selectors[15] = bytes4(keccak256(bytes("getValidatorRewardRateCheckpointCount(uint16,address)")));
        selectors[16] = bytes4(keccak256(bytes("getUserLastCheckpointIndex(address,uint16,address)")));
        selectors[17] = bytes4(keccak256(bytes("getRewardRateCheckpoint(address,uint256)")));
        selectors[18] = bytes4(keccak256(bytes("getValidatorRewardRateCheckpoint(uint16,address,uint256)")));
        selectors[19] = bytes4(keccak256(bytes("setTreasury(address)")));
        selectors[20] = bytes4(keccak256(bytes("getTreasury()")));
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

        IERC2535DiamondLoupeInternal.Facet[] memory facets = loupe.facets();
        console2.log("  Total facets in diamond:", facets.length);

        // --- Step 3: Prepare Diamond Cut for upgrades ---
        console2.log("\n3. Preparing Diamond Cut for facet upgrades...");

        uint256 cutCount = 0;
        IERC2535DiamondCutInternal.FacetCut[] memory cut = new IERC2535DiamondCutInternal.FacetCut[](10); // Double size
            // to accommodate both REPLACE and ADD

        // --- Handle each facet upgrade ---
        function(address) returns (bytes4[] memory) getSelectors;

        address[5] memory oldAddresses = [
            OLD_MANAGEMENT_FACET_ADDRESS,
            OLD_ACCESSCONTROL_FACET_ADDRESS,
            OLD_VALIDATOR_FACET_ADDRESS,
            OLD_STAKING_FACET_ADDRESS,
            OLD_REWARDS_FACET_ADDRESS
        ];

        address[5] memory newAddresses = [
            address(newManagementFacet),
            address(newAccessControlFacet),
            address(newValidatorFacet),
            address(newStakingFacet),
            address(newRewardsFacet)
        ];

        string[5] memory facetNames =
            ["ManagementFacet", "AccessControlFacet", "ValidatorFacet", "StakingFacet", "RewardsFacet"];

        for (uint256 i = 0; i < oldAddresses.length; i++) {
            if (oldAddresses[i] != address(0)) {
                // Get existing selectors
                bytes4[] memory existingSelectors = loupe.facetFunctionSelectors(oldAddresses[i]);

                // Get all selectors (including new ones)
                bytes4[] memory allSelectors;
                if (i == 0) {
                    allSelectors = getManagementSelectors();
                } else if (i == 1) {
                    allSelectors = getAccessControlSelectors();
                } else if (i == 2) {
                    allSelectors = getValidatorSelectors();
                } else if (i == 3) {
                    allSelectors = getStakingSelectors();
                } else if (i == 4) {
                    allSelectors = getRewardsSelectors();
                }

                // Find new selectors
                bytes4[] memory newSelectors = findNewSelectors(existingSelectors, allSelectors);

                // Add REPLACE cut for existing selectors
                if (existingSelectors.length > 0) {
                    cut[cutCount] = IERC2535DiamondCutInternal.FacetCut({
                        target: newAddresses[i],
                        action: IERC2535DiamondCutInternal.FacetCutAction.REPLACE,
                        selectors: existingSelectors
                    });
                    cutCount++;
                    console2.log("  Added", facetNames[i]);
                    console2.log("REPLACE upgrade with", existingSelectors.length);
                    console2.log("selectors");
                }

                // Add ADD cut for new selectors
                if (newSelectors.length > 0) {
                    cut[cutCount] = IERC2535DiamondCutInternal.FacetCut({
                        target: newAddresses[i],
                        action: IERC2535DiamondCutInternal.FacetCutAction.ADD,
                        selectors: newSelectors
                    });
                    cutCount++;
                    console2.log("  Added", facetNames[i]);
                    console2.log("ADD upgrade with", newSelectors.length, "new selectors");
                    console2.log("new selectors");
                }
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
            ISolidStateDiamondProxypayable(DIAMOND_PROXY_ADDRESS)).diamondCut(finalCut, address(0), "");
            console2.log("  Diamond Cut executed successfully.");

            // --- Step 5: Verification ---
            console2.log("\n5. Verifying upgrades...");

            // Verify each facet
            for (uint256 i = 0; i < oldAddresses.length; i++) {
                if (oldAddresses[i] != address(0)) {
                    bytes4[] memory allSelectors;
                    if (i == 0) {
                        allSelectors = getManagementSelectors();
                    } else if (i == 1) {
                        allSelectors = getAccessControlSelectors();
                    } else if (i == 2) {
                        allSelectors = getValidatorSelectors();
                    } else if (i == 3) {
                        allSelectors = getStakingSelectors();
                    } else if (i == 4) {
                        allSelectors = getRewardsSelectors();
                    }

                    // Check first selector to verify facet address
                    address newAddress = loupe.facetAddress(allSelectors[0]);
                    console2.log("  ", facetNames[i], "now points to:", newAddress);
                    console2.log("  Expected:", newAddresses[i]);
                    console2.log("  Verified:", newAddress == newAddresses[i]);

                    // Verify all selectors point to the new implementation
                    bool allValid = true;
                    for (uint256 j = 0; j < allSelectors.length; j++) {
                        if (loupe.facetAddress(allSelectors[j]) != newAddresses[i]) {
                            allValid = false;
                            break;
                        }
                    }
                    console2.log("  All selectors verified:", allValid);
                }
            }
        } else {
            console2.log("\n4. No facet upgrades to execute.");
        }

        console2.log("\n--- Plume Staking Diamond Upgrade Complete --- ");
        console2.log("\nNote on library updates (PlumeErrors.sol, PlumeEvents.sol, etc.):");
        console2.log("  Libraries are automatically included with facet implementations.");
        console2.log("  When a facet that imports a library is upgraded, it uses the new library code.");
        console2.log("  No separate diamond cut needed for library changes.");

        vm.stopBroadcast();
    }

}
