// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./WhitelistRestrictions.sol";
import "./ITransferRestrictions.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title RestrictionsFactory
 * @author Alp Guneysel
 * @notice Factory for creating and managing token transfer restriction modules
 * @dev Creates and upgrades restriction modules for ArcToken contracts
 */
contract RestrictionsFactory is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    
    /// @custom:storage-location erc7201:restrictions.factory.storage
    struct FactoryStorage {
        // Maps restriction proxies to their implementations
        mapping(address => address) restrictionsToImplementation;
        // Track allowed implementation contracts
        mapping(bytes32 => bool) allowedImplementations;
    }

    // Custom errors
    error ImplementationNotWhitelisted();
    error NotCreatedByFactory();

    // Events
    event RestrictionsCreated(
        address indexed restrictionsAddress,
        address indexed owner,
        address indexed implementation,
        string restrictionType
    );
    event ImplementationWhitelisted(address indexed implementation);
    event ImplementationRemoved(address indexed implementation);
    event RestrictionsUpgraded(address indexed restrictions, address indexed newImplementation);

    // Calculate unique storage slot
    bytes32 private constant FACTORY_STORAGE_LOCATION = keccak256("restrictions.factory.storage");

    function _getFactoryStorage() private pure returns (FactoryStorage storage fs) {
        bytes32 position = FACTORY_STORAGE_LOCATION;
        assembly {
            fs.slot := position
        }
    }

    /**
     * @dev Initialize the factory
     */
    function initialize() public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev Creates a new WhitelistRestrictions module
     * @param admin The address to grant admin role to in the new restrictions module
     * @return Address of the newly created restrictions module
     */
    function createWhitelistRestrictions(address admin) external returns (address) {
        // Deploy a fresh implementation
        WhitelistRestrictions implementation = new WhitelistRestrictions();
        
        // Add the implementation to the whitelist
        FactoryStorage storage fs = _getFactoryStorage();
        bytes32 codeHash = _getCodeHash(address(implementation));
        fs.allowedImplementations[codeHash] = true;
        
        // Deploy proxy with the fresh implementation
        bytes memory initData = abi.encodeWithSelector(
            WhitelistRestrictions.initialize.selector, 
            admin != address(0) ? admin : msg.sender
        );
        
        address proxy = _deployProxy(address(implementation), initData);
        
        // Store the mapping
        fs.restrictionsToImplementation[proxy] = address(implementation);
        
        emit RestrictionsCreated(proxy, msg.sender, address(implementation), "Whitelist");
        emit ImplementationWhitelisted(address(implementation));
        
        return proxy;
    }
    
    /**
     * @dev Internal helper to deploy a proxy
     */
    function _deployProxy(address implementation, bytes memory initData) internal returns (address) {
        // This is simplified - in a real implementation you'd use
        // OZ's ERC1967Proxy or a custom proxy implementation
        // For this example, we'll create a mock deployment return
        // In a real implementation, you'd deploy the proxy here
        
        // Placeholder for proxy deployment logic
        // address proxy = address(new ERC1967Proxy(implementation, initData));
        
        // For now, we'll just return the implementation as a placeholder
        // You'll need to replace this with actual proxy deployment
        return implementation;
    }

    /**
     * @dev Helper function to get code hash of an address
     */
    function _getCodeHash(address addr) internal view returns (bytes32 codeHash) {
        assembly {
            codeHash := extcodehash(addr)
        }
    }

    /**
     * @dev Get the implementation address for a specific restrictions module
     * @param restrictions Address of the restrictions module
     * @return The implementation address
     */
    function getRestrictionsImplementation(address restrictions) external view returns (address) {
        return _getFactoryStorage().restrictionsToImplementation[restrictions];
    }

    /**
     * @dev Adds a new implementation to the whitelist
     * @param newImplementation Address of the new implementation
     */
    function whitelistImplementation(address newImplementation) external onlyRole(DEFAULT_ADMIN_ROLE) {
        FactoryStorage storage fs = _getFactoryStorage();
        bytes32 codeHash = _getCodeHash(newImplementation);
        fs.allowedImplementations[codeHash] = true;
        emit ImplementationWhitelisted(newImplementation);
    }

    /**
     * @dev Removes an implementation from the whitelist
     * @param implementation Address of the implementation to remove
     */
    function removeWhitelistedImplementation(address implementation) external onlyRole(DEFAULT_ADMIN_ROLE) {
        FactoryStorage storage fs = _getFactoryStorage();
        bytes32 codeHash = _getCodeHash(implementation);
        fs.allowedImplementations[codeHash] = false;
        emit ImplementationRemoved(implementation);
    }

    /**
     * @dev Checks if an implementation is whitelisted
     * @param implementation Address of the implementation to check
     * @return bool True if implementation is whitelisted
     */
    function isImplementationWhitelisted(address implementation) external view returns (bool) {
        FactoryStorage storage fs = _getFactoryStorage();
        bytes32 codeHash = _getCodeHash(implementation);
        return fs.allowedImplementations[codeHash];
    }

    /**
     * @dev Authorization for upgrades
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
} 