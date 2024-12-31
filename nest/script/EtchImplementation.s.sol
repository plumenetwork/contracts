// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { AggregateToken } from "../src/AggregateToken.sol";
import { IComponentToken } from "../src/interfaces/IComponentToken.sol";

contract EtchImplementation is Script, Test {
    // Constants
    address constant PLUME_NRWA = address(0x4dA57055E62D8c5a7fD3832868DcF3817b99C959); 
    address constant PLUME_RECEIVER = address(0x04354e44ed31022716e77eC6320C04Eda153010c);
    
    // Component token addresses
    address constant USDC_TOKEN = address(0x3938A812c54304fEffD266C7E2E70B48F9475aD6);

    function test() public { }

    function run() external {
        vm.startBroadcast();

        // Deploy new implementation
        AggregateToken implementation = new AggregateToken();
        assertGt(address(implementation).code.length, 0, "AggregateToken should be deployed");
        console2.log("New AggregateToken Implementation deployed to:", address(implementation));

        // Etch the implementation bytecode at the PLUME_NRWA address
        vm.etch(PLUME_NRWA, address(implementation).code);
        console2.log("Implementation bytecode etched at:", PLUME_NRWA);

        // Get the etched contract instance
       // AggregateToken nRWA = AggregateToken(PLUME_NRWA);
/*
        // Initialize if needed
            nRWA.initialize(
                "Plume nRWA",     // name
                "nRWA",           // symbol
                PLUME_RECEIVER    // admin
            );
            console2.log("nRWA token initialized");
 */
        // Add component tokens if they're not already in the list

       
        vm.stopBroadcast();

        // Verify the component tokens are in the list
        IComponentToken[] memory tokens = nRWA.getComponentTokenList();
        console2.log("Number of component tokens:", tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            console2.log("Component token", i, ":", address(tokens[i]));
        }
    }
}