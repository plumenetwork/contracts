// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {
    ILayerZeroEndpointV2,
    MessagingFee,
    MessagingParams,
    MessagingReceipt,
    Origin
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

contract MockLZEndpointV2 {

    uint32 public immutable eid;
    mapping(address => bool) public allowlist;

    event PacketSent(address indexed sender, uint32 indexed dstEid, bytes32 receiver, bytes payload);

    event PacketReceived(uint32 indexed srcEid, bytes32 sender, address indexed receiver, bytes payload);

    constructor(
        uint32 _eid
    ) {
        eid = _eid;
    }

    function send(
        MessagingParams calldata _params,
        bytes calldata _options,
        MessagingFee calldata _fee,
        address _refundAddress
    ) external payable returns (MessagingReceipt memory receipt) {
        // Simple mock just emits event and returns receipt
        emit PacketSent(msg.sender, _params.dstEid, _params.receiver, _params.message);

        return MessagingReceipt({ guid: bytes32(0), nonce: 0, fee: _fee });
    }

    function quote(MessagingParams calldata, address) external pure returns (MessagingFee memory) {
        // Return mock fee
        return MessagingFee({ nativeFee: 0.01 ether, lzTokenFee: 0 });
    }

    // Helper function to simulate message receipt
    function mockReceiveMessage(uint32 _srcEid, bytes32 _sender, address _receiver, bytes calldata _message) external {
        // Call the OApp's lzReceive
        (bool success, bytes memory reason) =
            _receiver.call(abi.encodeWithSignature("lzReceive(uint32,bytes32,bytes)", _srcEid, _sender, _message));
        require(success, string(reason));

        emit PacketReceived(_srcEid, _sender, _receiver, _message);
    }

}
