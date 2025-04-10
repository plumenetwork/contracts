// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { SpinInternalProxy } from "../src/proxy/SpinInternalProxy.sol";
import { DateTime } from "../src/spin/DateTime.sol";
import { SpinInternal } from "../src/spin/SpinInternal.sol";

import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract DeployDevnetSpin is Script {

    address private constant SUPRA = 0xE1062AC81e76ebd17b1e283CEed7B9E8B2F749A5;
    address constant ADMIN = 0x656625D42167068796B3665763D4Ed756df65Dc6;
    //address private constant DATETIME = 0x9F0001FE8b5Dde5DF9b4c85819a4b0f04f5c273a;

    function run() external {
        vm.startBroadcast(ADMIN);

        DateTime datetime = new DateTime();

        SpinInternal spin = new SpinInternal();

        SpinInternalProxy spinproxy =
            new SpinInternalProxy(address(spin), abi.encodeCall(SpinInternal.initialize, (SUPRA, address(datetime))));
        console2.log("Spin Proxy deployed to:", address(spinproxy));

        vm.stopBroadcast();
    }

}
