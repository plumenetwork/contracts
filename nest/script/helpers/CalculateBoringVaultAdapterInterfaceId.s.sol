// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IBoringVaultAdapter } from "../../src/interfaces/IBoringVaultAdapter.sol";
import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

contract CalculateBoringVaultAdapterInterfaceId is Script {

    function run() public view {
        bytes4 interfaceId = type(IBoringVaultAdapter).interfaceId;

        // Log results
        console2.log("\nIBoringVaultAdapter Interface ID Calculation Results:");
        console2.log("----------------------------------------");
        console2.log("Interface ID: ", vm.toString(interfaceId));

        // Log individual function selectors for verification
        console2.log("\nFunction Selectors:");
        console2.log("----------------------------------------");
        console2.log("getVault:         ", vm.toString(IBoringVaultAdapter.getVault.selector));
        console2.log("getTeller:        ", vm.toString(IBoringVaultAdapter.getTeller.selector));
        console2.log("getAtomicQueue:   ", vm.toString(IBoringVaultAdapter.getAtomicQueue.selector));
        console2.log("version:          ", vm.toString(IBoringVaultAdapter.version.selector));
        console2.log("deposit:          ", vm.toString(IBoringVaultAdapter.deposit.selector));
        console2.log("requestRedeem:    ", vm.toString(IBoringVaultAdapter.requestRedeem.selector));
        console2.log("notifyRedeem:     ", vm.toString(IBoringVaultAdapter.notifyRedeem.selector));
        console2.log("redeem:           ", vm.toString(IBoringVaultAdapter.redeem.selector));
        console2.log("previewDeposit:   ", vm.toString(IBoringVaultAdapter.previewDeposit.selector));
        console2.log("previewRedeem:    ", vm.toString(IBoringVaultAdapter.previewRedeem.selector));
        console2.log("convertToShares:  ", vm.toString(IBoringVaultAdapter.convertToShares.selector));
        console2.log("convertToAssets:  ", vm.toString(IBoringVaultAdapter.convertToAssets.selector));
        console2.log("balanceOf:        ", vm.toString(IBoringVaultAdapter.balanceOf.selector));
        console2.log("assetsOf:         ", vm.toString(IBoringVaultAdapter.assetsOf.selector));
    }

}
