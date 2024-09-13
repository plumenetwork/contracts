// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

import { AggregateToken } from "../src/AggregateToken.sol";
import { FakeComponentToken } from "../src/FakeComponentToken.sol";

contract DeployNestContracts is Script {

    address private constant ARC_ADMIN_ADDRESS = 0x1c9d94FAD4ccCd522804a955103899e0D6A4405a;
    address private constant USDC_ADDRESS = 0x849c25e6cCB03cdc23ba91d92440dA7bC8486be2;

    function run() external {
        vm.startBroadcast(ARC_ADMIN_ADDRESS);

        address fakeComponentTokenProxy = Upgrades.deployUUPSProxy(
            "FakeComponentToken.sol",
            abi.encodeCall(FakeComponentToken.initialize, (msg.sender, "Banana", "BAN", IERC20(USDC_ADDRESS), 18))
        );
        console.log("FakeComponentToken deployed to:", fakeComponentTokenProxy);

        address aggregateTokenProxy = Upgrades.deployUUPSProxy(
            "AggregateToken.sol",
            abi.encodeCall(
                AggregateToken.initialize,
                (
                    msg.sender,
                    "Apple",
                    "AAPL",
                    IERC20(USDC_ADDRESS),
                    18,
                    15e17,
                    12e17,
                    "https://assets.plumenetwork.xyz/metadata/mineral-vault.json"
                )
            )
        );
        console.log("AggregateToken deployed to:", aggregateTokenProxy);

        vm.stopBroadcast();
    }

}
