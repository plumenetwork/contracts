// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title ITransferRestrictions
 * @author Alp Guneysel
 * @notice Interface for modular transfer restriction strategies for ArcToken
 * @dev Implementations of this interface provide different restriction strategies
 * that can be plugged into the ArcToken contract
 */
interface ITransferRestrictions {
    /**
     * @dev Returns whether a transfer is allowed
     * @param from Address sending tokens
     * @param to Address receiving tokens
     * @param amount Amount of tokens being transferred
     * @return allowed True if the transfer is allowed, false otherwise
     */
    function isTransferAllowed(
        address from,
        address to,
        uint256 amount
    ) external view returns (bool allowed);

    /**
     * @dev Optional hook that gets called before a transfer
     * @param from Address sending tokens
     * @param to Address receiving tokens
     * @param amount Amount of tokens being transferred
     */
    function beforeTransfer(
        address from,
        address to,
        uint256 amount
    ) external;

    /**
     * @dev Optional hook that gets called after a transfer
     * @param from Address that sent tokens
     * @param to Address that received tokens
     * @param amount Amount of tokens transferred
     */
    function afterTransfer(
        address from,
        address to,
        uint256 amount
    ) external;
} 