// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./IYieldRestrictions.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title YieldBlacklistRestrictions
 * @author Alp Guneysel
 * @notice Module to manage yield distribution restrictions based on a blacklist.
 * @dev Implements IYieldRestrictions. Uses OZ AccessControl for role management.
 */
contract YieldBlacklistRestrictions is Initializable, AccessControlUpgradeable, UUPSUpgradeable, IYieldRestrictions {

    // Role for managing the blacklist
    bytes32 public constant YIELD_BLACKLIST_ADMIN_ROLE = keccak256("YIELD_BLACKLIST_ADMIN_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE"); // For UUPS

    // Mapping for yield blacklist (address => true if blacklisted)
    mapping(address => bool) private _isBlacklisted;

    // Event emitted when an address's blacklist status changes
    event YieldBlacklistUpdated(address indexed account, bool isBlacklisted);

    // Custom Errors
    error InvalidAddress();
    error AlreadyBlacklisted();
    error NotBlacklisted();

    /**
     * @dev Initializes the contract, setting the initial admin for the blacklist.
     * @param admin The address to be granted the initial YIELD_BLACKLIST_ADMIN_ROLE.
     */
    function initialize(
        address admin
    ) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin); // Default admin can manage roles
        _grantRole(YIELD_BLACKLIST_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin); // Admin can upgrade
    }

    // -------------- Blacklist Management --------------

    /**
     * @dev Adds an account to the yield blacklist.
     *      Blacklisted accounts will not receive yield distributions.
     *      Only accounts with YIELD_BLACKLIST_ADMIN_ROLE can call this.
     * @param account The address to add to the blacklist.
     */
    function addToBlacklist(
        address account
    ) external onlyRole(YIELD_BLACKLIST_ADMIN_ROLE) {
        if (account == address(0)) {
            revert InvalidAddress();
        }
        if (_isBlacklisted[account]) {
            revert AlreadyBlacklisted();
        }
        _isBlacklisted[account] = true;
        emit YieldBlacklistUpdated(account, true);
    }

    /**
     * @dev Adds multiple accounts to the yield blacklist.
     * @param accounts Addresses to add.
     */
    function batchAddToBlacklist(
        address[] calldata accounts
    ) external onlyRole(YIELD_BLACKLIST_ADMIN_ROLE) {
        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i];
            if (account != address(0) && !_isBlacklisted[account]) {
                _isBlacklisted[account] = true;
                emit YieldBlacklistUpdated(account, true);
            }
        }
    }

    /**
     * @dev Removes an account from the yield blacklist.
     *      Only accounts with YIELD_BLACKLIST_ADMIN_ROLE can call this.
     * @param account The address to remove from the blacklist.
     */
    function removeFromBlacklist(
        address account
    ) external onlyRole(YIELD_BLACKLIST_ADMIN_ROLE) {
        if (account == address(0)) {
            revert InvalidAddress();
        }
        if (!_isBlacklisted[account]) {
            revert NotBlacklisted();
        }
        _isBlacklisted[account] = false;
        emit YieldBlacklistUpdated(account, false);
    }

    // -------------- IYieldRestrictions Implementation --------------

    /**
     * @dev Checks if an account is allowed to receive yield (i.e., not blacklisted).
     * @param account The address to check.
     * @return bool True if the account is allowed yield (not blacklisted), false otherwise.
     */
    function isYieldAllowed(
        address account
    ) external view override returns (bool) {
        return !_isBlacklisted[account];
    }

    // -------------- View Functions --------------

    /**
     * @dev Public view function to check if an account is explicitly blacklisted.
     * @param account The address to check.
     * @return bool True if the account is blacklisted, false otherwise.
     */
    function isBlacklisted(
        address account
    ) public view returns (bool) {
        return _isBlacklisted[account];
    }

    // -------------- Upgradeability --------------

    /**
     * @dev Authorization for upgrades (UUPS).
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER_ROLE) { }

}
