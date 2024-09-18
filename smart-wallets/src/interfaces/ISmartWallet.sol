// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { AssetVault } from "../extensions/AssetVault.sol";
import { ISignedOperations } from "./ISignedOperations.sol";

interface ISmartWallet is ISignedOperations {

    function deployAssetVault() external;
    function getAssetVault() external view returns (AssetVault assetVault);
    function getBalanceLocked(ERC20 assetToken) external view returns (uint256 balanceLocked);
    function upgrade(address userWallet) external;

}
