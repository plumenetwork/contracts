// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// SolidState Access Control
import { AccessControlInternal } from "@solidstate/access/access_control/AccessControlInternal.sol";
import { AccessControlStorage } from "@solidstate/access/access_control/AccessControlStorage.sol";

// Plume Roles & Interface
import { IAccessControl } from "../interfaces/IAccessControl.sol";
import { PlumeRoles } from "../lib/PlumeRoles.sol";
import { PlumeStakingStorage } from "../lib/PlumeStakingStorage.sol"; // For potential shared init flag

/**
 * @title AccessControlFacet
 * @notice Facet for managing roles using SolidState's AccessControl logic.
 * @dev Uses the storage slot defined in SolidState's AccessControlStorage.
 */
contract AccessControlFacet is IAccessControl, AccessControlInternal {

    // Simple flag to prevent re-initialization within this facet's context
    bool private _initializedAC;

    // Define all roles locally for clarity and direct access
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant ADMIN_ROLE = PlumeRoles.ADMIN_ROLE;
    bytes32 public constant UPGRADER_ROLE = PlumeRoles.UPGRADER_ROLE;
    bytes32 public constant VALIDATOR_ROLE = PlumeRoles.VALIDATOR_ROLE;
    bytes32 public constant REWARD_MANAGER_ROLE = PlumeRoles.REWARD_MANAGER_ROLE;

    /**
     * @notice Initializes the AccessControl facet, setting up all roles and their admins.
     * @dev Can only be called once, typically by the diamond owner after cutting the facet.
     * Sets up the complete role hierarchy with DEFAULT_ADMIN_ROLE and ADMIN_ROLE at the top.
     */
    function initializeAccessControl() external {
        require(!_initializedAC, "ACF: init"); // AccessControlFacet: Already initialized

        // Grant the essential DEFAULT_ADMIN_ROLE to the caller
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        // Grant ADMIN_ROLE to the caller
        _grantRole(ADMIN_ROLE, msg.sender);

        // Set up role hierarchy
        // Make ADMIN_ROLE the admin for all other roles (including itself)
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(UPGRADER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(VALIDATOR_ROLE, ADMIN_ROLE);
        _setRoleAdmin(REWARD_MANAGER_ROLE, ADMIN_ROLE);

        // Grant initial roles to the caller
        _grantRole(UPGRADER_ROLE, msg.sender);
        _grantRole(REWARD_MANAGER_ROLE, msg.sender);

        _initializedAC = true;
    }

    // --- External Functions ---

    /// @inheritdoc IAccessControl
    function hasRole(bytes32 role, address account) external view override returns (bool) {
        return _hasRole(role, account);
    }

    /// @inheritdoc IAccessControl
    function getRoleAdmin(
        bytes32 role
    ) external view override returns (bytes32) {
        return _getRoleAdmin(role);
    }

    /**
     * @inheritdoc IAccessControl
     * @dev Requires the caller to have the admin role for the role being granted.
     */
    function grantRole(bytes32 role, address account) external override onlyRole(_getRoleAdmin(role)) {
        _grantRole(role, account);
    }

    /**
     * @inheritdoc IAccessControl
     * @dev Requires the caller to have the admin role for the role being revoked.
     */
    function revokeRole(bytes32 role, address account) external override onlyRole(_getRoleAdmin(role)) {
        _revokeRole(role, account);
    }

    /**
     * @inheritdoc IAccessControl
     * @dev Allows an account to renounce their own role.
     */
    function renounceRole(bytes32 role, address account) external override {
        require(account == msg.sender, "AccessControl: can only renounce roles for self");
        _renounceRole(role);
    }

    /**
     * @inheritdoc IAccessControl
     * @dev Requires the caller to have the ADMIN_ROLE to change role admins.
     */
    function setRoleAdmin(bytes32 role, bytes32 adminRole) external override onlyRole(ADMIN_ROLE) {
        _setRoleAdmin(role, adminRole);
    }

}
