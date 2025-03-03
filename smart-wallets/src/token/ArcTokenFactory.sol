// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./ArcToken.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title ArcTokenFactory
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Factory contract for creating new ArcToken instances with proper initialization
 * @dev Uses ERC1967 proxy pattern for upgradeable tokens
 */
contract ArcTokenFactory is Initializable, AccessControlUpgradeable, UUPSUpgradeable {

    /// @custom:storage-location erc7201:arc.factory.storage
    struct FactoryStorage {
        address initialImplementation;
        mapping(bytes32 => bool) allowedImplementations;
    }

    // Calculate unique storage slot
    bytes32 private constant FACTORY_STORAGE_LOCATION = keccak256("arc.factory.storage");

    function _getFactoryStorage() private pure returns (FactoryStorage storage fs) {
        bytes32 position = FACTORY_STORAGE_LOCATION;
        assembly {
            fs.slot := position
        }
    }

    // Events
    event TokenCreated(
        address indexed tokenAddress, address indexed owner, string name, string symbol, string assetName
    );
    event ImplementationWhitelisted(address indexed implementation);
    event ImplementationRemoved(address indexed implementation);

    /**
     * @dev Initialize the factory with the initial token implementation
     * @param _initialImplementation Address of the initial ArcToken implementation
     */
    function initialize(
        address _initialImplementation
    ) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        FactoryStorage storage fs = _getFactoryStorage();
        fs.initialImplementation = _initialImplementation;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        // Whitelist the initial implementation
        bytes32 codeHash;
        assembly {
            codeHash := extcodehash(_initialImplementation)
        }
        fs.allowedImplementations[codeHash] = true;
        emit ImplementationWhitelisted(_initialImplementation);
    }

    /**
     * @dev Creates a new ArcToken instance
     * @param name Token name
     * @param symbol Token symbol
     * @param assetName Name of the underlying asset
     * @param assetValuation Initial valuation in yield token units
     * @param initialSupply Initial token supply
     * @param yieldToken Address of the yield token (e.g., USDC)
     * @return Address of the newly created token
     */
    function createToken(
        string memory name,
        string memory symbol,
        string memory assetName,
        uint256 assetValuation,
        uint256 initialSupply,
        address yieldToken
    ) external returns (address) {
        FactoryStorage storage fs = _getFactoryStorage();

        // Create initialization data
        bytes memory initData = abi.encodeWithSelector(
            ArcToken.initialize.selector, name, symbol, assetName, assetValuation, initialSupply, yieldToken
        );

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(fs.initialImplementation, initData);

        emit TokenCreated(address(proxy), msg.sender, name, symbol, assetName);

        return address(proxy);
    }

    /**
     * @dev Adds a new implementation to the whitelist
     * @param newImplementation Address of the new implementation
     */
    function whitelistImplementation(
        address newImplementation
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        FactoryStorage storage fs = _getFactoryStorage();
        bytes32 codeHash;
        assembly {
            codeHash := extcodehash(newImplementation)
        }
        fs.allowedImplementations[codeHash] = true;
        emit ImplementationWhitelisted(newImplementation);
    }

    /**
     * @dev Removes an implementation from the whitelist
     * @param implementation Address of the implementation to remove
     */
    function removeWhitelistedImplementation(
        address implementation
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        FactoryStorage storage fs = _getFactoryStorage();
        bytes32 codeHash;
        assembly {
            codeHash := extcodehash(implementation)
        }
        fs.allowedImplementations[codeHash] = false;
        emit ImplementationRemoved(implementation);
    }

    /**
     * @dev Checks if an implementation is whitelisted
     * @param implementation Address of the implementation to check
     * @return bool True if implementation is whitelisted
     */
    function isImplementationWhitelisted(
        address implementation
    ) external view returns (bool) {
        FactoryStorage storage fs = _getFactoryStorage();
        bytes32 codeHash;
        assembly {
            codeHash := extcodehash(implementation)
        }
        return fs.allowedImplementations[codeHash];
    }

    /**
     * @dev Authorization for upgrades
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

}
