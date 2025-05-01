// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IAccessControl
 * @notice Interface for the role-based access control facet.
 */
interface IAccessControl {

    // Events are inherited from SolidState's AccessControl
    // event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
    // event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    // event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    function hasRole(bytes32 role, address account) external view returns (bool);
    function getRoleAdmin(
        bytes32 role
    ) external view returns (bytes32);
    function grantRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
    function renounceRole(bytes32 role, address account) external; // Keep renounceRole signature consistent
    function setRoleAdmin(bytes32 role, bytes32 adminRole) external;

}
