// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { Script, console2 } from "forge-std/Script.sol";

import { PlumeStakingRewardTreasury } from "../src/PlumeStakingRewardTreasury.sol";

contract UpgradePlumeStakingRewardTreasury is Script {

    // Configuration
    address private constant ADMIN = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;
    address private constant PROXY = 0x0000000000000000000000000000000000000000; // TODO: Replace with actual proxy
        // address

    function run() external {
        // Use admin for upgrade
        vm.startBroadcast(ADMIN);

        // 1. Deploy new implementation
        console2.log("Deploying new PlumeStakingRewardTreasury implementation...");
        PlumeStakingRewardTreasury newImplementation = new PlumeStakingRewardTreasury();
        console2.log("New implementation deployed at:", address(newImplementation));

        // 2. Upgrade proxy to new implementation
        console2.log("Upgrading proxy to new implementation...");
        ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(PROXY);
        proxy.upgradeToAndCall(address(newImplementation), "");
        console2.log("Proxy upgraded successfully");

        // 3. Log upgrade summary
        console2.log("\nUpgrade Summary:");
        console2.log("---------------");
        console2.log("New Implementation:", address(newImplementation));
        console2.log("Proxy:", PROXY);
        console2.log("Admin:", ADMIN);

        vm.stopBroadcast();
    }

}
