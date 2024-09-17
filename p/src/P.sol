// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { ERC20BurnableUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import { ERC20PausableUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import { ERC20PermitUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

/**
 * @title P
 * @author Eugene Y. Q. Shen
 * @notice ERC20 token that is the governance token for Plume Network
 */
contract P is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    ERC20PausableUpgradeable,
    AccessControlUpgradeable,
    ERC20PermitUpgradeable,
    UUPSUpgradeable
{

    // Constants

    /// @notice Role for the admin of P
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @notice Role for the upgrader of P
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    /// @notice Role for the minter of P
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    /// @notice Role for the burner of P
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    /// @notice Role for the pauser of P
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // Initializer

    /**
     * @notice Prevent the implementation contract from being initialized or reinitialized
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize P
     * @dev Give all roles to the admin address passed into the constructor
     * @param owner Address of the owner of P
     */
    function initialize(address owner) public initializer {
        __ERC20_init("Plume", "P");
        __ERC20Burnable_init();
        __ERC20Pausable_init();
        __AccessControl_init();
        __ERC20Permit_init("Plume");
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(ADMIN_ROLE, owner);
        _grantRole(MINTER_ROLE, owner);
        _grantRole(BURNER_ROLE, owner);
        _grantRole(PAUSER_ROLE, owner);
        _grantRole(UPGRADER_ROLE, owner);
    }

    // Override Functions

    /**
     * @notice Revert when `msg.sender` is not authorized to upgrade the contract
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) { }

    /**
     * @notice Update the balance of `from` and `to` after token transfer
     * @param from Address to transfer tokens from
     * @param to Address to transfer tokens to
     * @param value Amount of tokens to transfer
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20Upgradeable, ERC20PausableUpgradeable) {
        super._update(from, to, value);
    }

    // User Functions

    /**
     * @notice Mint new P tokens
     * @dev Only the minter can mint new tokens
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /**
     * @notice Burn P tokens
     * @dev Only the burner can burn tokens
     * @param from Address to burn tokens from
     * @param amount Amount of tokens to burn
     */
    function burn(address from, uint256 amount) external onlyRole(BURNER_ROLE) {
        _burn(from, amount);
    }

    /**
     * @notice Pause the contract
     * @dev Only the pauser can pause the contract
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause the contract
     * @dev Only the pauser can unpause the contract
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

}
