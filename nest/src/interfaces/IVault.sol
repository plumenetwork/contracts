// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IVault {

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

    /**
     * @notice Transfers vault shares from one address to another
     * @param from Address sending the shares
     * @param to Address receiving the shares
     * @param amount Number of shares to transfer
     * @return bool Success of the transfer operation
     */
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    /**
     * @notice Approves another address to spend vault shares
     * @param spender Address authorized to spend shares
     * @param amount Number of shares approved to spend
     * @return bool Success of the approval operation
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @notice Returns the number of vault shares owned by an account
     * @param account Address to check balance for
     * @return uint256 Number of shares owned by the account
     */
    function balanceOf(
        address account
    ) external view returns (uint256);

}
