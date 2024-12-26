// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { MessageLibManager } from "@layerzerolabs/lz-evm-protocol-v2/contracts/MessageLibManager.sol";
import { MessagingChannel } from "@layerzerolabs/lz-evm-protocol-v2/contracts/MessagingChannel.sol";
import { MessagingComposer } from "@layerzerolabs/lz-evm-protocol-v2/contracts/MessagingComposer.sol";
import { MessagingContext } from "@layerzerolabs/lz-evm-protocol-v2/contracts/MessagingContext.sol";
import {
    ILayerZeroEndpointV2,
    MessagingFee,
    MessagingParams,
    MessagingReceipt,
    Origin
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract MockLayerZeroEndpoint is
    MessagingChannel,
    MessageLibManager,
    MessagingComposer,
    MessagingContext,
    ILayerZeroEndpointV2
{

    address public lzToken;
    mapping(address oapp => address delegate) public delegates;

    constructor(
        uint32 _eid,
        address _owner
    ) MessagingChannel(_eid) MessageLibManager() MessagingComposer() MessagingContext() Ownable(_owner) { }

    function quote(MessagingParams calldata, address) external pure returns (MessagingFee memory) {
        return MessagingFee(0, 0);
    }

    function send(MessagingParams calldata _params, address) external payable returns (MessagingReceipt memory) {
        bytes32 guid = keccak256(abi.encodePacked(msg.sender, _params.dstEid, _params.receiver));
        return MessagingReceipt(guid, 1, MessagingFee(0, 0));
    }

    function verify(Origin calldata, address, bytes32) external pure { }

    function lzReceive(Origin calldata, address, bytes32, bytes calldata, bytes calldata) external payable { }

    function clear(address, Origin calldata, bytes32, bytes calldata) external { }

    function setLzToken(
        address _lzToken
    ) external {
        lzToken = _lzToken;
        emit LzTokenSet(_lzToken);
    }

    function setDelegate(
        address _delegate
    ) external {
        delegates[msg.sender] = _delegate;
        emit DelegateSet(msg.sender, _delegate);
    }

    function nativeToken() external pure returns (address) {
        return address(0);
    }

    function initializable(Origin calldata, address) external pure returns (bool) {
        return true;
    }

    function verifiable(Origin calldata, address) external pure returns (bool) {
        return true;
    }

    // Override required internal functions
    function _assertAuthorized(
        address _oapp
    ) internal view override(MessagingChannel, MessageLibManager) {
        if (msg.sender != _oapp && msg.sender != delegates[_oapp]) {
            revert("Unauthorized");
        }
    }

}
