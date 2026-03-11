// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { OFTAdapterUpgradeable } from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTAdapterUpgradeable.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IERC20Bridge } from "./bridge/IERC20Bridge.sol";

contract OrbitERC20OFTAdapterUpgradeable is OFTAdapterUpgradeable {
    using SafeERC20 for IERC20;

    IERC20Bridge private immutable bridge;

    constructor(
        address _token,
        address _layerZeroEndpoint,
        IERC20Bridge _bridge
    ) OFTAdapterUpgradeable(_token, _layerZeroEndpoint) {
        bridge = _bridge;
        _disableInitializers();
    }

    function initialize(address _delegate) public initializer {
        __OFTAdapter_init(_delegate);
        __Ownable_init(_delegate);
    }

    function _debit(
        address /*_from*/,
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