// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { RoycoNestMarketHelper } from "../src/RoycoNestMarketHelper.sol";
import { RoycoMarketHelperProxy } from "../src/proxy/RoycoMarketHelperProxy.sol";

contract DeployRoycoMarketHelper is Script, Test {

    // Configuration variables - replace with your own values
    address private constant ADMIN_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;
    address private constant ATOMIC_QUEUE_ADDRESS = 0x228C44Bb4885C6633F4b6C83f14622f37D5112E5;

    // Test function to satisfy forge test requirement
    function test() public { }

    function run() external {
        // Start broadcasting transactions
        vm.startBroadcast(ADMIN_ADDRESS);

        // Deploy the implementation contract
        RoycoNestMarketHelper implementation = new RoycoNestMarketHelper();
        console2.log("RoycoNestMarketHelper implementation deployed to:", address(implementation));

        // Prepare the initialization data
        bytes memory initData = abi.encodeCall(RoycoNestMarketHelper.initialize, (ATOMIC_QUEUE_ADDRESS));

        // Deploy the custom proxy with the implementation and initialization data
        RoycoMarketHelperProxy proxy = new RoycoMarketHelperProxy(address(implementation), initData);

        // Log the proxy address
        console2.log("RoycoMarketHelperProxy deployed to:", address(proxy));

        // Get an instance of the proxy as RoycoNestMarketHelper to perform initialization tasks
        RoycoNestMarketHelper helper = RoycoNestMarketHelper(payable(address(proxy)));

        // Configure initial vaults if needed
        // For example:
        /*
        helper.addVault(
            "nelixir",
            0x1234..., // teller
            0x2345..., // vault
            0x3456..., // accountant
            50,        // 0.5% slippage
            0          // 0% performance fee
        );
        */

        // Configure atomic parameters
        helper.updateAtomicParameters(
            address(0), // Keep existing atomic queue
            3600, // 1 hour deadline
            9900 // 98% price (2% discount)
        );

        // Log implementation verification
        console2.log("Implementation verification can be done manually by checking storage slot");
        console2.log("Expected implementation:", address(implementation));

        // Log completion
        console2.log("RoycoNestMarketHelper deployment and configuration complete");

        // Stop broadcasting transactions
        vm.stopBroadcast();
    }

}
