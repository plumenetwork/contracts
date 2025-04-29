// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title PlumeRoles
 * @notice Defines role constants used for access control in the PlumeStaking Diamond.
 */
library PlumeRoles {

    // Default admin role (can grant/revoke other roles)
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Role for performing diamond upgrades (diamondCut)
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // Role for managing validator settings
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");

    // Role for managing reward settings and distribution
    bytes32 public constant REWARD_MANAGER_ROLE = keccak256("REWARD_MANAGER_ROLE");

    // Role for managing time-locked actions
    bytes32 public constant TIMELOCK_ROLE = keccak256("TIMELOCK_ROLE");

}
