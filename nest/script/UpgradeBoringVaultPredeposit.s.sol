// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { Script } from "forge-std/Script.sol";

import { BoringVaultPredeposit } from "../src/BoringVaultPredeposit.sol";
import { BoringVaultPredepositProxy } from "../src/proxy/BoringVaultPredepositProxy.sol";

import { console2 } from "forge-std/console2.sol";

contract UpgradeBoringVaultPredeposit is Script {

    // Configuration
    address private constant ADMIN = address(0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5);

    // Existing proxy address that needs to be upgraded
        UUPSUpgradeable private constant BORINGVAULT_PREDEPOSIT_PROXY = UUPSUpgradeable(payable(0xF4A8D1680D189aE460840CA8946B9Df688e2b5B3));

    function run() external {
        vm.startBroadcast(ADMIN);

        // 1. Deploy implementation
        BoringVaultPredeposit newImplementation = new BoringVaultPredeposit();
        console2.log("New implementation deployed to:", address(newImplementation));

        // 2. Upgrade proxy to point to new implementation
        BORINGVAULT_PREDEPOSIT_PROXY.upgradeToAndCall(address(newImplementation), "");


        vm.stopBroadcast();

        // Log upgrade details
        console2.log("Proxy upgraded successfully");
        console2.log("Proxy address:", address(BORINGVAULT_PREDEPOSIT_PROXY));
        console2.log("New implementation:", address(newImplementation));
    }

}
