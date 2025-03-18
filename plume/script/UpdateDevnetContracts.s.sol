// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { Faucet } from "../src/Faucet.sol";
import { FaucetProxy } from "../src/proxy/FaucetProxy.sol";

/**
 * @title UpdateDevnetContracts
 * @notice Script to upgrade the implementation of existing proxy contracts on devnet
 */
contract UpdateDevnetContracts is Script {

    // Constants
    address private constant ADMIN_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;
    address private constant FAUCET_PROXY_ADDRESS = 0x81A7A4Ece4D161e720ec602Ad152a7026B82448b;
    address private constant ETH_ADDRESS = address(1);

    function run() external {
        vm.startBroadcast(ADMIN_ADDRESS);

        // Deploy new implementation
        Faucet newFaucetImplementation = new Faucet();
        console2.log("New Faucet implementation deployed to:", address(newFaucetImplementation));

        // Get proxy interface to call the upgrade function
        Faucet faucet = Faucet(payable(FAUCET_PROXY_ADDRESS));

        // Upgrade to the new implementation
        faucet.upgradeToAndCall(address(newFaucetImplementation), "");
        console2.log(
            "Faucet proxy at", FAUCET_PROXY_ADDRESS, "upgraded to implementation:", address(newFaucetImplementation)
        );

        vm.stopBroadcast();
    }

}
