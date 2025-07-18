// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { OFTAdapter } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTAdapter.sol";

import { IERC20Bridge } from "./bridge/IERC20Bridge.sol";

contract OrbitERC20OFTAdapter is OFTAdapter {
    using SafeERC20 for IERC20;

    IERC20Bridge private immutable bridge;

    constructor(
        address _token,
        address _layerZeroEndpoint,
        address _owner,
        IERC20Bridge _bridge
    ) OFTAdapter(_token, _layerZeroEndpoint, _owner) {
        bridge = _bridge;
    }

    function _debit(
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal virtual override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        (amountSentLD, amountReceivedLD) = _debitView(_amountLD, _minAmountLD, _dstEid);
        // @dev Lock tokens by moving them into the bridge from the caller.
        innerToken.safeTransferFrom(msg.sender, address(bridge), amountSentLD);
    }

    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 /*_srcEid*/
    ) internal virtual override returns (uint256 amountReceivedLD) {
        // @dev Unlock the tokens and transfer to the recipient.
        bridge.executeCall(_to, _amountLD, "");

        // @dev In the case of NON-default OFTAdapter, the amountLD MIGHT not be == amountReceivedLD.
        return _amountLD;
    }
}