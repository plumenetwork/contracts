// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IComponentToken } from "../../src/interfaces/IComponentToken.sol";
import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

contract CalculateComponentTokenInterfaceId is Script {

    function run() public view {
        bytes4 interfaceId = calculateInterfaceId();

        // Log results
        console2.log("\nIComponentToken Interface ID Calculation Results:");
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
            keccak256("requestDeposit(uint256,address,address)") ^ keccak256("deposit(uint256,address,address)")
                ^ keccak256("requestRedeem(uint256,address,address)") ^ keccak256("redeem(uint256,address,address)")
        );
    }

    function calculateGroup2() public pure returns (bytes4) {
        return bytes4(
            keccak256("asset()") ^ keccak256("totalAssets()") ^ keccak256("assetsOf(address)")
                ^ keccak256("convertToShares(uint256)") ^ keccak256("convertToAssets(uint256)")
        );
    }

    function calculateGroup3() public pure returns (bytes4) {
        return bytes4(
            keccak256("pendingDepositRequest(uint256,address)") ^ keccak256("claimableDepositRequest(uint256,address)")
                ^ keccak256("pendingRedeemRequest(uint256,address)") ^ keccak256("claimableRedeemRequest(uint256,address)")
        );
    }

    function logFunctionSelectors() public pure {
        console2.log("\nFunction Selectors:");
        console2.log("----------------------------------------");
        console2.log(
            "requestDeposit:          ", vm.toString(bytes4(keccak256("requestDeposit(uint256,address,address)")))
        );
        console2.log("deposit:                 ", vm.toString(bytes4(keccak256("deposit(uint256,address,address)"))));
        console2.log(
            "requestRedeem:           ", vm.toString(bytes4(keccak256("requestRedeem(uint256,address,address)")))
        );
        console2.log("redeem:                  ", vm.toString(bytes4(keccak256("redeem(uint256,address,address)"))));
        console2.log("asset:                   ", vm.toString(bytes4(keccak256("asset()"))));
        console2.log("totalAssets:             ", vm.toString(bytes4(keccak256("totalAssets()"))));
        console2.log("assetsOf:                ", vm.toString(bytes4(keccak256("assetsOf(address)"))));
        console2.log("convertToShares:         ", vm.toString(bytes4(keccak256("convertToShares(uint256)"))));
        console2.log("convertToAssets:         ", vm.toString(bytes4(keccak256("convertToAssets(uint256)"))));
        console2.log(
            "pendingDepositRequest:   ", vm.toString(bytes4(keccak256("pendingDepositRequest(uint256,address)")))
        );
        console2.log(
            "claimableDepositRequest: ", vm.toString(bytes4(keccak256("claimableDepositRequest(uint256,address)")))
        );
        console2.log(
            "pendingRedeemRequest:    ", vm.toString(bytes4(keccak256("pendingRedeemRequest(uint256,address)")))
        );
        console2.log(
            "claimableRedeemRequest:  ", vm.toString(bytes4(keccak256("claimableRedeemRequest(uint256,address)")))
        );
    }

}
