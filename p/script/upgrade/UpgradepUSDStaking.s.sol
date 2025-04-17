// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Plume } from "../../src/Plume.sol";
import { pUSDStaking } from "../../src/pUSDStaking.sol";
import { pUSDStakingProxy } from "../../src/proxy/pUSDStakingProxy.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Script } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

contract UpgradepUSDStaking is Script, Test {

    address private constant ADMIN_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;

    UUPSUpgradeable private constant PUSDSTAKING_PROXY =
        UUPSUpgradeable(payable(0x0630e14dABDb05Ca6d9A1Be40c6F996855e9c2cb));

    function test() public { }

    function run() external {
        vm.startBroadcast(ADMIN_ADDRESS);

        // Deploy new implementation
        pUSDStaking newpUSDStakingImpl = new pUSDStaking();
        console2.log("New PlumeStaking Implementation deployed to:", address(newpUSDStakingImpl));

        // Upgrade to new implementation
        PUSDSTAKING_PROXY.upgradeToAndCall(address(newpUSDStakingImpl), "");

        vm.stopBroadcast();
    }

}
