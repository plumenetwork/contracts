// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title IYieldRestrictions Interface
 * @notice Interface for modules that handle restrictions on yield distribution.
 */
interface IYieldRestrictions {

    /**
     * @notice Checks if a given account is allowed to receive yield.
     * @param account The address of the account to check.
     * @return bool True if yield distribution is allowed for the account, false otherwise.
     */
    function isYieldAllowed(
        address account
    ) external view returns (bool);

}
