// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AggregateToken } from "../src/AggregateToken.sol";
import { FakeComponentToken } from "../src/FakeComponentToken.sol";
import { NestStaking } from "../src/NestStaking.sol";
import { AggregateTokenProxy } from "../src/proxy/AggregateTokenProxy.sol";
import { FakeComponentTokenProxy } from "../src/proxy/FakeComponentTokenProxy.sol";
import { NestStakingProxy } from "../src/proxy/NestStakingProxy.sol";

contract DeployNestContracts is Script {

    address private constant ARC_ADMIN_ADDRESS = 0x1c9d94FAD4ccCd522804a955103899e0D6A4405a;
    address private constant NEST_ADMIN_ADDRESS = 0xb015762405De8fD24d29A6e0799c12e0Ea81c1Ff;
    address private constant USDC_ADDRESS = 0x849c25e6cCB03cdc23ba91d92440dA7bC8486be2;

    function run() external {
        vm.startBroadcast(ARC_ADMIN_ADDRESS);

        FakeComponentToken fakeComponentToken = new FakeComponentToken();
        FakeComponentTokenProxy fakeComponentTokenProxy = new FakeComponentTokenProxy(
            address(fakeComponentToken),
            abi.encodeCall(
                FakeComponentToken.initialize, (ARC_ADMIN_ADDRESS, "Banana", "BAN", IERC20(USDC_ADDRESS), 18)
            )
        );
        console.log("FakeComponentTokenProxy deployed to:", address(fakeComponentTokenProxy));

        AggregateToken aggregateToken = new AggregateToken();
        AggregateTokenProxy aggregateTokenProxy = new AggregateTokenProxy(
            address(aggregateToken),
            abi.encodeCall(
                AggregateToken.initialize,
                (
                    NEST_ADMIN_ADDRESS,
                    "Apple",
                    "AAPL",
                    USDC_ADDRESS,
                    18,
                    15e17,
                    12e17,
                    "https://assets.plumenetwork.xyz/metadata/mineral-vault.json"
                )
            )
        );
        console.log("AggregateTokenProxy deployed to:", address(aggregateTokenProxy));

        NestStaking nestStaking = new NestStaking();
        NestStakingProxy nestStakingProxy =
            new NestStakingProxy(address(nestStaking), abi.encodeCall(NestStaking.initialize, (NEST_ADMIN_ADDRESS)));
        console.log("NestStakingProxy deployed to:", address(nestStakingProxy));

        vm.stopBroadcast();
    }

}
