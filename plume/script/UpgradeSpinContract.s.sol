// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { Options } from "openzeppelin-foundry-upgrades/Options.sol";

import { Spin } from "../src/spin/Spin.sol";

contract UpgradeSpinContract is Script {
    string private BLOCKSCOUT_URL;

    function run() external {
        // Load private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Load proxy address from environment (required)
        address spinProxyAddress = vm.envAddress("SPIN_PROXY_ADDRESS");
        
        // Get chain ID and deployer address
        uint256 chainId = block.chainid;
        address deployerAddress = vm.addr(deployerPrivateKey);
        
        console2.log("Upgrading Spin contract");
        console2.log("Deployer:", deployerAddress);
        console2.log("Chain ID:", chainId);
        console2.log("Proxy Address:", spinProxyAddress);

        vm.startBroadcast(deployerPrivateKey);

        // Create options with reference contract
        Options memory opts;
        opts.referenceContract = "Spin.sol:Spin";
        opts.unsafeSkipStorageCheck = true;
        opts.unsafeSkipAllChecks = true;
        opts.unsafeAllowRenames = true;

        // Upgrade the proxy using OpenZeppelin's Upgrades library
        Upgrades.upgradeProxy(
            spinProxyAddress,
            "Spin.sol:Spin",
            "", // No initialization data needed for upgrade
            opts
        );
        
        // Print verification command for Blockscout
        BLOCKSCOUT_URL = vm.envOr("BLOCKSCOUT_URL", string("https://phoenix-explorer.plumenetwork.xyz/api?"));
        
        console2.log("\n--- Blockscout Verification Command ---");
        console2.log("New implementation verification:");
        console2.log(string.concat(
            "forge verify-contract <NEW_IMPLEMENTATION_ADDRESS>",
            " src/spin/Spin.sol:Spin",
            " --chain-id ",
            vm.toString(chainId),
            " --verifier blockscout",
            " --verifier-url ",
            BLOCKSCOUT_URL
        ));

        vm.stopBroadcast();
    }
}