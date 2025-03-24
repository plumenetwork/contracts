// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../src/ArcToken.sol";
import "../src/proxy/ArcTokenProxy.sol";

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Script } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

/**
 * @title Mineral Vault I Security Token Deployment Script
 * @notice Deploys and configures an ArcToken specifically for the Mineral Vault I Security Token
 *         with unrestricted transfers (no whitelist) for initial setup
 */
contract DeployMineralVault is Script, Test {

    // Address of the admin - Update this to your address
    address private constant ADMIN_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;

    // Token configuration constants
    string public constant TOKEN_NAME = "Mineral Vault I Security Token";
    string public constant TOKEN_SYMBOL = "aMNRL";

    // Financial metrics (all monetary values scaled by 1e18)
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 1e18; // 1,000,000 tokens with 18 decimals

    // IMPORTANT: Update this address with your deployed MockUSDC address before running
    address private constant YIELD_TOKEN_ADDRESS = 0x41b199a4138BFA31b32f58Adb167F6981d5A99Dd;

    // Metadata URI path
    string private constant METADATA_URI_PATH = "mineralvault/";

    // Default admin role from AccessControl
    bytes32 private constant DEFAULT_ADMIN_ROLE = 0x00;

    function test() public { }

    /**
     * @notice Deploys and initializes the Mineral Vault I Security Token using ArcTokenProxy
     *         with unrestricted transfers (whitelist disabled) for initial setup
     */
    function run() external {
        // Verify the yield token address has been set
        require(
            YIELD_TOKEN_ADDRESS != address(0),
            "ERROR: Please update the YIELD_TOKEN_ADDRESS constant with your MockUSDC address!"
        );

        vm.startBroadcast(ADMIN_ADDRESS);

        // Deploy ArcToken implementation
        ArcToken implementation = new ArcToken();
        console2.log("ArcToken implementation deployed to:", address(implementation));

        // Create proxy using ArcTokenProxy - INITIALIZING WITH FULL TOKEN SUPPLY
        ArcTokenProxy arcTokenProxy = new ArcTokenProxy(
            address(implementation),
            abi.encodeCall(
                ArcToken(address(0)).initialize,
                (
                    TOKEN_NAME,
                    TOKEN_SYMBOL,
                    INITIAL_SUPPLY, // Initial token supply
                    YIELD_TOKEN_ADDRESS, // Yield token address
                    ADMIN_ADDRESS // The admin address will receive the initial token supply
                )
            )
        );

        // Get ArcToken interface of proxy
        ArcToken token = ArcToken(address(arcTokenProxy));

        // Set the full token URI
        token.setTokenURI(string.concat("https://arc.plumenetwork.xyz/tokens/", METADATA_URI_PATH));

        // Ensure transfers are unrestricted (no whitelist requirement)
        token.setTransfersAllowed(true);

        console2.log("Mineral Vault I Security Token deployed to:", address(arcTokenProxy));
        console2.log("Using yield token at address:", YIELD_TOKEN_ADDRESS);
        console2.log("Initial supply of", INITIAL_SUPPLY / 1e18, "tokens minted to admin:", ADMIN_ADDRESS);
        console2.log("IMPORTANT: Contract deployed with unrestricted transfers (whitelist disabled)");
        console2.log("The deploying address has been granted all roles for initial setup");

        // Log role information for reference
        bytes32 adminRole = token.ADMIN_ROLE();
        bytes32 managerRole = token.MANAGER_ROLE();
        bytes32 yieldManagerRole = token.YIELD_MANAGER_ROLE();
        bytes32 yieldDistributorRole = token.YIELD_DISTRIBUTOR_ROLE();

        // Print role hashes for reference when granting roles later
        console2.log("\n---------- ROLE MANAGEMENT ----------");
        console2.log("DEFAULT_ADMIN_ROLE:", uint256(DEFAULT_ADMIN_ROLE));
        console2.log("ADMIN_ROLE:", uint256(adminRole));
        console2.log("MANAGER_ROLE:", uint256(managerRole));
        console2.log("YIELD_MANAGER_ROLE:", uint256(yieldManagerRole));
        console2.log("YIELD_DISTRIBUTOR_ROLE:", uint256(yieldDistributorRole));

        console2.log("\n---------- ROLE PERMISSIONS ----------");
        console2.log("DEFAULT_ADMIN_ROLE: Manage role assignments (can grant/revoke any role)");
        console2.log("ADMIN_ROLE: Toggle transfer restrictions on/off");
        console2.log("MANAGER_ROLE: Permissions for general token management:");
        console2.log("  - Whitelist management (add/remove addresses to whitelist)");
        console2.log("  - Minting and burning tokens");
        console2.log("  - Asset management (update name, valuation)");
        console2.log("  - Metadata management (update token URI)");
        console2.log("  - Financial metrics management (update token price, accrual rate, etc.)");
        console2.log("YIELD_MANAGER_ROLE: Configure the yield token address");
        console2.log("YIELD_DISTRIBUTOR_ROLE: Distribute yield to token holders");

        console2.log("\n---------- ASSIGNING ADDITIONAL ROLES ----------");
        console2.log("To grant a role to another address, use the grantRole function:");
        console2.log(
            "Example: cast send TOKEN_ADDRESS \"grantRole(bytes32,address)\" ROLE_HASH NEW_ADDRESS --from ADMIN_ADDRESS"
        );

        vm.stopBroadcast();
    }

}
