// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script, console2 } from "forge-std/Script.sol";

// --- SolidState Diamond Interfaces ---
import { IERC2535DiamondCutInternal } from "solidstate-solidity/interfaces/IERC2535DiamondCutInternal.sol";

import { IERC2535DiamondLoupe } from "solidstate-solidity/interfaces/IERC2535DiamondLoupe.sol";
import { ISolidStateDiamondProxy} from "solidstate-solidity/proxy/diamond/SolidStateDiamondProxysol"; // For verification

contract FixRewardsFacet is Script {

    // --- Configuration ---
    address private constant DIAMOND_PROXY_ADDRESS = 0xA20bfe49969D4a0E9abfdb6a46FeD777304ba07f;
    // Address of the *NEW* RewardsFacet deployed in the main upgrade
    address private constant NEW_REWARDS_FACET_ADDRESS = 0x6D656cCB5FEAd9357F52092943a78061Bb1Ed5b8;
    // Address with upgrade permissions
    address private constant UPGRADER_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;

    function run() external {
        vm.startBroadcast(UPGRADER_ADDRESS);

        console2.log("--- Fixing RewardsFacet Selector --- ");
        console2.log("Target Proxy: %s", DIAMOND_PROXY_ADDRESS);
        console2.log("RewardsFacet Address: %s", NEW_REWARDS_FACET_ADDRESS);
        console2.log("Upgrader Address: %s", UPGRADER_ADDRESS);

        // --- Define Missing Selector ---
        bytes4[] memory selectorToAdd = new bytes4[](1);
        selectorToAdd[0] = bytes4(keccak256(bytes("getRewardRate(address)"))); // 0x24c60e50

        console2.log("\nPreparing to ADD selector: %s", vm.toString(selectorToAdd[0]));

        // --- Prepare Diamond Cut Data (ADD phase) ---
        IERC2535DiamondCutInternal.FacetCut[] memory addCut = new IERC2535DiamondCutInternal.FacetCut[](1);
        addCut[0] = IERC2535DiamondCutInternal.FacetCut({
            target: NEW_REWARDS_FACET_ADDRESS, // Point selector to the correct, new facet
            action: IERC2535DiamondCutInternal.FacetCutAction.ADD,
            selectors: selectorToAdd
        });

        // --- Execute ADD Diamond Cut ---
        console2.log("\nExecuting ADD Diamond Cut...");
        ISolidStateDiamondProxypayable(DIAMOND_PROXY_ADDRESS)).diamondCut(addCut, address(0), "");
        console2.log("  ADD Diamond Cut executed successfully.");

        // --- Verification (Optional but Recommended) ---
        console2.log("\nVerifying selector mapping...");
        IERC2535DiamondLoupe loupe = IERC2535DiamondLoupe(DIAMOND_PROXY_ADDRESS);
        bytes4 selector = selectorToAdd[0];
        address currentTarget = loupe.facetAddress(selector);
        if (currentTarget == NEW_REWARDS_FACET_ADDRESS) {
            console2.log("  OK: Selector %s correctly points to %s", vm.toString(selector), vm.toString(currentTarget));
            console2.log("\nVerification Successful.");
        } else {
            console2.log(
                "  ERROR: Selector %s points to %s, expected %s",
                vm.toString(selector),
                vm.toString(currentTarget),
                vm.toString(NEW_REWARDS_FACET_ADDRESS)
            );
            console2.log("\nVerification FAILED.");
        }

        console2.log("\n--- Rewards Facet Fix Complete --- ");

        vm.stopBroadcast();
    }

}
