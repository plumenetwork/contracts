// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Script } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { AggregateToken } from "../src/AggregateToken.sol";
import { ComponentToken } from "../src/ComponentToken.sol";
import { NestStaking } from "../src/NestStaking.sol";
import { IComponentToken } from "../src/interfaces/IComponentToken.sol";
import { AggregateTokenProxy } from "../src/proxy/AggregateTokenProxy.sol";
import { NestStakingProxy } from "../src/proxy/NestStakingProxy.sol";

import { pUSDProxy } from "../src/proxy/pUSDProxy.sol";
import { pUSD } from "../src/token/pUSD.sol";

// Concrete implementation of ComponentToken
contract ConcreteComponentToken is ComponentToken {

    // Implement the required abstract functions
    function convertToShares(
        uint256 assets
    ) public view override returns (uint256) {
        return assets; // 1:1 conversion
    }

    function convertToAssets(
        uint256 shares
    ) public view override returns (uint256) {
        return shares; // 1:1 conversion
    }

}

contract DeployNestContracts is Script, Test {

    address private constant NEST_ADMIN_ADDRESS = 0xb015762405De8fD24d29A6e0799c12e0Ea81c1Ff;
    address private constant VAULT_ADDRESS = 0x52805adf7b3d25c013eDa66eF32b53d1696f809C;
    address private constant PUSD_ADDRESS = 0x2DEc3B6AdFCCC094C31a2DCc83a43b5042220Ea2;

    function test() public { }

    function run() external {
        vm.startBroadcast(NEST_ADMIN_ADDRESS);

        AggregateToken aggregateToken = new AggregateToken();
        AggregateTokenProxy aggregateTokenProxy = new AggregateTokenProxy(
            address(aggregateToken),
            abi.encodeCall(
                AggregateToken.initialize,
                (
                    NEST_ADMIN_ADDRESS,
                    "Nest RWA Vault",
                    "nRWA",
                    IComponentToken(PUSD_ADDRESS),
                    1e17, // ask price
                    1e17 // bid price
                )
            )
        );
        console2.log("AggregateTokenProxy deployed to:", address(aggregateTokenProxy));

        vm.stopBroadcast();
    }

}
