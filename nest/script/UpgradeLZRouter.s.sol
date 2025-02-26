// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Script } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { LZRouter } from "../src/LZRouter.sol";
import { LZRouterProxy } from "../src/proxy/LZRouterProxy.sol";

contract UpgradeLZRouter is Script, Test {

    address private constant NEST_ADMIN_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;
    address private constant BORING_VAULT_ADDRESS = 0xe644F07B1316f28a7F134998e021eA9f7135F351;

    UUPSUpgradeable private constant LZROUTER_PROXY =
        UUPSUpgradeable(payable(0xa74296224113485c93330c1d4d5493B76c0E3A3f));

    function test() public { }

    function run() external {
        vm.startBroadcast(NEST_ADMIN_ADDRESS);

        // Deploy new implementation
        LZRouter newLZRouterimpl = new LZRouter();
        assertGt(address(newLZRouterimpl).code.length, 0, "newLZRouterimpl should be deployed");
        console2.log("New   Implementation deployed to:", address(newLZRouterimpl));

        // Upgrade to new implementation
        LZROUTER_PROXY.upgradeToAndCall(address(newLZRouterimpl), "");

        vm.stopBroadcast();
    }

}
