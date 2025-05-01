// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { Options } from "openzeppelin-foundry-upgrades/Options.sol";

import { Raffle } from "../src/spin/Raffle.sol";

contract UpgradeRaffleContract is Script {
    string private BLOCKSCOUT_URL;

    function run() external {
        // Load private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Load proxy address from environment (required)
        address raffleProxyAddress = vm.envAddress("RAFFLE_PROXY_ADDRESS");
        
        // Get chain ID and deployer address
        uint256 chainId = block.chainid;
        address deployerAddress = vm.addr(deployerPrivateKey);
        
        console2.log("Upgrading Raffle contract");
        console2.log("Deployer:", deployerAddress);
        console2.log("Chain ID:", chainId);
        console2.log("Proxy Address:", raffleProxyAddress);

        vm.startBroadcast(deployerPrivateKey);

        // Create options with reference contract
        Options memory opts;
        opts.referenceContract = "Raffle.sol:Raffle";
        opts.unsafeSkipStorageCheck = true;
        opts.unsafeSkipAllChecks = true;
        opts.unsafeAllowRenames = true;

        // Upgrade the proxy using OpenZeppelin's Upgrades library
        Upgrades.upgradeProxy(
            raffleProxyAddress,
            "Raffle.sol:Raffle",
            "", // No initialization data needed for upgrade
            opts
        );

        // Print verification command for Blockscout
        BLOCKSCOUT_URL = vm.envOr("BLOCKSCOUT_URL", string("https://phoenix-explorer.plumenetwork.xyz/api?"));
        
        console2.log("\n--- Blockscout Verification Command ---");
        console2.log("To verify the new implementation, first get the new implementation address from the proxy and then run:");
        console2.log("forge verify-contract <NEW_IMPLEMENTATION_ADDRESS> src/spin/Raffle.sol:Raffle \\");
        console2.log("    --chain-id ", chainId, " \\");
        console2.log("    --verifier blockscout \\");
        console2.log("    --verifier-url ", BLOCKSCOUT_URL);

        vm.stopBroadcast();
    }
}