// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { ArbNativeOFTAdapterUpgradeable } from  "../../../contracts/plume/ArbNativeOFTAdapterUpgradeable.sol";

contract MockArbNativeOFTAdapterUpgradeable is ArbNativeOFTAdapterUpgradeable {
    /**
     * @param _localDecimals The decimals of the native on the local chain (this chain). 18 on ETH.
     * @param _lzEndpoint The LayerZero endpoint address.
     */
    constructor(
        uint8 _localDecimals,
        address _lzEndpoint
    ) ArbNativeOFTAdapterUpgradeable(_localDecimals, _lzEndpoint) {}

    function initialize(address _delegate) public initializer {
        __NativeOFTAdapter_init(_delegate);
        __Ownable_init(_delegate);
    }

    // @dev expose internal functions for testing purposes
    function debit(
        address _from,
        uint256 _amountToSendLD,
        uint256 _minAmountToCreditLD,
        uint32 _dstEid
    ) public returns (uint256 amountDebitedLD, uint256 amountToCreditLD) {
        return _debit(_from, _amountToSendLD, _minAmountToCreditLD, _dstEid);
    }

    function credit(address _to, uint256 _amountToCreditLD, uint32 _srcEid) public returns (uint256 amountReceivedLD) {
        return _credit(_to, _amountToCreditLD, _srcEid);
    }
}