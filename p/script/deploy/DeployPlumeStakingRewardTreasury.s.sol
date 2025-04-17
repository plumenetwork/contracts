// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script, console2 } from "forge-std/Script.sol";

import { PlumeStakingRewardTreasury } from "../../src/PlumeStakingRewardTreasury.sol";
import { PlumeStakingRewardTreasuryProxy } from "../../src/proxy/PlumeStakingRewardTreasuryProxy.sol";

contract DeployPlumeStakingRewardTreasury is Script {

    // Configuration
    address private constant ADMIN = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;
    address private constant PLUME_STAKING = 0xA20bfe49969D4a0E9abfdb6a46FeD777304ba07f; // TODO: Replace with actual
        // address

    function run() external {
        // Use admin for deployment
        vm.startBroadcast(ADMIN);

        // 1. Deploy Implementation
        console2.log("Deploying PlumeStakingRewardTreasury implementation...");
        PlumeStakingRewardTreasury implementation = new PlumeStakingRewardTreasury();
        console2.log("Implementation deployed at:", address(implementation));

        // 2. Prepare initialization data
        bytes memory initData =
            abi.encodeWithSelector(PlumeStakingRewardTreasury.initialize.selector, ADMIN, PLUME_STAKING);

        // 3. Deploy Proxy
        console2.log("Deploying PlumeStakingRewardTreasuryProxy...");
        PlumeStakingRewardTreasuryProxy proxy = new PlumeStakingRewardTreasuryProxy(address(implementation), initData);
        console2.log("Proxy deployed at:", address(proxy));

        // 4. Log deployment addresses
        console2.log("\nDeployment Summary:");
        console2.log("--------------------");
        console2.log("Implementation:", address(implementation));
        console2.log("Proxy:", address(proxy));
        console2.log("Admin:", ADMIN);
        console2.log("PlumeStaking (Distributor):", PLUME_STAKING);

        vm.stopBroadcast();
    }

}
