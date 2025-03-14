// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { SpinProxy } from "../src/proxy/SpinProxy.sol";
import { DateTime } from "../src/spin/DateTime.sol";
import { Spin } from "../src/spin/Spin.sol";

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract UpgradeDevnetSpin is Script {

    address private constant SUPRA = 0x6D46C098996AD584c9C40D6b4771680f54cE3726;
    address constant ADMIN = 0xF5A6c4a29610722C84dC25222AF09FA81fAa4BDE;
    UUPSUpgradeable private constant PROXY_ADDRESS = UUPSUpgradeable(0x5cFADCC362b7696CEBAeD6aC7b9dC5Bdc6f8789c);

    function run() external {
        vm.startBroadcast(ADMIN);
        Spin spin = new Spin();

        PROXY_ADDRESS.upgradeToAndCall(address(spin), "");

        console2.log("Upgradeddeployed to:");

        vm.stopBroadcast();
    }

}
