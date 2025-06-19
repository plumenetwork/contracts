// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";

import { IOAppCore } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppCore.sol";

contract WireAdapterToL1 is Script {
    function setUp() public {}

    uint256 rollupAdminPrivateKey =        vm.envUint("ROLLUP_ADMIN_PRIVATE_KEY");

    address l1AdapterAddress      =     vm.envAddress("L1_ADAPTER_ADDRESS");
    uint32 l1LayerZeroEndpointId  = uint32(vm.envUint("L1_LAYER_ZERO_ENDPOINT_ID"));

    address l2AdapterAddress      =     vm.envAddress("L2_ADAPTER_ADDRESS");

    function run() public {
        vm.startBroadcast(rollupAdminPrivateKey);
        IOAppCore l2Adapter = IOAppCore(l2AdapterAddress);

        bytes32 l1PeerAddress = addressToBytes32(l1AdapterAddress);

        bytes32 existingPeer = l2Adapter.peers(l1LayerZeroEndpointId);
        if (keccak256(abi.encodePacked(existingPeer)) == keccak256(abi.encodePacked(l1PeerAddress))) {
            console.log("%s", "Peer already set.");
            return;
        }
        l2Adapter.setPeer(l1LayerZeroEndpointId, l1PeerAddress);
        vm.stopBroadcast();
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}