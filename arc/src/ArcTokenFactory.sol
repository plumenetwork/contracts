// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./ArcToken.sol";
import "./proxy/ArcTokenProxy.sol";

import "./restrictions/IRestrictionsRouter.sol";
import "./restrictions/ITransferRestrictions.sol";
import "./restrictions/IYieldRestrictions.sol";
import "./restrictions/WhitelistRestrictions.sol";
import "./restrictions/YieldBlacklistRestrictions.sol";
import "./restrictions/RestrictionTypes.sol";

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title ArcTokenFactory
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Factory contract for creating new ArcToken instances and their associated restriction modules.
 * @dev Uses ERC1967 proxy pattern for upgradeable tokens. Requires a RestrictionsRouter.
 */
contract ArcTokenFactory is Initializable, AccessControlUpgradeable, UUPSUpgradeable {

    /// @custom:storage-location erc7201:arc.factory.storage
    struct FactoryStorage {
        // --- Data associated with the Factory itself ---
        address restrictionsRouter; // Store router address here as well
        mapping(bytes32 => bool) allowedImplementations; // Allowed ArcToken implementations
        // --- Data associated with TOKENS created by this factory ---
        // Maps token proxies to their implementations
        mapping(address => address) tokenToImplementation;
    }
    // Maps tokens to their restriction modules (Type => Module Address)
    // We might still want factory-level tracking if needed, but ArcToken is the source of truth.

    // Custom errors
    error ImplementationNotWhitelisted();
    error TokenNotCreatedByFactory();
    error RouterNotSet();
    error FailedToCreateRestrictionsModule();
    error FailedToSetRestrictions();

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
    event ModuleLinked(address indexed tokenAddress, address indexed moduleAddress, bytes32 indexed moduleType);
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
     * @dev Initialize the factory with the address of the RestrictionsRouter.
     * @param routerAddress The address of the deployed RestrictionsRouter proxy.
     */
    function initialize(
        address routerAddress
    ) public initializer {
        require(routerAddress != address(0), "Router address cannot be zero");
        __AccessControl_init();
        __UUPSUpgradeable_init();

        FactoryStorage storage fs = _getFactoryStorage();
        fs.restrictionsRouter = routerAddress; // Store router address

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev Internal function to create and initialize a WhitelistRestrictions module.
     * @param admin Address that will have admin privileges on the restrictions module
     * @return Address of the newly created restrictions module
     */
    function _createWhitelistRestrictionsModule(
        address admin
    ) internal returns (address) {
        // Deploy a fresh whitelist restrictions implementation
        WhitelistRestrictions implementation = new WhitelistRestrictions();

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(WhitelistRestrictions.initialize.selector, admin);

        // Deploy and initialize the module behind a proxy
        try new ERC1967Proxy(address(implementation), initData) returns (ERC1967Proxy proxy) {
            return address(proxy);
        } catch {
            revert FailedToCreateRestrictionsModule();
        }
    }

    /**
     * @dev Internal function to create and initialize a YieldBlacklistRestrictions module.
     * @param admin Address that will have admin privileges on the restrictions module
     * @return Address of the newly created restrictions module
     */
    function _createYieldBlacklistRestrictionsModule(
        address admin
    ) internal returns (address) {
        // Deploy a fresh yield blacklist restrictions implementation
        YieldBlacklistRestrictions implementation = new YieldBlacklistRestrictions();

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(YieldBlacklistRestrictions.initialize.selector, admin);

        // Deploy and initialize the module behind a proxy
        try new ERC1967Proxy(address(implementation), initData) returns (ERC1967Proxy proxy) {
            return address(proxy);
        } catch {
            revert FailedToCreateRestrictionsModule();
        }
    }

    /**
     * @dev Creates a new ArcToken instance with its own implementation and associated restriction modules.
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
        address routerAddr = fs.restrictionsRouter;
        if (routerAddr == address(0)) {
            revert RouterNotSet(); // Ensure factory is initialized with router
        }

        // Deploy a fresh implementation for this token
        ArcToken implementation = new ArcToken();

        // Add the implementation to the whitelist for future upgrades
        bytes32 codeHash = _getCodeHash(address(implementation));
        fs.allowedImplementations[codeHash] = true;

        // Use caller as token holder if not specified
        address tokenHolder = initialTokenHolder == address(0) ? msg.sender : initialTokenHolder;

        // Create initialization data with specified decimals
        bytes memory initData = abi.encodeWithSelector(
            ArcToken.initialize.selector, // Use the main initializer
            name,
            symbol,
            initialSupply,
            yieldToken,
            tokenHolder,
            decimals,
            routerAddr
        );

        // Deploy proxy with the fresh implementation
        ArcTokenProxy proxy = new ArcTokenProxy(address(implementation), initData);

        // Store the mapping between token and its implementation
        fs.tokenToImplementation[address(proxy)] = address(implementation);

        // Set the token URI
        ArcToken token = ArcToken(address(proxy));
        token.setTokenURI(tokenUri);

        // Grant all necessary roles to the owner
        // Grant the DEFAULT_ADMIN_ROLE to the deployer
        token.grantRole(token.DEFAULT_ADMIN_ROLE(), msg.sender);
        token.grantRole(token.ADMIN_ROLE(), msg.sender);
        token.grantRole(token.MANAGER_ROLE(), msg.sender);
        token.grantRole(token.YIELD_MANAGER_ROLE(), msg.sender);
        token.grantRole(token.YIELD_DISTRIBUTOR_ROLE(), msg.sender);
        token.grantRole(token.MINTER_ROLE(), msg.sender);
        token.grantRole(token.BURNER_ROLE(), msg.sender);
        token.grantRole(token.UPGRADER_ROLE(), address(this));

        // --- Create and link Restriction Modules ---

        // 1. Whitelist Module (for transfers)
        address whitelistModule = _createWhitelistRestrictionsModule(msg.sender);
        try token.setRestrictionModule(RestrictionTypes.TRANSFER_RESTRICTION_TYPE, whitelistModule) {
            emit ModuleLinked(address(proxy), whitelistModule, RestrictionTypes.TRANSFER_RESTRICTION_TYPE);
        } catch {
            revert FailedToSetRestrictions();
        }

        // 2. Yield Blacklist Module
        address yieldBlacklistModule = _createYieldBlacklistRestrictionsModule(msg.sender);
        try token.setRestrictionModule(RestrictionTypes.YIELD_RESTRICTION_TYPE, yieldBlacklistModule) {
            emit ModuleLinked(address(proxy), yieldBlacklistModule, RestrictionTypes.YIELD_RESTRICTION_TYPE);
        } catch {
            revert FailedToSetRestrictions();
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
     * @dev Get the address of the RestrictionsRouter
     * @return The address of the RestrictionsRouter
     */
    function getRestrictionsRouter() external view returns (address) {
        return _getFactoryStorage().restrictionsRouter;
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
