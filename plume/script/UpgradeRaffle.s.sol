// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { RaffleProxy } from "../src/proxy/RaffleProxy.sol";
import { Raffle } from "../src/spin/Raffle.sol";

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract UpgradeDevnetRaffle is Script {

    address private constant SUPRA = 0x6D46C098996AD584c9C40D6b4771680f54cE3726;
    address constant ADMIN = 0xF5A6c4a29610722C84dC25222AF09FA81fAa4BDE;
    UUPSUpgradeable private constant PROXY_ADDRESS = UUPSUpgradeable(0x04dcE5e65aB02975bc50418371a6b1f9f91101F8);

    function run() external {
        vm.startBroadcast(ADMIN);
        Raffle raffle = new Raffle();

        PROXY_ADDRESS.upgradeToAndCall(address(raffle), "");

        console2.log("Upgradeddeployed to:");

        vm.stopBroadcast();
    }

}
