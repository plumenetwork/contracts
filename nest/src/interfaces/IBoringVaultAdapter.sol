// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

interface IBoringVaultAdapter {

    // View Functions
    function getVault() external view returns (address);
    function getTeller() external view returns (address);
    function getAtomicQueue() external view returns (address);
    function version() external view returns (uint256);

    // Core Functions
    function deposit(
        uint256 assets,
        address receiver,
        address controller,
        uint256 minimumMint
    ) external returns (uint256 shares);

    function requestRedeem(
        uint256 shares,
        address receiver,
        address controller,
        uint256 price,
        uint64 deadline
    ) external returns (uint256);

    function notifyRedeem(uint256 assets, uint256 shares, address controller) external;

    function redeem(uint256 shares, address receiver, address controller) external returns (uint256 assets);

    // Preview Functions
    function previewDeposit(
        uint256 assets
    ) external view returns (uint256);
    function previewRedeem(
        uint256 shares
    ) external view returns (uint256 assets);
    function convertToShares(
        uint256 assets
    ) external view returns (uint256 shares);
    function convertToAssets(
        uint256 shares
    ) external view returns (uint256 assets);

    // Balance Functions
    function balanceOf(
        address account
    ) external view returns (uint256);
    function assetsOf(
        address account
    ) external view returns (uint256);

    // Events
    event VaultChanged(address oldVault, address newVault);
    event Reinitialized(uint256 version);

}
