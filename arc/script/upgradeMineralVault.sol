// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../src/ArcToken.sol";
import "../src/proxy/ArcTokenProxy.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { Script } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

/**
 * @title Mineral Vault Token Upgrade Script
 * @notice Upgrades the implementation of an existing ArcToken proxy for Mineral Vault
 */
contract UpgradeMineralVault is Script, Test {

    // Address of the admin - should be the admin of the token
    address private constant ADMIN_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;

    // The address of the deployed ArcToken proxy to upgrade
    // IMPORTANT: Update this with your deployed Mineral Vault token address
    address private constant TOKEN_PROXY_ADDRESS = 0xa3Bc080265ac5dce0e95Bfcb2Aea07802801C892;

    function test() public { }

    /**
     * @notice Deploys a new ArcToken implementation and upgrades the proxy
     */
    function run() external {
        require(
            TOKEN_PROXY_ADDRESS != address(0),
            "ERROR: Please update the TOKEN_PROXY_ADDRESS constant with your Mineral Vault token address!"
        );

        console2.log("Starting Mineral Vault token upgrade process...");
        console2.log("Token Proxy Address:", TOKEN_PROXY_ADDRESS);

        vm.startBroadcast(ADMIN_ADDRESS);

        // Deploy new implementation
        ArcToken newImplementation = new ArcToken();
        console2.log("New ArcToken implementation deployed to:", address(newImplementation));

        // Get the current token instance
        ArcToken token = ArcToken(TOKEN_PROXY_ADDRESS);

        try token.name() returns (string memory tokenName) {
            console2.log("Current token name:", tokenName);

            // Perform the upgrade through the UUPSUpgradeable pattern
            ArcToken upgradeableToken = ArcToken(payable(TOKEN_PROXY_ADDRESS));
            upgradeableToken.upgradeToAndCall(address(newImplementation), "");
            console2.log("Token proxy upgraded to new implementation");

            // Log success information
            console2.log("\n---------- UPGRADE SUMMARY ----------");
            console2.log("Token Proxy:", TOKEN_PROXY_ADDRESS);
            console2.log("New Implementation:", address(newImplementation));
            console2.log("Admin:", ADMIN_ADDRESS);
        } catch {
            console2.log("Could not access current token details. Please verify the TOKEN_PROXY_ADDRESS is correct.");
        }

        // Instructions for verifying the upgrade
        console2.log("\n---------- VERIFICATION STEPS ----------");
        console2.log("1. Call getTokenMetrics to verify new parameter structure:");
        console2.log("   token.getTokenMetrics(address holder) should return:");
        console2.log("   - secondsHeld");
        console2.log("\n2. AssetValuation parameter has been removed from the token.");
        console2.log("   The getAssetInfo function now only returns the asset name and price per token (0).");

        vm.stopBroadcast();
    }

}
