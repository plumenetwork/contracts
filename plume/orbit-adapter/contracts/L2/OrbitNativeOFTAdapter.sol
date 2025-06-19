// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { NativeOFTAdapterMsgValueTransfer } from  "./NativeOFTAdapterMsgValueTransfer.sol";

contract OrbitNativeOFTAdapter is NativeOFTAdapterMsgValueTransfer {
    constructor(
        string memory _name,
        string memory _symbol,
        address _layerZeroEndpoint, // local endpoint address
        address _owner // token owner
    ) NativeOFTAdapterMsgValueTransfer(_name, _symbol, _layerZeroEndpoint, _owner) {}
}