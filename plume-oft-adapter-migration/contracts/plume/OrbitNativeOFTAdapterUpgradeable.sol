// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { ArbNativeOFTAdapterUpgradeable } from  "./ArbNativeOFTAdapterUpgradeable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract OrbitNativeOFTAdapterUpgradeable is ArbNativeOFTAdapterUpgradeable {
    /**
     * @param _localDecimals The decimals of the native on the local chain (this chain). 18 on ETH.
     * @param _lzEndpoint The LayerZero endpoint address.
     */
    constructor(
        uint8 _localDecimals,
        address _lzEndpoint
    ) ArbNativeOFTAdapterUpgradeable(_localDecimals, _lzEndpoint) {
        _disableInitializers();
    }

    function initialize(address _delegate) public initializer {
        __NativeOFTAdapter_init(_delegate);
        __Ownable_init(_delegate);
    }
    
}