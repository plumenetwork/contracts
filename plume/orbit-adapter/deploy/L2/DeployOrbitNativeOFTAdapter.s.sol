// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import { ILayerZeroEndpointV2 } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

import { OrbitNativeOFTAdapter } from "../../contracts/L2/OrbitNativeOFTAdapter.sol";

contract DeployOrbitNativeOFTAdapter is Script {
    function setUp() public {}

    uint256 deployerPrivateKey      =    vm.envUint("ROLLUP_ADMIN_PRIVATE_KEY");

    string l2OftAdapterName            =  vm.envString("L2_ADAPTER_NAME");
    string l2OftAdapterSymbol          =  vm.envString("L2_ADAPTER_SYMBOL");
    address l2LayerZeroEndpointAddress = vm.envAddress("L2_LAYER_ZERO_ENDPOINT_ADDRESS");

    function run() public returns (address) {
        address deployerAddress = vm.addr(deployerPrivateKey);

        if (ILayerZeroEndpointV2(l2LayerZeroEndpointAddress).eid() == 0) {
            revert("Error: supplied LZ Endpoint ID is 0. Check L2_LAYER_ZERO_ENDPOINT_ADDRESS env.");
        }

        vm.startBroadcast(deployerPrivateKey);
        OrbitNativeOFTAdapter l2Adapter = new OrbitNativeOFTAdapter(l2OftAdapterName, l2OftAdapterSymbol, l2LayerZeroEndpointAddress, deployerAddress);
        vm.stopBroadcast();

        console.log("L2_ADAPTER_ADDRESS", address(l2Adapter));

        return address(l2Adapter);
    }
}