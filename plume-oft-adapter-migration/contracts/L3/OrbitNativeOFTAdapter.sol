// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { ArbNativeOFTAdapter } from  "./ArbNativeOFTAdapter.sol";

contract OrbitNativeOFTAdapter is ArbNativeOFTAdapter {
    /**
     * @param _localDecimals The decimals of the native on the local chain (this chain). 18 on ETH.
     * @param _lzEndpoint The LayerZero endpoint address.
     * @param _delegate The delegate capable of making OApp configurations inside of the endpoint.
     */
    constructor(
        uint8 _localDecimals,
        address _lzEndpoint,
        address _delegate
    ) ArbNativeOFTAdapter(_localDecimals, _lzEndpoint, _delegate) {}
}