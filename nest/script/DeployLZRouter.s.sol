// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { LZRouter } from "../src/LZRouter.sol";
import { LZRouterProxy } from "../src/proxy/LZRouterProxy.sol";
import { Script } from "forge-std/Script.sol";

contract DeployLZRouter is Script {

    function run() external {
        vm.startBroadcast();

        // Deploy implementation
        LZRouter implementation = new LZRouter();

        // Encode initialization data
        bytes memory data = abi.encodeWithSelector(
            LZRouter.initialize.selector,
            address(0x6F475642a6e85809B1c36Fa62763669b1b48DD5B) // Replace with actual LZ endpoint address
        );

        // Deploy proxy
        LZRouterProxy proxy = new LZRouterProxy(address(implementation), data);

        vm.stopBroadcast();
    }

}
