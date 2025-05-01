// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { DateTime } from "../src/spin/DateTime.sol";

contract DeployDateTimeContract is Script {
    string private BLOCKSCOUT_URL;

    function run() external {
        // Load private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Set blockscout URL from environment or use default
        BLOCKSCOUT_URL = vm.envOr("BLOCKSCOUT_URL", string("https://phoenix-explorer.plumenetwork.xyz/api?"));
        
        // Get chain ID
        uint256 chainId = block.chainid;
        
        // Get deployer address from private key
        address deployerAddress = vm.addr(deployerPrivateKey);
        console2.log("Deploying from:", deployerAddress);
        console2.log("Chain ID:", chainId);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy DateTime contract
        DateTime dateTime = new DateTime();
        console2.log("DateTime contract deployed to:", address(dateTime));

        // Print verification command for Blockscout
        console2.log("\n--- Blockscout Verification Command ---");
        console2.log("DateTime contract verification:");
        console2.log(string.concat(
            "forge verify-contract --chain-id ", 
            vm.toString(chainId), 
            " --verifier blockscout --verifier-url ", 
            BLOCKSCOUT_URL, 
            " ", 
            vm.toString(address(dateTime)), 
            " src/spin/DateTime.sol:DateTime"
        ));

        vm.stopBroadcast();
    }
}