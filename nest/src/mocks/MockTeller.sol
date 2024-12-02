// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ITeller } from "../interfaces/ITeller.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockTeller is ITeller {

    bool private _paused;
    mapping(IERC20 => bool) private _supportedAssets;

    function setPaused(
        bool paused
    ) external {
        _paused = paused;
    }

    function setAssetSupport(IERC20 asset, bool supported) external {
        _supportedAssets[asset] = supported;
    }

    function isPaused() external view returns (bool) {
        return _paused;
    }

    function isSupported(
        IERC20 asset
    ) external view returns (bool) {
        return _supportedAssets[asset];
    }

    function deposit(
        IERC20 depositAsset,
        uint256 depositAmount,
        uint256 minimumMint
    ) external payable returns (uint256) {
        return depositAmount;
    }

    function assetData(
        IERC20 asset
    ) external view returns (Asset memory) {
        return
            Asset({ allowDeposits: _supportedAssets[asset], allowWithdraws: _supportedAssets[asset], sharePremium: 0 });
    }

    function shareLockPeriod() external view returns (uint64) {
        return 0;
    }

    function shareUnlockTime(
        address user
    ) external view returns (uint256) {
        return 0;
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

}
