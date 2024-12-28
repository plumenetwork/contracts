// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { ERC20 } from "@solmate/tokens/ERC20.sol";

struct BridgeData {
    uint32 chainSelector;
    address destinationChainReceiver;
    ERC20 bridgeFeeToken;
    uint64 messageGas;
    bytes data;
}

interface ICrossChainTellerBase {

    // Events
    event MessageSent(bytes32 messageId, uint256 shareAmount, address to);
    event MessageReceived(bytes32 messageId, uint256 shareAmount, address to);

    /**
     * @notice function to deposit into the vault AND bridge crosschain in 1 call
     * @param depositAsset ERC20 to deposit
     * @param depositAmount amount of deposit asset to deposit
     * @param minimumMint minimum required shares to receive
     * @param data Bridge Data
     */
    function depositAndBridge(
        ERC20 depositAsset,
        uint256 depositAmount,
        uint256 minimumMint,
        BridgeData calldata data
    ) external payable;

    /**
     * @notice Preview fee required to bridge shares in a given feeToken.
     */
    function previewFee(uint256 shareAmount, BridgeData calldata data) external view returns (uint256 fee);

    /**
     * @notice bridging code to be done without deposit, for users who already have vault tokens
     * @param shareAmount to bridge
     * @param data bridge data
     */
    function bridge(uint256 shareAmount, BridgeData calldata data) external payable returns (bytes32 messageId);

    // Errors (from TellerWithMultiAssetSupport)
    error TellerWithMultiAssetSupport__AssetNotSupported();
    error TellerWithMultiAssetSupport__Paused();

}
