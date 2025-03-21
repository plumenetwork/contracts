// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../src/ArcTokenFactory.sol";
import { Script } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

/**
 * @title ArcTokenFactory Upgrade Script
 * @notice Deploys a new implementation of ArcTokenFactory and upgrades an existing proxy
 */
contract UpgradeArcTokenFactory is Script, Test {

    // Address of the admin - should be the admin of the factory
    address private constant ADMIN_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;

    // The address of the deployed ArcTokenFactory proxy
    address private constant FACTORY_PROXY_ADDRESS = 0x5B45ba000A2CF8004F2F7BC6c9A539E67D7921B5;

    // Whether to whitelist the new implementation into the factory
    bool private constant SHOULD_WHITELIST_NEW_IMPL = true;

    // Address of a token created by the factory (needed for the updated version)
    // You need to replace this with an actual token address created by the factory
    address private constant SAMPLE_TOKEN_ADDRESS = address(0); // Replace with actual token

    function test() public { }

    /**
     * @notice Deploys a new ArcTokenFactory implementation and upgrades the proxy
     */
    function run() external {
        console2.log("Starting ArcTokenFactory upgrade process...");
        console2.log("Factory Proxy Address:", FACTORY_PROXY_ADDRESS);

        vm.startBroadcast(ADMIN_ADDRESS);

        // Deploy new implementation
        ArcTokenFactory newImplementation = new ArcTokenFactory();
        console2.log("New implementation deployed to:", address(newImplementation));

        // Get the current factory instance
        ArcTokenFactory factory = ArcTokenFactory(FACTORY_PROXY_ADDRESS);

        // The method has changed in the new version
        // The old version had getImplementationAddress()
        // The new version has getTokenImplementation(address token)

        // Check if we have a sample token to check implementation
        if (SAMPLE_TOKEN_ADDRESS != address(0)) {
            try factory.getTokenImplementation(SAMPLE_TOKEN_ADDRESS) returns (address tokenImplementation) {
                console2.log("Sample token implementation:", tokenImplementation);

                // Whitelist the new implementation in the old factory if specified
                if (SHOULD_WHITELIST_NEW_IMPL) {
                    factory.whitelistImplementation(address(newImplementation));
                    console2.log("New implementation whitelisted in current factory");
                }

                // Upgrade the proxy to the new implementation
                factory.upgradeToAndCall(address(newImplementation), "");
                console2.log("Factory proxy upgraded to new implementation");

                // Log success information
                console2.log("\n---------- UPGRADE SUMMARY ----------");
                console2.log("Factory Proxy:", FACTORY_PROXY_ADDRESS);
                console2.log("New Implementation:", address(newImplementation));
                console2.log("Sample Token:", SAMPLE_TOKEN_ADDRESS);
                console2.log("Sample Token Implementation:", tokenImplementation);
                console2.log("Admin:", ADMIN_ADDRESS);
            } catch {
                // This catches the case where we're trying to upgrade from the old version
                // that doesn't have getTokenImplementation to the new version
                console2.log(
                    "Could not get token implementation. Likely upgrading from old version without per-token implementations."
                );
                _performUpgradeWithoutImplementationCheck(factory, newImplementation);
            }
        } else {
            console2.log("No sample token address provided. Proceeding with upgrade without implementation check.");
            _performUpgradeWithoutImplementationCheck(factory, newImplementation);
        }

        vm.stopBroadcast();
    }

    /**
     * @dev Helper function to perform upgrade when we can't check implementations
     */
    function _performUpgradeWithoutImplementationCheck(
        ArcTokenFactory factory,
        ArcTokenFactory newImplementation
    ) private {
        // Try the old method for checking implementation (will only work with old version)
        try ArcTokenFactoryV1(address(factory)).getImplementationAddress() returns (address oldImplementation) {
            console2.log("Found old-style implementation:", oldImplementation);
        } catch {
            console2.log("Could not access implementation details with old method either. Proceeding anyway.");
        }

        // Try to whitelist the new implementation if requested
        if (SHOULD_WHITELIST_NEW_IMPL) {
            try factory.whitelistImplementation(address(newImplementation)) {
                console2.log("New implementation whitelisted in current factory");
            } catch {
                console2.log("Failed to whitelist implementation. Proceeding with upgrade anyway.");
            }
        }

        // Upgrade the proxy to the new implementation
        factory.upgradeToAndCall(address(newImplementation), "");
        console2.log("Factory proxy upgraded to new implementation");

        // Log success information
        console2.log("\n---------- UPGRADE SUMMARY ----------");
        console2.log("Factory Proxy:", FACTORY_PROXY_ADDRESS);
        console2.log("New Implementation:", address(newImplementation));
        console2.log("Admin:", ADMIN_ADDRESS);

        // Instructions for the new model
        console2.log("\n---------- ABOUT THE NEW FACTORY MODEL ----------");
        console2.log(
            "The new factory creates a fresh implementation for each token instead of sharing one implementation."
        );
        console2.log("This resolves initialization issues that could cause infinite recursion.");
        console2.log("Each token still uses a proxy for upgradeability, but has its own dedicated implementation.");

        // Instructions for verifying the upgrade
        console2.log("\n---------- VERIFICATION STEPS ----------");
        console2.log("1. Create a token with the updated factory:");
        console2.log("   factory.createToken(");
        console2.log("     name,                 // token name");
        console2.log("     symbol,               // token symbol");
        console2.log("     assetName,            // underlying asset name");
        console2.log("     initialSupply,        // initial token supply");
        console2.log("     yieldToken,           // yield token address");
        console2.log("     tokenIssuePrice,      // price at which tokens are issued");
        console2.log("     totalTokenOffering    // total number of tokens available");
        console2.log("   )");
        console2.log("\n2. After creating a token, verify its implementation with:");
        console2.log("   factory.getTokenImplementation(tokenAddress)");
    }

}

// Interface for the old version of the factory
interface ArcTokenFactoryV1 {

    function getImplementationAddress() external view returns (address);

}
