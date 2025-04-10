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

    // Define locally as it's not being resolved via inheritance
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    /**
     * @notice Initializes the AccessControl facet, granting DEFAULT_ADMIN_ROLE.
     * @dev Can only be called once, typically by the diamond owner after cutting the facet.
     * Grants DEFAULT_ADMIN_ROLE to the caller (expected to be the owner/deployer).
     */
    function initializeAccessControl() external {
        require(!_initializedAC, "ACF: init"); // AccessControlFacet: Already initialized
        // Grant the essential DEFAULT_ADMIN_ROLE to the caller
        // Use msg.sender instead of _msgSender() as it's not resolved
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _initializedAC = true;
        // Emit an event? Optional.
    }

    // --- External Functions ---

    /// @inheritdoc IAccessControl
    function hasRole(bytes32 role, address account) external view override returns (bool) {
        // Directly calls the internal function inherited from AccessControlInternal
        return _hasRole(role, account);
    }

    /// @inheritdoc IAccessControl
    function getRoleAdmin(
        bytes32 role
    ) external view override returns (bytes32) {
        // Directly calls the internal function inherited from AccessControlInternal
        return _getRoleAdmin(role);
    }

    /**
     * @inheritdoc IAccessControl
     * @dev Requires the caller to have the admin role for the role being granted.
     */
    function grantRole(bytes32 role, address account) external override onlyRole(_getRoleAdmin(role)) {
        // Directly calls the internal function inherited from AccessControlInternal
        _grantRole(role, account);
    }

    /**
     * @inheritdoc IAccessControl
     * @dev Requires the caller to have the admin role for the role being revoked.
     */
    function revokeRole(bytes32 role, address account) external override onlyRole(_getRoleAdmin(role)) {
        // Directly calls the internal function inherited from AccessControlInternal
        _revokeRole(role, account);
    }

    /**
     * @inheritdoc IAccessControl
     * @dev Allows an account to renounce their own role. The `_account` parameter is part of the
     *      interface but the internal function `_renounceRole` uses msg.sender.
     */
    function renounceRole(bytes32 role, address account) external override {
        require(account == msg.sender, "AccessControl: can only renounce roles for self");
        // Directly calls the internal function inherited from AccessControlInternal
        _renounceRole(role);
    }

    /**
     * @inheritdoc IAccessControl
     * @dev Requires the caller to have the PlumeRoles.ADMIN_ROLE to change role admins.
     *      Note: SolidState's default admin role is 0x00, but we use PlumeRoles.ADMIN_ROLE
     *      for controlling this specific privileged function.
     */
    function setRoleAdmin(bytes32 role, bytes32 adminRole) external override onlyRole(PlumeRoles.ADMIN_ROLE) {
        // Directly calls the internal function inherited from AccessControlInternal
        _setRoleAdmin(role, adminRole);
    }

}
