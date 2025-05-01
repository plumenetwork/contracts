// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Plume } from "../../src/Plume.sol";
import { PlumeStaking } from "../../src/PlumeStaking.sol";
import { PlumeStakingProxy } from "../../src/proxy/PlumeStakingProxy.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Script } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

contract UpgradePlumeStaking is Script, Test {

    address private constant ADMIN_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;

    UUPSUpgradeable private constant PLUMESTAKING_PROXY =
        UUPSUpgradeable(payable(0x79AA1340f7EA4E38567353E3af4d82ea6C0b5E00));

    function test() public { }

    function run() external {
        vm.startBroadcast(ADMIN_ADDRESS);

        // Deploy new implementation
        PlumeStaking newPlumeStakingImpl = new PlumeStaking();
        console2.log("New PlumeStaking Implementation deployed to:", address(newPlumeStakingImpl));

        // Upgrade to new implementation
        PLUMESTAKING_PROXY.upgradeToAndCall(address(newPlumeStakingImpl), "");
        console2.log("Successfully upgraded PlumeStaking implementation");

        vm.stopBroadcast();
    }

}
