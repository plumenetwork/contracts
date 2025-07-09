// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./ITransferRestrictions.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title WhitelistRestrictions
 * @author Alp Guneysel
 * @notice Implementation of transfer restrictions based on a whitelist
 * @dev This contract can be used by ArcToken to enforce whitelist-based
 * transfer restrictions in a modular way
 */
contract WhitelistRestrictions is
    ITransferRestrictions,
    Initializable,
    UUPSUpgradeable,
    AccessControlEnumerableUpgradeable
{

    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant WHITELIST_ADMIN_ROLE = keccak256("WHITELIST_ADMIN_ROLE");

    // Custom errors
    error AlreadyWhitelisted(address account);
    error NotWhitelisted(address account);
    error TransferRestricted();
    error InvalidAddress();
    error CannotRemoveZeroAddress();
    error CannotAddZeroAddress();

    /// @custom:storage-location erc7201:whitelist.restrictions.storage
    struct WhitelistStorage {
        // Whitelist mapping (address => true if allowed to transfer/hold when restricted)
        mapping(address => bool) isWhitelisted;
        // Flag to control if transfers are unrestricted (true) or only whitelisted (false)
        bool transfersAllowed;
        // Set of all whitelisted addresses for enumeration if needed
        EnumerableSet.AddressSet whitelistedAddresses;
    }

    // Calculate unique storage slot
    bytes32 private constant WHITELIST_STORAGE_LOCATION = keccak256("whitelist.restrictions.storage");

    function _getWhitelistStorage() private pure returns (WhitelistStorage storage ws) {
        bytes32 position = WHITELIST_STORAGE_LOCATION;
        assembly {
            ws.slot := position
        }
    }

    // Events
    event WhitelistStatusChanged(address indexed account, bool isWhitelisted);
    event TransfersRestrictionToggled(bool transfersAllowed);
    event AddedToWhitelist(address indexed account);
    event RemovedFromWhitelist(address indexed account);

    /**
     * @dev Initialize the whitelist restrictions module
     * @param admin The address to grant admin role to
     */
    function initialize(
        address admin
    ) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __AccessControlEnumerable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, admin);
        _grantRole(WHITELIST_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);

        // Set initial transfer restriction to unrestricted
        WhitelistStorage storage ws = _getWhitelistStorage();
        ws.transfersAllowed = true;

        // Add admin to whitelist
        // _add(admin); // Comment kept for clarity on removal
        /* // Removed lines:
        ws.isWhitelisted[admin] = true;
        ws.whitelistedAddresses.add(admin);
        emit WhitelistStatusChanged(admin, true);
        */
    }

    /**
     * @dev Implementation of isTransferAllowed from ITransferRestrictions
     * @notice Determines if a transfer is allowed based on whitelist settings
     */
    function isTransferAllowed(address from, address to, uint256 /*amount*/ ) external view override returns (bool) {
        WhitelistStorage storage ws = _getWhitelistStorage();

        // If transfers are unrestricted, allow all transfers
        if (ws.transfersAllowed) {
            return true;
        }

        // Otherwise, only allow if both the sender and receiver are whitelisted
        return ws.isWhitelisted[from] && ws.isWhitelisted[to];
    }

    /**
     * @dev Implementation of beforeTransfer from ITransferRestrictions
     * @notice No actions needed before transfer in this implementation
     */
    function beforeTransfer(address, /*from*/ address, /*to*/ uint256 /*amount*/ ) external override {
        // Not used in this implementation, but required by interface
    }

    /**
     * @dev Implementation of afterTransfer from ITransferRestrictions
     * @notice No actions needed after transfer in this implementation
     */
    function afterTransfer(address, /*from*/ address, /*to*/ uint256 /*amount*/ ) external override {
        // Not used in this implementation, but required by interface
    }

    /**
     * @dev Adds an account to the whitelist, allowing it to hold and transfer tokens when transfers are restricted.
     */
    function addToWhitelist(
        address account
    ) external onlyRole(MANAGER_ROLE) {
        if (account == address(0)) {
            revert InvalidAddress();
        }

        WhitelistStorage storage ws = _getWhitelistStorage();
        if (ws.isWhitelisted[account]) {
            revert AlreadyWhitelisted(account);
        }

        ws.isWhitelisted[account] = true;
        ws.whitelistedAddresses.add(account);
        emit WhitelistStatusChanged(account, true);
        emit AddedToWhitelist(account);
    }

    /**
     * @dev Adds multiple accounts to the whitelist in a single transaction.
     * @param accounts Array of addresses to add to the whitelist
     */
    function batchAddToWhitelist(
        address[] calldata accounts
    ) external onlyRole(MANAGER_ROLE) {
        WhitelistStorage storage ws = _getWhitelistStorage();

        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i];

            if (account == address(0)) {
                continue; // Skip zero address
            }

            if (!ws.isWhitelisted[account]) {
                ws.isWhitelisted[account] = true;
                ws.whitelistedAddresses.add(account);
                emit WhitelistStatusChanged(account, true);
                emit AddedToWhitelist(account);
            }
        }
    }

    /**
     * @dev Removes an account from the whitelist.
     * Accounts not whitelisted cannot send or receive tokens while transfers are restricted.
     */
    function removeFromWhitelist(
        address account
    ) external onlyRole(MANAGER_ROLE) {
        WhitelistStorage storage ws = _getWhitelistStorage();

        if (!ws.isWhitelisted[account]) {
            revert NotWhitelisted(account);
        }

        ws.isWhitelisted[account] = false;
        ws.whitelistedAddresses.remove(account);
        emit WhitelistStatusChanged(account, false);
        emit RemovedFromWhitelist(account);
    }

    /**
     * @dev Checks if an account is whitelisted.
     */
    function isWhitelisted(
        address account
    ) external view returns (bool) {
        return _getWhitelistStorage().isWhitelisted[account];
    }

    /**
     * @dev Toggles transfer restrictions. When transfersAllowed is true, anyone can transfer tokens.
     * When false, only whitelisted addresses can send/receive tokens.
     */
    function setTransfersAllowed(
        bool allowed
    ) external onlyRole(ADMIN_ROLE) {
        _getWhitelistStorage().transfersAllowed = allowed;
        emit TransfersRestrictionToggled(allowed);
    }

    /**
     * @dev Returns true if token transfers are currently unrestricted (open to all).
     */
    function transfersAllowed() external view returns (bool) {
        return _getWhitelistStorage().transfersAllowed;
    }

    /**
     * @dev Returns all whitelisted addresses (for off-chain viewing purposes)
     */
    function getWhitelistedAddresses() external view returns (address[] memory) {
        WhitelistStorage storage ws = _getWhitelistStorage();
        uint256 length = ws.whitelistedAddresses.length();
        address[] memory addresses = new address[](length);

        for (uint256 i = 0; i < length; i++) {
            addresses[i] = ws.whitelistedAddresses.at(i);
        }

        return addresses;
    }

    /**
     * @dev Authorization for upgrades
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER_ROLE) { }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(AccessControlEnumerableUpgradeable /*, UUPSUpgradeable? Check exact hierarchy if needed */ )
        returns (bool)
    {
        return AccessControlEnumerableUpgradeable.supportsInterface(interfaceId);
    }

    // Override internal access control functions to resolve inheritance conflict
    function _grantRole(
        bytes32 role,
        address account
    ) internal virtual override(AccessControlEnumerableUpgradeable) returns (bool) {
        return AccessControlEnumerableUpgradeable._grantRole(role, account);
    }

    function _revokeRole(
        bytes32 role,
        address account
    ) internal virtual override(AccessControlEnumerableUpgradeable) returns (bool) {
        return AccessControlEnumerableUpgradeable._revokeRole(role, account);
    }

}
