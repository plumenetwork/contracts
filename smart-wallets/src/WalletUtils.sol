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
     * @notice Checks if an address is a contract.
     * @dev This function uses the `extcodesize` opcode to check if the target address contains contract code.
     * It returns false for externally owned accounts (EOA) and true for contracts.
     * @param addr The address to check.
     * @return bool Returns true if the address is a contract, and false if it's an externally owned account (EOA).
     */
    function isContract(address addr) internal view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

}
