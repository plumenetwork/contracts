// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { MockPUSD } from "../src/mocks/MockPUSD.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title UpgradeMockPUSD
 * @notice Upgrades the MockPUSD implementation
 */
contract UpgradeMockPUSD is Script {

    // Replace with your actual proxy address after deployment
    address private constant PROXY_ADDRESS = 0x0000000000000000000000000000000000000000;
    // Admin address that has the authority to upgrade the contract
    address private constant ADMIN_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;

    function run() external {
        vm.startBroadcast(ADMIN_ADDRESS);

        // 1. Deploy new implementation
        MockPUSD newImplementation = new MockPUSD();
        console2.log("New MockPUSD Implementation deployed to:", address(newImplementation));

        // 2. Upgrade the proxy to point to the new implementation
        UUPSUpgradeable(PROXY_ADDRESS).upgradeToAndCall(
            address(newImplementation),
            "" // No additional initialization call for this upgrade
        );

        console2.log("Proxy upgraded to use new implementation");
        console2.log("\nUpgrade Configuration:");
        console2.log("------------------------");
        console2.log("Proxy Address:", PROXY_ADDRESS);
        console2.log("New Implementation:", address(newImplementation));
        console2.log("Admin:", ADMIN_ADDRESS);

        vm.stopBroadcast();
    }

}
