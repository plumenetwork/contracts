// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Script } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { RoycoNestMarketHelper } from "../src/RoycoNestMarketHelper.sol";
import { RoycoMarketHelperProxy } from "../src/proxy/RoycoMarketHelperProxy.sol";

contract UpgradeRoycoMarketHelper is Script, Test {

    // Configuration - Replace with actual deployed addresses
    address private constant ADMIN_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;

    // Address of the deployed proxy contract
    UUPSUpgradeable private constant MARKET_HELPER_PROXY =
        UUPSUpgradeable(payable(0x77B4bBD5A4A5636eDe8160eeb5d2932958fb7fDB));

    // Test function to satisfy forge test requirement
    function test() public { }

    function run() external {
        vm.startBroadcast(ADMIN_ADDRESS);

        // Deploy new implementation
        RoycoNestMarketHelper newImplementation = new RoycoNestMarketHelper();
        console2.log("New RoycoNestMarketHelper implementation deployed to:", address(newImplementation));

        // Verify the new implementation has code
        assertGt(address(newImplementation).code.length, 0, "RoycoNestMarketHelper should be deployed");

        // Upgrade to new implementation - note that we don't need to pass any initialization data
        // since this is an upgrade, not an initial deployment
        MARKET_HELPER_PROXY.upgradeToAndCall(address(newImplementation), "");
        console2.log("Proxy upgraded to new implementation");

        // Get the upgraded contract instance to interact with it
        RoycoNestMarketHelper marketHelper = RoycoNestMarketHelper(address(MARKET_HELPER_PROXY));

        vm.stopBroadcast();

        // Display all active vaults
        string[] memory vaultIds = marketHelper.getAllVaultIdentifiers();
        console2.log("Number of configured vaults:", vaultIds.length);
        for (uint256 i = 0; i < vaultIds.length; i++) {
            if (marketHelper.isVaultActive(vaultIds[i])) {
                (
                    address teller,
                    address vault,
                    address accountant,
                    uint256 slippageBps,
                    uint256 performanceBps,
                    bool active
                ) = marketHelper.vaults(vaultIds[i]);

                console2.log("Vault:", vaultIds[i]);
                console2.log("  Teller:", teller);
                console2.log("  Vault:", vault);
                console2.log("  Accountant:", accountant);
                console2.log("  Slippage BPS:", slippageBps);
                console2.log("  Performance BPS:", performanceBps);
                console2.log("  Active:", active ? "yes" : "no");
            }
        }
    }

}
