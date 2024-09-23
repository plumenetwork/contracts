// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title WalletUtils
 * @author Eugene Y. Q. Shen
 * @notice Common utilities for smart wallets on Plume
 */
contract WalletUtils {

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

    /**
     * @notice Checks if an address is a contract or smart wallet.
     * @dev This function uses the `extcodesize` opcode to check if the target address contains contract code.
     * It returns true for contracts and smart wallets, and false for EOAs that do not have smart wallets.
     * @param addr Address to check
     * @return hasCode True if the address is a contract or smart wallet, and false if it is not
     */
    function isContract(address addr) internal view returns (bool hasCode) {
        uint32 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

}
