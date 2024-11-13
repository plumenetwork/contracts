// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

/**
 * @title pUSD
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Unified Plume USD stablecoin
 */
contract pUSD is Initializable, ERC20Upgradeable, AccessControlUpgradeable, UUPSUpgradeable {

    // Constants

    /// @notice Role for the admin of pUSD
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @notice Role for the upgrader of pUSD
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // Initializer

    /**
     * @notice Prevent the implementation contract from being initialized or reinitialized
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize pUSD
     * @dev Give all roles to the admin address passed into the constructor
     * @param owner_ Address of the owner of pUSD
     */
    function initialize(
        address owner_
    ) public initializer {
        __ERC20_init("Plume USD", "pUSD");
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, owner_);
        _grantRole(ADMIN_ROLE, owner_);
        _grantRole(UPGRADER_ROLE, owner_);
    }

    // Override Functions

    /**
     * @notice Revert when `msg.sender` is not authorized to upgrade the contract
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER_ROLE) { }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function name() public pure override returns (string memory) {
        return "Plume USD";
    }

    function symbol() public pure override returns (string memory) {
        return "pUSD";
    }

}
