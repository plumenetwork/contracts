// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IAssetToken } from "../interfaces/IAssetToken.sol";
import { IAssetVault } from "../interfaces/IAssetVault.sol";
import { ISmartWallet } from "../interfaces/ISmartWallet.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockFailingSmartWallet is ISmartWallet {

    // Always revert on transferYield
    function transferYield(
        IAssetToken assetToken,
        address beneficiary,
        IERC20 currencyToken,
        uint256 currencyTokenAmount
    ) external {
        revert("MockFailingSmartWallet: Always fails");
    }

    // ISmartWallet implementations
    function deployAssetVault() external { }

    function getAssetVault() external view returns (IAssetVault assetVault) {
        return IAssetVault(address(0));
    }

    function getBalanceLocked(
        IAssetToken assetToken
    ) external view returns (uint256 balanceLocked) {
        return 0;
    }

    function claimAndRedistributeYield(
        IAssetToken assetToken
    ) external { }
    function upgrade(
        address userWallet
    ) external { }

    // ISignedOperations implementations
    function isNonceUsed(
        bytes32 nonce
    ) external view returns (bool used) {
        return false;
    }

    function cancelSignedOperations(
        bytes32 nonce
    ) external { }
    function executeSignedOperations(
        address[] calldata targets,
        bytes[] calldata calls,
        uint256[] calldata values,
        bytes32 nonce,
        bytes32 nonceDependency,
        uint256 expiration,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external { }

    // IYieldReceiver implementation
    function receiveYield(IAssetToken assetToken, IERC20 currencyToken, uint256 currencyTokenAmount) external { }

}
