// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Script } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { AggregateToken } from "../src/AggregateToken.sol";
import { AggregateTokenProxy } from "../src/proxy/AggregateTokenProxy.sol";

contract UpgradeNestContracts is Script, Test {

    address private constant NEST_ADMIN_ADDRESS = 0xb015762405De8fD24d29A6e0799c12e0Ea81c1Ff;
    UUPSUpgradeable private constant AGGREGATE_TOKEN_PROXY =
        UUPSUpgradeable(payable(0x659619AEdf381c3739B0375082C2d61eC1fD8835));

    function test() public { }

    function run() external {
        vm.startBroadcast(NEST_ADMIN_ADDRESS);

        AggregateToken newAggregateTokenImpl = new AggregateToken();
        assertGt(address(newAggregateTokenImpl).code.length, 0, "AggregateToken should be deployed");
        console2.log("New AggregateToken Implementation deployed to:", address(newAggregateTokenImpl));

        AGGREGATE_TOKEN_PROXY.upgradeToAndCall(address(newAggregateTokenImpl), "");

        vm.stopBroadcast();
    }

}
