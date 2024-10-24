// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAssetToken } from "./IAssetToken.sol";
import { IAssetVault } from "./IAssetVault.sol";
import { ISignedOperations } from "./ISignedOperations.sol";
import { IYieldReceiver } from "./IYieldReceiver.sol";

interface ISmartWallet is ISignedOperations, IYieldReceiver {

    function deployAssetVault() external;
    function getAssetVault() external view returns (IAssetVault assetVault);
    function getBalanceLocked(IAssetToken assetToken) external view returns (uint256 balanceLocked);
    function claimAndRedistributeYield(IAssetToken assetToken) external;
    function transferYield(
        IAssetToken assetToken,
        address beneficiary,
        IERC20 currencyToken,
        uint256 currencyTokenAmount
    ) external;
    function upgrade(address userWallet) external;

}
