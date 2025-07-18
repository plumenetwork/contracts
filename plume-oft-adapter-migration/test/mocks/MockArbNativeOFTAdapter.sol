// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { ArbNativeOFTAdapter } from  "../../src/L3/ArbNativeOFTAdapter.sol";

contract MockArbNativeOFTAdapter is ArbNativeOFTAdapter {
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

    // @dev expose internal functions for testing purposes
    function debit(
        uint256 _amountToSendLD,
        uint256 _minAmountToCreditLD,
        uint32 _dstEid
    ) public returns (uint256 amountDebitedLD, uint256 amountToCreditLD) {
        return _debit(_amountToSendLD, _minAmountToCreditLD, _dstEid);
    }

    function credit(address _to, uint256 _amountToCreditLD, uint32 _srcEid) public returns (uint256 amountReceivedLD) {
        return _credit(_to, _amountToCreditLD, _srcEid);
    }
}