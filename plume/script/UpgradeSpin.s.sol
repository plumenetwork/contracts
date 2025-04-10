// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { SpinInternalProxy } from "../src/proxy/SpinInternalProxy.sol";
import { DateTime } from "../src/spin/DateTime.sol";
import { SpinInternal } from "../src/spin/SpinInternal.sol";

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract UpgradeDevnetSpin is Script {

    address private constant SUPRA = 0x6D46C098996AD584c9C40D6b4771680f54cE3726;
    address constant ADMIN = 0xF5A6c4a29610722C84dC25222AF09FA81fAa4BDE;
    UUPSUpgradeable private constant PROXY_ADDRESS = UUPSUpgradeable(0x39ee53F96b576110e13189f7ED064333116df389);

    function run() external {
        vm.startBroadcast(ADMIN);
        SpinInternal spin = new SpinInternal();

        PROXY_ADDRESS.upgradeToAndCall(address(spin), "");

        console2.log("Upgradeddeployed to:");

        vm.stopBroadcast();
    }

}
