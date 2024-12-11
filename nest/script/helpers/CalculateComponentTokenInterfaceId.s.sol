// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IComponentToken } from "../../src/interfaces/IComponentToken.sol";
import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

contract CalculateComponentTokenInterfaceId is Script {

    function run() public view {
        bytes4 interfaceId = type(IComponentToken).interfaceId;

        // Log results
        console2.log("\nIComponentToken Interface ID Calculation Results:");
        console2.log("----------------------------------------");
        console2.log("Interface ID: ", vm.toString(interfaceId));

        // Log individual function selectors
        console2.log("\nFunction Selectors:");
        console2.log("----------------------------------------");
        console2.log("requestDeposit:          ", vm.toString(IComponentToken.requestDeposit.selector));
        console2.log("deposit:                 ", vm.toString(IComponentToken.deposit.selector));
        console2.log("requestRedeem:           ", vm.toString(IComponentToken.requestRedeem.selector));
        console2.log("redeem:                  ", vm.toString(IComponentToken.redeem.selector));
        console2.log("asset:                   ", vm.toString(IComponentToken.asset.selector));
        console2.log("totalAssets:             ", vm.toString(IComponentToken.totalAssets.selector));
        console2.log("assetsOf:                ", vm.toString(IComponentToken.assetsOf.selector));
        console2.log("convertToShares:         ", vm.toString(IComponentToken.convertToShares.selector));
        console2.log("convertToAssets:         ", vm.toString(IComponentToken.convertToAssets.selector));
        console2.log("pendingDepositRequest:   ", vm.toString(IComponentToken.pendingDepositRequest.selector));
        console2.log("claimableDepositRequest: ", vm.toString(IComponentToken.claimableDepositRequest.selector));
        console2.log("pendingRedeemRequest:    ", vm.toString(IComponentToken.pendingRedeemRequest.selector));
        console2.log("claimableRedeemRequest:  ", vm.toString(IComponentToken.claimableRedeemRequest.selector));
    }

}
