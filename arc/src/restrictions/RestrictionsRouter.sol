// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./IRestrictionsRouter.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title RestrictionsRouter
 * @author Alp Guneysel
 * @notice Central router for managing and retrieving addresses of global restriction modules.
 * @dev This contract is upgradeable (UUPS) and managed by an admin role.
 */
contract RestrictionsRouter is Initializable, AccessControlUpgradeable, UUPSUpgradeable, IRestrictionsRouter {

    bytes32 public constant ROUTER_ADMIN_ROLE = keccak256("ROUTER_ADMIN_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE"); // For UUPS

    struct ModuleInfo {
        bool isGlobal; // True if the module uses a single global instance
        address globalImplementation; // Address of the global instance (if isGlobal is true)
        bool exists; // True if this typeId is registered
    }

    // Mapping from module type identifier to its info
    mapping(bytes32 => ModuleInfo) public moduleTypes;

    // Events
    event ModuleTypeRegistered(bytes32 indexed typeId, bool isGlobal, address globalImplementation);
    event ModuleTypeRemoved(bytes32 indexed typeId);
    event GlobalImplementationUpdated(bytes32 indexed typeId, address indexed newGlobalImplementation);

    // Custom Errors
    error ModuleTypeNotRegistered(bytes32 typeId);
    error ModuleTypeAlreadyRegistered(bytes32 typeId);
    error ModuleNotGlobal(bytes32 typeId);
    error ModuleIsGlobal(bytes32 typeId);
    error InvalidGlobalImplementationAddress();
    error InvalidTypeId();

    /**
     * @dev Initializes the router, setting the initial admin.
     * @param admin The address to be granted ROUTER_ADMIN_ROLE and UPGRADER_ROLE.
     */
    function initialize(
        address admin
    ) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin); // Default admin can manage roles
        _grantRole(ROUTER_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin); // Admin can upgrade
    }

    // -------------- Module Management (Admin Only) --------------

    /**
     * @dev Registers a new type of restriction module.
     * @param typeId Unique identifier for the module type (e.g., keccak256("TRANSFER_WHITELIST")).
     * @param isGlobal Set to true if this module uses a single, shared instance across all tokens.
     * @param globalImplementation Address of the shared instance (only if isGlobal is true, otherwise use address(0)).
     */
    function registerModuleType(
        bytes32 typeId,
        bool isGlobal,
        address globalImplementation
    ) external onlyRole(ROUTER_ADMIN_ROLE) {
        if (typeId == bytes32(0)) {
            revert InvalidTypeId();
        }
        if (moduleTypes[typeId].exists) {
            revert ModuleTypeAlreadyRegistered(typeId);
        }
        if (isGlobal && globalImplementation == address(0)) {
            revert InvalidGlobalImplementationAddress();
        }
        if (!isGlobal && globalImplementation != address(0)) {
            // Ensure globalImplementation is 0 if module is per-token
            globalImplementation = address(0);
        }

        moduleTypes[typeId] =
            ModuleInfo({ isGlobal: isGlobal, globalImplementation: globalImplementation, exists: true });

        emit ModuleTypeRegistered(typeId, isGlobal, globalImplementation);
    }

    /**
     * @dev Updates the global implementation address for a registered global module type.
     * @param typeId The identifier of the global module type to update.
     * @param newGlobalImplementation The new address of the global implementation.
     */
    function updateGlobalModuleImplementation(
        bytes32 typeId,
        address newGlobalImplementation
    ) external onlyRole(ROUTER_ADMIN_ROLE) {
        ModuleInfo storage moduleInfo = moduleTypes[typeId];
        if (!moduleInfo.exists) {
            revert ModuleTypeNotRegistered(typeId);
        }
        if (!moduleInfo.isGlobal) {
            revert ModuleNotGlobal(typeId);
        }
        if (newGlobalImplementation == address(0)) {
            revert InvalidGlobalImplementationAddress();
        }

        moduleInfo.globalImplementation = newGlobalImplementation;
        emit GlobalImplementationUpdated(typeId, newGlobalImplementation);
    }

    /**
     * @dev Removes a registered module type.
     * @notice Use with caution. Tokens relying on this typeId might behave unexpectedly.
     * @param typeId The identifier of the module type to remove.
     */
    function removeModuleType(
        bytes32 typeId
    ) external onlyRole(ROUTER_ADMIN_ROLE) {
        if (!moduleTypes[typeId].exists) {
            revert ModuleTypeNotRegistered(typeId);
        }
        delete moduleTypes[typeId];
        emit ModuleTypeRemoved(typeId);
    }

    // -------------- IRestrictionsRouter Implementation --------------

    /**
     * @dev Retrieves the address of a registered global module implementation.
     * @param typeId The unique identifier for the module type.
     * @return address The address of the global module implementation, or address(0) if not registered or not global.
     */
    function getGlobalModuleAddress(
        bytes32 typeId
    ) external view override returns (address) {
        ModuleInfo storage moduleInfo = moduleTypes[typeId];
        if (moduleInfo.exists && moduleInfo.isGlobal) {
            return moduleInfo.globalImplementation;
        }
        return address(0);
    }

    // -------------- View Functions --------------

    /**
     * @dev Gets the information for a registered module type.
     * @param typeId The identifier of the module type.
     * @return ModuleInfo Struct containing isGlobal, globalImplementation, and exists flags.
     */
    function getModuleInfo(
        bytes32 typeId
    ) external view returns (ModuleInfo memory) {
        return moduleTypes[typeId];
    }

    // -------------- Upgradeability --------------

    /**
     * @dev Authorization for upgrades (UUPS).
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER_ROLE) { }

}
