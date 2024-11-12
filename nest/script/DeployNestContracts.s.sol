// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";

import { AggregateToken } from "../src/AggregateToken.sol";
import { ComponentToken } from "../src/ComponentToken.sol";
import { NestStaking } from "../src/NestStaking.sol";
import { IComponentToken } from "../src/interfaces/IComponentToken.sol";
import { AggregateTokenProxy } from "../src/proxy/AggregateTokenProxy.sol";
import { NestStakingProxy } from "../src/proxy/NestStakingProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Concrete implementation of ComponentToken
contract ConcreteComponentToken is ComponentToken {
    // Implement the required abstract functions
    function convertToShares(uint256 assets) public view override returns (uint256) {
        return assets; // 1:1 conversion
    }

    function convertToAssets(uint256 shares) public view override returns (uint256) {
        return shares; // 1:1 conversion
    }
}

contract DeployNestContracts is Script {
    address private constant ARC_ADMIN_ADDRESS = 0x1c9d94FAD4ccCd522804a955103899e0D6A4405a;
    address private constant NEST_ADMIN_ADDRESS = 0xb015762405De8fD24d29A6e0799c12e0Ea81c1Ff;
    address private constant P_ADDRESS = 0xEa0c23A2411729073Ed52fF94b38FceffE82FDE3;

    function run() external {
        vm.startBroadcast(ARC_ADMIN_ADDRESS);

        // Cast P_ADDRESS to IERC20 for ComponentToken
        IERC20 currencyTokenERC20 = IERC20(P_ADDRESS);
        // Keep IComponentToken version for AggregateToken
        IComponentToken currencyToken = IComponentToken(P_ADDRESS);

        // Deploy ConcreteComponentToken
        ConcreteComponentToken componentToken = new ConcreteComponentToken();
        ERC1967Proxy componentTokenProxy = new ERC1967Proxy(
            address(componentToken),
            abi.encodeCall(
                ComponentToken.initialize,
                (
                    ARC_ADMIN_ADDRESS,    // owner
                    "Banana",             // name
                    "BAN",               // symbol
                    currencyTokenERC20,   // asset token
                    false,               // async deposit
                    false                // async redeem
                )
            )
        );
        console.log("ComponentTokenProxy deployed to:", address(componentTokenProxy));

        // Deploy AggregateToken with IComponentToken
        AggregateToken aggregateToken = new AggregateToken();
        AggregateTokenProxy aggregateTokenProxy = new AggregateTokenProxy(
            address(aggregateToken),
            abi.encodeCall(
                AggregateToken.initialize,
                (
                    NEST_ADMIN_ADDRESS,
                    "Apple",
                    "AAPL",
                    currencyToken,
                    1e18, // ask price
                    1e18  // bid price
                )
            )
        );
        console.log("AggregateTokenProxy deployed to:", address(aggregateTokenProxy));

        // Deploy NestStaking
        NestStaking nestStaking = new NestStaking();
        NestStakingProxy nestStakingProxy =
            new NestStakingProxy(address(nestStaking), abi.encodeCall(NestStaking.initialize, (NEST_ADMIN_ADDRESS)));
        console.log("NestStakingProxy deployed to:", address(nestStakingProxy));

        vm.stopBroadcast();
    }
}