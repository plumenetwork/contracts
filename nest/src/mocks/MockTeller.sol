// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { BridgeData, ITeller } from "../interfaces/ITeller.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockTeller is ITeller {

    IERC20 public immutable vault;
    uint256 public constant MOCK_FEE = 0.01 ether;
    bool private _paused;
    mapping(IERC20 => bool) private _supportedAssets;

    constructor(
        IERC20 _vault
    ) {
        vault = _vault;
    }

    function depositAndBridge(
        ERC20 depositAsset,
        uint256 depositAmount,
        uint256 minimumMint,
        BridgeData calldata data
    ) external payable {
        // Mock implementation that just transfers the tokens
        depositAsset.transferFrom(msg.sender, address(this), depositAmount);
    }

    function previewFee(
        uint256, // shareAmount
        BridgeData calldata // data
    ) external pure returns (uint256) {
        // Mock implementation that returns a fixed fee
        return MOCK_FEE;
    }

    // Implement other required interface functions
    function isPaused() external view returns (bool) {
        return _paused;
    }

    function isSupported(
        IERC20 asset
    ) external view returns (bool) {
        return _supportedAssets[asset];
    }

    function assetData(
        IERC20 asset
    ) external view returns (Asset memory) {
        return
            Asset({ allowDeposits: _supportedAssets[asset], allowWithdraws: _supportedAssets[asset], sharePremium: 0 });
    }

    function shareLockPeriod() external pure returns (uint64) {
        return 0;
    }

    function shareUnlockTime(
        address
    ) external pure returns (uint256) {
        return 0;
    }

    function deposit(
        IERC20 depositAsset,
        uint256 depositAmount,
        uint256 minimumMint
    ) external payable returns (uint256) {
        return depositAmount;
    }

    function depositWithPermit(
        IERC20 depositAsset,
        uint256 depositAmount,
        uint256 minimumMint,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256) {
        return depositAmount;
    }

    function bulkDeposit(
        IERC20 depositAsset,
        uint256 depositAmount,
        uint256 minimumMint,
        address to
    ) external returns (uint256) {
        return depositAmount;
    }

    function bulkWithdraw(
        IERC20 withdrawAsset,
        uint256 shareAmount,
        uint256 minimumAssets,
        address to
    ) external returns (uint256) {
        return shareAmount;
    }

    function refundDeposit(
        uint256 nonce,
        address receiver,
        address depositAsset,
        uint256 depositAmount,
        uint256 shareAmount,
        uint256 depositTimestamp,
        uint256 shareLockUpPeriodAtTimeOfDeposit
    ) external { }

    // Additional helper functions for testing
    function setPaused(
        bool paused
    ) external {
        _paused = paused;
    }

    function setAssetSupport(IERC20 asset, bool supported) external {
        _supportedAssets[asset] = supported;
    }

    function mint(address to, uint256 amount) external {
        // Mock minting vault tokens
        vault.transfer(to, amount);
    }

}
