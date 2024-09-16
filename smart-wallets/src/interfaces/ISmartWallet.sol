// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAssetVault } from "./IAssetVault.sol";
import { ISignedOperations } from "./ISignedOperations.sol";

interface ISmartWallet is ISignedOperations {

    function deployAssetVault() external;
    function getAssetVault() external view returns (IAssetVault assetVault);
    function getBalanceLocked(IERC20 assetToken) external view returns (uint256 balanceLocked);
    function upgrade(address userWallet) external;

}
