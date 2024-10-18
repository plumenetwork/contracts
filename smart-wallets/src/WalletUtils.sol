// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title WalletUtils
 * @author Eugene Y. Q. Shen
 * @notice Common utilities for smart wallets on Plume
 */
contract WalletUtils {

    /**
     * @notice Indicates a failure because the user's SmartWallet call failed
     * @param user Address of the user whose SmartWallet call failed
     */
    error SmartWalletCallFailed(address user);

    /**
     * @notice Indicates a failure because the caller is not the user wallet
     * @param invalidUser Address of the caller who tried to call a wallet-only function
     */
    error UnauthorizedCall(address invalidUser);

    /// @notice Only the user wallet can call this function
    modifier onlyWallet() {
        if (msg.sender != address(this)) {
            revert UnauthorizedCall(msg.sender);
        }
        _;
    }

}
