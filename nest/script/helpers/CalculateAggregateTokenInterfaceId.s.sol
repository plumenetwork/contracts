// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IAggregateToken } from "../../src/interfaces/IAggregateToken.sol";
import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

contract CalculateAggregateTokenInterfaceId is Script {

    function run() public view {
        bytes4 interfaceId = calculateInterfaceId();

        // Log results
        console2.log("\nIAggregateToken Interface ID Calculation Results:");
        console2.log("----------------------------------------");
        console2.log("Interface ID: ", vm.toString(interfaceId));

        // Log individual function selectors
        logFunctionSelectors();
    }

    function calculateInterfaceId() public pure returns (bytes4) {
        // Split calculations into groups to avoid stack too deep
        bytes4 group1 = calculateGroup1();
        bytes4 group2 = calculateGroup2();
        bytes4 group3 = calculateGroup3();

        return group1 ^ group2 ^ group3;
    }

    function calculateGroup1() public pure returns (bytes4) {
        return bytes4(
            keccak256("approveComponentToken(address,uint256)") ^ keccak256("addComponentToken(address)")
                ^ keccak256("buyComponentToken(address,uint256)") ^ keccak256("sellComponentToken(address,uint256)")
        );
    }

    function calculateGroup2() public pure returns (bytes4) {
        return bytes4(
            keccak256("requestBuyComponentToken(address,uint256)")
                ^ keccak256("requestSellComponentToken(address,uint256)") ^ keccak256("setAskPrice(uint256)")
                ^ keccak256("setBidPrice(uint256)")
        );
    }

    function calculateGroup3() public pure returns (bytes4) {
        return bytes4(
            keccak256("pause()") ^ keccak256("unpause()") ^ keccak256("getAskPrice()") ^ keccak256("getBidPrice()")
                ^ keccak256("getComponentTokenList()") ^ keccak256("isPaused()") ^ keccak256("getComponentToken(address)")
        );
    }

    function logFunctionSelectors() public pure {
        console2.log("\nFunction Selectors:");
        console2.log("----------------------------------------");
        console2.log(
            "approveComponentToken:    ", vm.toString(bytes4(keccak256("approveComponentToken(address,uint256)")))
        );
        console2.log("addComponentToken:        ", vm.toString(bytes4(keccak256("addComponentToken(address)"))));
        console2.log("buyComponentToken:        ", vm.toString(bytes4(keccak256("buyComponentToken(address,uint256)"))));
        console2.log(
            "sellComponentToken:       ", vm.toString(bytes4(keccak256("sellComponentToken(address,uint256)")))
        );
        console2.log(
            "requestBuyComponentToken: ", vm.toString(bytes4(keccak256("requestBuyComponentToken(address,uint256)")))
        );
        console2.log(
            "requestSellComponentToken:", vm.toString(bytes4(keccak256("requestSellComponentToken(address,uint256)")))
        );
        console2.log("setAskPrice:             ", vm.toString(bytes4(keccak256("setAskPrice(uint256)"))));
        console2.log("setBidPrice:             ", vm.toString(bytes4(keccak256("setBidPrice(uint256)"))));
        console2.log("pause:                   ", vm.toString(bytes4(keccak256("pause()"))));
        console2.log("unpause:                 ", vm.toString(bytes4(keccak256("unpause()"))));
        console2.log("getAskPrice:             ", vm.toString(bytes4(keccak256("getAskPrice()"))));
        console2.log("getBidPrice:             ", vm.toString(bytes4(keccak256("getBidPrice()"))));
        console2.log("getComponentTokenList:    ", vm.toString(bytes4(keccak256("getComponentTokenList()"))));
        console2.log("isPaused:                ", vm.toString(bytes4(keccak256("isPaused()"))));
        console2.log("getComponentToken:        ", vm.toString(bytes4(keccak256("getComponentToken(address)"))));
    }

}
