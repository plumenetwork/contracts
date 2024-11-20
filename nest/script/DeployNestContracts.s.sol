// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
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

    function test() public { }

    function run() external {
        vm.startBroadcast(NEST_ADMIN_ADDRESS);

        // Deploy pUSD
        pUSD pUSDToken = new pUSD();

        ERC1967Proxy pUSDProxy =
            new ERC1967Proxy(address(pUSDToken), abi.encodeCall(pUSD.initialize, (VAULT_ADDRESS, NEST_ADMIN_ADDRESS)));
        console2.log("pUSDProxy deployed to:", address(pUSDProxy));

        // Deploy ConcreteComponentToken
        ConcreteComponentToken componentToken = new ConcreteComponentToken();
        ERC1967Proxy componentTokenProxy = new ERC1967Proxy(
            address(componentToken),
            abi.encodeCall(
                ComponentToken.initialize,
                (
                    NEST_ADMIN_ADDRESS, // owner
                    "Banana", // name
                    "BAN", // symbol
                    IERC20(address(pUSDProxy)), // asset token
                    false, // async deposit
                    false // async redeem
                )
            )
        );
        console2.log("ComponentTokenProxy deployed to:", address(componentTokenProxy));

        // Deploy AggregateToken with both component tokens
        AggregateToken aggregateToken = new AggregateToken();
        AggregateTokenProxy aggregateTokenProxy = new AggregateTokenProxy(
            address(aggregateToken),
            abi.encodeCall(
                AggregateToken.initialize,
                (
                    NEST_ADMIN_ADDRESS,
                    "Apple",
                    "AAPL",
                    IComponentToken(address(pUSDProxy)),
                    1e17, // ask price
                    1e17 // bid price
                )
            )
        );
        console2.log("AggregateTokenProxy deployed to:", address(aggregateTokenProxy));

        // Add new component tokens
        AggregateToken(address(aggregateTokenProxy)).addComponentToken(IComponentToken(address(pUSDProxy)));
        AggregateToken(address(aggregateTokenProxy)).addComponentToken(IComponentToken(address(componentTokenProxy)));

        // Deploy NestStaking
        NestStaking nestStaking = new NestStaking();
        NestStakingProxy nestStakingProxy =
            new NestStakingProxy(address(nestStaking), abi.encodeCall(NestStaking.initialize, (NEST_ADMIN_ADDRESS)));
        console2.log("NestStakingProxy deployed to:", address(nestStakingProxy));

        vm.stopBroadcast();
    }

}
