// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { SpinProxy } from "../src/proxy/SpinProxy.sol";
import { DateTime } from "../src/spin/DateTime.sol";
import { Spin } from "../src/spin/Spin.sol";

import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract DeployDevnetSpin is Script {

    address private constant SUPRA = 0x6D46C098996AD584c9C40D6b4771680f54cE3726;
    address constant ADMIN = 0xF5A6c4a29610722C84dC25222AF09FA81fAa4BDE;

    function run() external {
        vm.startBroadcast(ADMIN);

        DateTime datetime = new DateTime();

        Spin spin = new Spin();

        SpinProxy spinproxy =
            new SpinProxy(address(spin), abi.encodeCall(Spin.initialize, (SUPRA, address(datetime), 5)));
        console2.log("Spin Proxy deployed to:", address(spinproxy));

        vm.stopBroadcast();
    }

}
