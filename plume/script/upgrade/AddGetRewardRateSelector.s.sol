// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script, console2 } from "forge-std/Script.sol";

// --- SolidState Diamond Interfaces ---
import { IERC2535DiamondCutInternal } from "@solidstate/interfaces/IERC2535DiamondCutInternal.sol";
import { IERC2535DiamondLoupe } from "@solidstate/interfaces/IERC2535DiamondLoupe.sol";
import { ISolidStateDiamond } from "@solidstate/proxy/diamond/ISolidStateDiamond.sol";

/**
 * @title AddGetRewardRateSelector
 * @notice Script to specifically add the getRewardRate selector mapping using the user-specified selector.
 * @dev Ensures the specified selector points to the correct RewardsFacet implementation.
 *      Uses ADD action assuming the selector was previously removed or never added.
 *      Uses user-specified selector 0xea7cbff1.
 *      Run this script against a network using:
 *      forge script p/script/upgrade/AddGetRewardRateSelector.s.sol:AddGetRewardRateSelector --rpc-url <your_rpc_url>
 * --private-key <your_private_key> --broadcast -vvv
 */
contract AddGetRewardRateSelector is Script {

    // --- Configuration ---
    address private constant DIAMOND_PROXY_ADDRESS = 0xA20bfe49969D4a0E9abfdb6a46FeD777304ba07f;
    // The address of the DEPLOYED RewardsFacet implementation that contains the function
    address private constant REWARDS_FACET_IMPLEMENTATION_ADDRESS = 0x431E7b32634dbefF77111c36A720945a3791aC85;
    // Address with upgrade permissions (Owner or UPGRADER_ROLE)
    address private constant UPGRADER_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;

    // Use the user-specified selector value directly
    bytes4 private constant SELECTOR_TO_ADD = 0xea7cbff1; // User specified selector

    function run() external {
        vm.startBroadcast(UPGRADER_ADDRESS);

        console2.log("--- Adding User-Specified Selector --- ");
        console2.log("Diamond Proxy: %s", DIAMOND_PROXY_ADDRESS);
        console2.log("Target RewardsFacet Implementation: %s", REWARDS_FACET_IMPLEMENTATION_ADDRESS);
        console2.log("Selector to map (User Specified): %s", vm.toString(SELECTOR_TO_ADD));

        // --- Prepare Diamond Cut Data ---
        IERC2535DiamondCutInternal.FacetCut[] memory cut = new IERC2535DiamondCutInternal.FacetCut[](1);

        cut[0] = IERC2535DiamondCutInternal.FacetCut({
            target: REWARDS_FACET_IMPLEMENTATION_ADDRESS,
            // Use ADD: Assumes the selector is missing.
            action: IERC2535DiamondCutInternal.FacetCutAction.ADD,
            selectors: new bytes4[](1)
        });
        cut[0].selectors[0] = SELECTOR_TO_ADD; // Use the user-specified selector

        // --- Execute Diamond Cut ---
        console2.log("Executing diamond cut (Action: ADD)...");
        try ISolidStateDiamond(payable(DIAMOND_PROXY_ADDRESS)).diamondCut(cut, address(0), "") {
            console2.log("  Diamond cut executed successfully.");
        } catch Error(string memory reason) {
            console2.log("  ERROR: Diamond cut failed: %s", reason);
            vm.stopBroadcast();
            revert("Diamond cut failed");
        } catch Panic(uint256 code) {
            console2.log("  PANIC: Diamond cut failed with code: %d", code);
            vm.stopBroadcast();
            revert("Diamond cut failed with panic");
        }

        // --- Verification ---
        console2.log("Verifying selector mapping...");
        IERC2535DiamondLoupe loupe = IERC2535DiamondLoupe(DIAMOND_PROXY_ADDRESS);
        address mappedAddress;
        try loupe.facetAddress(SELECTOR_TO_ADD) returns (address facetAddr) {
            mappedAddress = facetAddr;
            console2.log("  Selector %s currently points to: %s", vm.toString(SELECTOR_TO_ADD), mappedAddress);
        } catch Error(string memory reason) {
            console2.log(
                "  ERROR: Loupe check failed for selector %s. Reason: %s", vm.toString(SELECTOR_TO_ADD), reason
            );
            vm.stopBroadcast();
            revert("Verification failed: Loupe check error");
        } catch Panic(uint256 code) {
            console2.log("  PANIC: Loupe check failed for selector %s. Code: %d", vm.toString(SELECTOR_TO_ADD), code);
            vm.stopBroadcast();
            revert("Verification failed: Loupe check panic");
        }

        if (mappedAddress == REWARDS_FACET_IMPLEMENTATION_ADDRESS) {
            console2.log("  SUCCESS: Selector correctly mapped to the target RewardsFacet implementation.");
        } else {
            console2.log(
                "  FAILURE: Selector points to %s, expected %s.", mappedAddress, REWARDS_FACET_IMPLEMENTATION_ADDRESS
            );
            vm.stopBroadcast();
            revert("Verification failed: Selector mapped incorrectly");
        }

        console2.log("--- Selector Update Complete ---");
        vm.stopBroadcast();
    }

}
