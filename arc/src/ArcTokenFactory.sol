// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./ArcToken.sol";
import "./proxy/ArcTokenProxy.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
//import "@openzeppelin/contracts/proxy/ERC1967/ArcTokenProxy.sol";

/**
 * @title ArcTokenFactory
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Factory contract for creating new ArcToken instances with proper initialization
 * @dev Uses ERC1967 proxy pattern for upgradeable tokens, deploying a fresh implementation for each token
 */
contract ArcTokenFactory is Initializable, AccessControlUpgradeable, UUPSUpgradeable {

    /// @custom:storage-location erc7201:arc.factory.storage
    struct FactoryStorage {
        // Maps token proxies to their implementations
        mapping(address => address) tokenToImplementation;
        // Track allowed implementation contracts (for future upgrades)
        mapping(bytes32 => bool) allowedImplementations;
    }

    // Custom errors
    error ImplementationNotWhitelisted();
    error TokenNotCreatedByFactory();

    // Events
    event TokenCreated(
        address indexed tokenAddress,
        address indexed owner,
        address indexed implementation,
        string name,
        string symbol,
        string tokenUri,
        uint8 decimals
    );
    event ImplementationWhitelisted(address indexed implementation);
    event ImplementationRemoved(address indexed implementation);
    event TokenUpgraded(address indexed token, address indexed newImplementation);

    // Calculate unique storage slot
    bytes32 private constant FACTORY_STORAGE_LOCATION = keccak256("arc.factory.storage");

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
     * @dev Creates a new ArcToken instance with its own implementation (with default 18 decimals)
     * This overload provides backward compatibility with existing integration code
     * @param name Token name
     * @param symbol Token symbol
     * @param initialSupply Initial token supply
     * @param yieldToken Address of the yield token (e.g., USDC)
     * @param tokenUri URI for the token metadata
     * @param initialTokenHolder Address that will receive the initial token supply (if address(0), defaults to
     * msg.sender)
     * @return Address of the newly created token
     */
    function createToken(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        address yieldToken,
        string memory tokenUri,
        address initialTokenHolder
    ) external returns (address) {
        FactoryStorage storage fs = _getFactoryStorage();

        // Deploy a fresh implementation for this token
        ArcToken implementation = new ArcToken();

        // Add the implementation to the whitelist
        bytes32 codeHash = _getCodeHash(address(implementation));
        fs.allowedImplementations[codeHash] = true;

        // Use caller as token holder if not specified
        address tokenHolder = initialTokenHolder == address(0) ? msg.sender : initialTokenHolder;

        // Create initialization data with default decimals (18)
        bytes memory initData = abi.encodeWithSelector(
            ArcToken.initialize.selector, name, symbol, initialSupply, yieldToken, tokenHolder, 18
        );

        // Deploy proxy with the fresh implementation
        ArcTokenProxy proxy = new ArcTokenProxy(address(implementation), initData);

        // Store the mapping between token and its implementation
        fs.tokenToImplementation[address(proxy)] = address(implementation);

        // Set the token URI
        ArcToken token = ArcToken(address(proxy));
        token.setTokenURI(tokenUri);

        // Grant all necessary roles to the owner
        token.grantRole(token.ADMIN_ROLE(), msg.sender);
        token.grantRole(token.MANAGER_ROLE(), msg.sender);
        token.grantRole(token.YIELD_MANAGER_ROLE(), msg.sender);
        token.grantRole(token.YIELD_DISTRIBUTOR_ROLE(), msg.sender);
        token.grantRole(token.MINTER_ROLE(), msg.sender);
        token.grantRole(token.BURNER_ROLE(), msg.sender);
        token.grantRole(token.UPGRADER_ROLE(), msg.sender);

        // Make sure the owner is whitelisted
        try token.addToWhitelist(msg.sender) { }
        catch (bytes memory) {
            // Owner might already be whitelisted from initialization
        }

        emit TokenCreated(address(proxy), msg.sender, address(implementation), name, symbol, tokenUri, 18);
        emit ImplementationWhitelisted(address(implementation));

        return address(proxy);
    }

    /**
     * @dev Creates a new ArcToken instance with its own implementation
     * @param name Token name
     * @param symbol Token symbol
     * @param initialSupply Initial token supply
     * @param yieldToken Address of the yield token (e.g., USDC)
     * @param tokenUri URI for the token metadata
     * @param initialTokenHolder Address that will receive the initial token supply (if address(0), defaults to
     * msg.sender)
     * @param decimals Number of decimal places for the token (default is 18 if 0 is provided)
     * @return Address of the newly created token
     */
    function createToken(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        address yieldToken,
        string memory tokenUri,
        address initialTokenHolder,
        uint8 decimals
    ) external returns (address) {
        FactoryStorage storage fs = _getFactoryStorage();

        // Deploy a fresh implementation for this token
        ArcToken implementation = new ArcToken();

        // Add the implementation to the whitelist for future upgrades
        bytes32 codeHash = _getCodeHash(address(implementation));
        fs.allowedImplementations[codeHash] = true;

        // Use caller as token holder if not specified
        address tokenHolder = initialTokenHolder == address(0) ? msg.sender : initialTokenHolder;

        // Create initialization data with specified decimals
        bytes memory initData = abi.encodeWithSelector(
            ArcToken.initialize.selector, name, symbol, initialSupply, yieldToken, tokenHolder, decimals
        );

        // Deploy proxy with the fresh implementation
        ArcTokenProxy proxy = new ArcTokenProxy(address(implementation), initData);

        // Store the mapping between token and its implementation
        fs.tokenToImplementation[address(proxy)] = address(implementation);

        // Set the token URI
        ArcToken token = ArcToken(address(proxy));
        token.setTokenURI(tokenUri);

        // Grant all necessary roles to the owner
        // Note: DEFAULT_ADMIN_ROLE is already granted during initialization
        token.grantRole(token.ADMIN_ROLE(), msg.sender);
        token.grantRole(token.MANAGER_ROLE(), msg.sender);
        token.grantRole(token.YIELD_MANAGER_ROLE(), msg.sender);
        token.grantRole(token.YIELD_DISTRIBUTOR_ROLE(), msg.sender);
        token.grantRole(token.MINTER_ROLE(), msg.sender);
        token.grantRole(token.BURNER_ROLE(), msg.sender);
        token.grantRole(token.UPGRADER_ROLE(), msg.sender);

        // Make sure the owner is whitelisted
        try token.addToWhitelist(msg.sender) { }
        catch (bytes memory) {
            // Owner might already be whitelisted from initialization, so ignore errors
        }

        emit TokenCreated(address(proxy), msg.sender, address(implementation), name, symbol, tokenUri, decimals);
        emit ImplementationWhitelisted(address(implementation));

        return address(proxy);
    }

    /**
     * @dev Helper function to get code hash of an address
     */
    function _getCodeHash(
        address addr
    ) internal view returns (bytes32 codeHash) {
        assembly {
            codeHash := extcodehash(addr)
        }
    }

    /**
     * @dev Get the implementation address for a specific token
     * @param token Address of the token
     * @return The implementation address for this token
     */
    function getTokenImplementation(
        address token
    ) external view returns (address) {
        return _getFactoryStorage().tokenToImplementation[token];
    }

    /**
     * @dev Upgrades a token to a new implementation
     * @param token Token address to upgrade
     * @param newImplementation Address of the new implementation
     */
    function upgradeToken(address token, address newImplementation) external onlyRole(DEFAULT_ADMIN_ROLE) {
        FactoryStorage storage fs = _getFactoryStorage();

        // Ensure the token was created by this factory
        if (fs.tokenToImplementation[token] == address(0)) {
            revert TokenNotCreatedByFactory();
        }

        // Ensure the new implementation is whitelisted
        bytes32 codeHash = _getCodeHash(newImplementation);
        if (!fs.allowedImplementations[codeHash]) {
            revert ImplementationNotWhitelisted();
        }

        // Perform the upgrade (this assumes the token implements UUPSUpgradeable)
        UUPSUpgradeable(token).upgradeToAndCall(newImplementation, "");

        // Update the implementation mapping
        fs.tokenToImplementation[token] = newImplementation;

        emit TokenUpgraded(token, newImplementation);
    }

    /**
     * @dev Adds a new implementation to the whitelist
     * @param newImplementation Address of the new implementation
     */
    function whitelistImplementation(
        address newImplementation
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        FactoryStorage storage fs = _getFactoryStorage();
        bytes32 codeHash = _getCodeHash(newImplementation);
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
        bytes32 codeHash = _getCodeHash(implementation);
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
        bytes32 codeHash = _getCodeHash(implementation);
        return fs.allowedImplementations[codeHash];
    }

    /**
     * @dev Authorization for upgrades
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

}
