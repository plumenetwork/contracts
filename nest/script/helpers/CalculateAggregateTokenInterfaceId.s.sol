// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IAggregateToken } from "../../src/interfaces/IAggregateToken.sol";
import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

contract CalculateAggregateTokenInterfaceId is Script {

    function run() public view {
        bytes4 interfaceId = type(IAggregateToken).interfaceId;

        // Log results
        console2.log("\nIAggregateToken Interface ID Calculation Results:");
        console2.log("----------------------------------------");
        console2.log("Interface ID: ", vm.toString(interfaceId));

        // Log individual function selectors
        console2.log("\nFunction Selectors:");
        console2.log("----------------------------------------");
        // Admin Functions
        console2.log("addComponentToken:        ", vm.toString(IAggregateToken.addComponentToken.selector));
        console2.log("approveComponentToken:    ", vm.toString(IAggregateToken.approveComponentToken.selector));
        console2.log("setAskPrice:             ", vm.toString(IAggregateToken.setAskPrice.selector));
        console2.log("setBidPrice:             ", vm.toString(IAggregateToken.setBidPrice.selector));
        console2.log("pause:                   ", vm.toString(IAggregateToken.pause.selector));
        console2.log("unpause:                 ", vm.toString(IAggregateToken.unpause.selector));

        // Trading Functions
        console2.log("buyComponentToken:        ", vm.toString(IAggregateToken.buyComponentToken.selector));
        console2.log("sellComponentToken:       ", vm.toString(IAggregateToken.sellComponentToken.selector));
        console2.log("requestBuyComponentToken: ", vm.toString(IAggregateToken.requestBuyComponentToken.selector));
        console2.log("requestSellComponentToken:", vm.toString(IAggregateToken.requestSellComponentToken.selector));

        // View Functions
        console2.log("getComponentTokenList:    ", vm.toString(IAggregateToken.getComponentTokenList.selector));
        console2.log("getComponentToken:        ", vm.toString(IAggregateToken.getComponentToken.selector));
        console2.log("getAskPrice:             ", vm.toString(IAggregateToken.getAskPrice.selector));
        console2.log("getBidPrice:             ", vm.toString(IAggregateToken.getBidPrice.selector));
        console2.log("isPaused:                ", vm.toString(IAggregateToken.isPaused.selector));
    }

}
