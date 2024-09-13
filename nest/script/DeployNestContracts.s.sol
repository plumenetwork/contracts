// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

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

        vm.stopBroadcast();
    }

}
