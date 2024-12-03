// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IVault is IERC20, IERC20Metadata {

    /**
     * @notice Deposits assets into the vault in exchange for shares
     * @param from Address providing the assets
     * @param asset Token address being deposited
     * @param assetAmount Amount of assets to deposit
     * @param to Address receiving the vault shares
     * @param shareAmount Amount of shares to mint
     */
    function enter(address from, address asset, uint256 assetAmount, address to, uint256 shareAmount) external;

    /**
     * @notice Withdraws assets from the vault by burning shares
     * @param to Address receiving the withdrawn assets
     * @param asset Token address being withdrawn
     * @param assetAmount Amount of assets to withdraw
     * @param from Address providing the shares to burn
     * @param shareAmount Amount of shares to burn
     */
    function exit(address to, address asset, uint256 assetAmount, address from, uint256 shareAmount) external;

}
