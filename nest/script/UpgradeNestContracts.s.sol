// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Script } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { AggregateToken } from "../src/AggregateToken.sol";

import { IComponentToken } from "../src/interfaces/IComponentToken.sol";
import { AggregateTokenProxy } from "../src/proxy/AggregateTokenProxy.sol";

contract UpgradeNestContracts is Script, Test {

    address private constant NEST_ADMIN_ADDRESS = 0xb015762405De8fD24d29A6e0799c12e0Ea81c1Ff;
    address private constant BORING_VAULT_ADDRESS = 0xe644F07B1316f28a7F134998e021eA9f7135F351;
    address private constant LZ_ENDPOINT_ADDRESS = 0xb015762405De8fD24d29A6e0799c12e0Ea81c1Ff;
    address private constant LZ_DELEGATE_ADDRESS = 0xb015762405De8fD24d29A6e0799c12e0Ea81c1Ff;

    UUPSUpgradeable private constant AGGREGATE_TOKEN_PROXY =
        UUPSUpgradeable(payable(0x659619AEdf381c3739B0375082C2d61eC1fD8835));

    // Add the component token addresses
    address private constant ASSET_TOKEN = 0x2DEc3B6AdFCCC094C31a2DCc83a43b5042220Ea2;

    // LiquidContinuousMultiTokenVault - Credbull
    address private constant COMPONENT_TOKEN = 0x4B1fC984F324D2A0fDD5cD83925124b61175f5C6;

    function test() public { }

    function run() external {
        vm.startBroadcast(NEST_ADMIN_ADDRESS);

        // Deploy new implementation
        AggregateToken newAggregateTokenImpl =
            new AggregateToken(LZ_ENDPOINT_ADDRESS, LZ_DELEGATE_ADDRESS, NEST_ADMIN_ADDRESS);
        assertGt(address(newAggregateTokenImpl).code.length, 0, "AggregateToken should be deployed");
        console2.log("New AggregateToken Implementation deployed to:", address(newAggregateTokenImpl));

        // Upgrade to new implementation
        AGGREGATE_TOKEN_PROXY.upgradeToAndCall(address(newAggregateTokenImpl), "");

        // Get the upgraded contract instance
        AggregateToken aggregateToken = AggregateToken(address(AGGREGATE_TOKEN_PROXY));

        // Add component tokens if they're not already in the list
        if (!aggregateToken.getComponentToken(IComponentToken(ASSET_TOKEN))) {
            aggregateToken.addComponentToken(IComponentToken(ASSET_TOKEN));
            console2.log("Added ASSET_TOKEN to component list");
        }

        if (!aggregateToken.getComponentToken(IComponentToken(COMPONENT_TOKEN))) {
            aggregateToken.addComponentToken(IComponentToken(COMPONENT_TOKEN));
            console2.log("Added CREDBULL_COMPONENT_TOKEN to component list");
        }

        vm.stopBroadcast();

        // Verify the component tokens are in the list
        IComponentToken[] memory tokens = aggregateToken.getComponentTokenList();
        console2.log("Number of component tokens:", tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            console2.log("Component token", i, ":", address(tokens[i]));
        }
    }

}
