// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface ISmartWallet {

    function deployAssetVault() external;
    function getAssetVault() external view returns (IAssetVault);
    function upgrade(address userWallet) external;

}
