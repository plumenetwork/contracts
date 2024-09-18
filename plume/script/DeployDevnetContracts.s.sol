// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

import { pUSD } from "../src/pUSD.sol";

contract DeployScript is Script {

    address private constant ADMIN_ADDRESS = 0xbeC8320D84789b91AE30f2d13402CD2037494Dd1;

    function run() external {
        vm.startBroadcast(ADMIN_ADDRESS);

        pUSD pusd = new pUSD(ADMIN_ADDRESS);
        console.log("pUSD deployed to:", address(pusd));

        vm.stopBroadcast();
    }

}
