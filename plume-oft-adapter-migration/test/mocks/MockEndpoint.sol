// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { ILayerZeroEndpointV2, MessagingParams, MessagingFee, MessagingReceipt, Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { SetConfigParam } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";

contract MockEndpoint is ILayerZeroEndpointV2 {
    mapping(address oapp => address delegate) public delegates;

    // Implementations for ILayerZeroEndpointV2
    function quote(MessagingParams calldata /*_params*/, address /*_sender*/) external pure override returns (MessagingFee memory) {
        return MessagingFee(0, 0);
    }

    function send(
        MessagingParams calldata /*_params*/,
        address /*_refundAddress*/
    ) external payable override returns (MessagingReceipt memory) {
        return MessagingReceipt(bytes32(0), 0, MessagingFee(0, 0));
    }

    function verify(Origin calldata /*_origin*/, address /*_receiver*/, bytes32 /*_payloadHash*/) external override {}

    function verifiable(Origin calldata /*_origin*/, address /*_receiver*/) external pure override returns (bool) {
        return false;
    }

    function initializable(Origin calldata /*_origin*/, address /*_receiver*/) external pure override returns (bool) {
        return false;
    }

    function lzReceive(
        Origin calldata /*_origin*/,
        address /*_receiver*/,
        bytes32 /*_guid*/,
        bytes calldata /*_message*/,
        bytes calldata /*_extraData*/
    ) external payable override {}

    function clear(address /*_oapp*/, Origin calldata /*_origin*/, bytes32 /*_guid*/, bytes calldata /*_message*/) external override {}

    function setLzToken(address /*_lzToken*/) external override {}

    function lzToken() external pure override returns (address) {
        return address(0);
    }

    function nativeToken() external pure override returns (address) {
        return address(0);
    }

    function setDelegate(address _delegate) external override {
        delegates[msg.sender] = _delegate;
        emit DelegateSet(msg.sender, _delegate);
    }

    // Implementations for IMessageLibManager
    function registerLibrary(address /*_lib*/) external override {}
    function isRegisteredLibrary(address /*_lib*/) external pure override returns (bool) {
        return false;
    }
    function getRegisteredLibraries() external pure override returns (address[] memory) {
        address[] memory emptyArray;
        return emptyArray;
    }
    function setDefaultSendLibrary(uint32 /*_eid*/, address /*_newLib*/) external override {}
    function defaultSendLibrary(uint32 /*_eid*/) external pure override returns (address) {
        return address(0);
    }
    function setDefaultReceiveLibrary(uint32 /*_eid*/, address /*_newLib*/, uint256 /*_timeout*/) external override {}
    function defaultReceiveLibrary(uint32 /*_eid*/) external pure override returns (address) {
        return address(0);
    }
    function setDefaultReceiveLibraryTimeout(uint32 /*_eid*/, address /*_lib*/, uint256 /*_expiry*/) external override {}
    function defaultReceiveLibraryTimeout(uint32 /*_eid*/) external pure override returns (address lib, uint256 expiry) {
        return (address(0), 0);
    }
    function isSupportedEid(uint32 /*_eid*/) external pure override returns (bool) {
        return false;
    }
    function isValidReceiveLibrary(address /*_receiver*/, uint32 /*_eid*/, address /*_lib*/) external pure override returns (bool) {
        return false;
    }
    function setSendLibrary(address /*_oapp*/, uint32 /*_eid*/, address /*_newLib*/) external override {}
    function getSendLibrary(address /*_sender*/, uint32 /*_eid*/) external pure override returns (address lib) {
        return address(0);
    }
    function isDefaultSendLibrary(address /*_sender*/, uint32 /*_eid*/) external pure override returns (bool) {
        return false;
    }
    function setReceiveLibrary(address /*_oapp*/, uint32 /*_eid*/, address /*_newLib*/, uint256 /*_gracePeriod*/) external override {}
    function getReceiveLibrary(address /*_receiver*/, uint32 /*_eid*/) external pure override returns (address lib, bool isDefault) {
        return (address(0), false);
    }
    function setReceiveLibraryTimeout(address /*_oapp*/, uint32 /*_eid*/, address /*_lib*/, uint256 /*_gracePeriod*/) external override {}
    function receiveLibraryTimeout(address /*_receiver*/, uint32 /*_eid*/) external pure override returns (address lib, uint256 expiry) {
        return (address(0), 0);
    }
    function setConfig(address /*_oapp*/, address /*_lib*/, SetConfigParam[] calldata /*_params*/) external override {}
    function getConfig(
        address /*_oapp*/,
        address /*_lib*/,
        uint32 /*_eid*/,
        uint32 /*_configType*/
    ) external pure override returns (bytes memory config) {
        return "";
    }

    // Implementations for IMessagingComposer
    function composeQueue(
        address /*_from*/,
        address /*_to*/,
        bytes32 /*_guid*/,
        uint16 /*_index*/
    ) external pure override returns (bytes32) {
        return bytes32(0);
    }
    function sendCompose(address /*_to*/, bytes32 /*_guid*/, uint16 /*_index*/, bytes calldata /*_message*/) external override {}
    function lzCompose(
        address /*_from*/,
        address /*_to*/,
        bytes32 /*_guid*/,
        uint16 /*_index*/,
        bytes calldata /*_message*/,
        bytes calldata /*_extraData*/
    ) external payable override {}

    // Implementations for IMessagingChannel
    function eid() external pure override returns (uint32) {
        return 10777;
    }
    function skip(address /*_oapp*/, uint32 /*_srcEid*/, bytes32 /*_sender*/, uint64 /*_nonce*/) external override {}
    function nilify(address /*_oapp*/, uint32 /*_srcEid*/, bytes32 /*_sender*/, uint64 /*_nonce*/, bytes32 /*_payloadHash*/) external override {}
    function burn(address /*_oapp*/, uint32 /*_srcEid*/, bytes32 /*_sender*/, uint64 /*_nonce*/, bytes32 /*_payloadHash*/) external override {}
    function nextGuid(address /*_sender*/, uint32 /*_dstEid*/, bytes32 /*_receiver*/) external pure override returns (bytes32) {
        return bytes32(0);
    }
    function inboundNonce(address /*_receiver*/, uint32 /*_srcEid*/, bytes32 /*_sender*/) external pure override returns (uint64) {
        return 0;
    }
    function outboundNonce(address /*_sender*/, uint32 /*_dstEid*/, bytes32 /*_receiver*/) external pure override returns (uint64) {
        return 0;
    }
    function inboundPayloadHash(
        address /*_receiver*/,
        uint32 /*_srcEid*/,
        bytes32 /*_sender*/,
        uint64 /*_nonce*/
    ) external pure override returns (bytes32) {
        return bytes32(0);
    }
    function lazyInboundNonce(address /*_receiver*/, uint32 /*_srcEid*/, bytes32 /*_sender*/) external pure override returns (uint64) {
        return 0;
    }

    // Implementations for IMessagingContext
    function isSendingMessage() external pure override returns (bool) {
        return false;
    }
    function getSendContext() external pure override returns (uint32 dstEid, address sender) {
        return (0, address(0));
    }
}