// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import { BoringVault } from "./BoringVault.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";

/**
 * @title pUSD
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Unified Plume USD stablecoin
 */
contract pUSD is Initializable, ERC20Upgradeable, AccessControlUpgradeable, UUPSUpgradeable {

    using SafeTransferLib for ERC20;

    // ========== ROLES ==========

    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant VAULT_ADMIN_ROLE = keccak256("VAULT_ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // ========== STATE VARIABLES ==========

    /// @notice The vault contract for internal accounting
    IVault public vault;

    /// @notice Whether transfers are paused
    bool public paused;

    // ========== EVENTS ==========

    event VaultChanged(address oldVault, address newVault);
    event Paused(address account);
    event Unpaused(address account);

    // ========== MODIFIERS ==========

    modifier whenNotPaused() {
        require(!paused, "PUSD: paused");
        _;
    }

    // ========== CONSTRUCTOR & INITIALIZER ==========

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
    function initialize(address _vault, address admin) external initializer {
        __ERC20_init("", ""); // Empty strings since we override name() and symbol()
        __AccessControl_init();
        __UUPSUpgradeable_init();

        vault = IVault(_vault);

        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(BURNER_ROLE, admin);
        _grantRole(VAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    // ========== METADATA OVERRIDES ==========

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function name() public pure override returns (string memory) {
        return "Plume USD";
    }

    function symbol() public pure override returns (string memory) {
        return "pUSD";
    }

    // ========== ADMIN FUNCTIONS ==========

    function setVault(
        address newVault
    ) external onlyRole(VAULT_ADMIN_ROLE) {
        address oldVault = address(vault);
        vault = IVault(newVault);
        emit VaultChanged(oldVault, newVault);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        paused = false;
        emit Unpaused(msg.sender);
    }

    // Required override for UUPSUpgradeable
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER_ROLE) { }

    // ========== ERC20 OVERRIDES ==========

    function transfer(address to, uint256 amount) public override whenNotPaused returns (bool) {
        address owner = _msgSender();
        bool success = super.transfer(to, amount);

        // Perform actual transfer in vault
        vault.transferFrom(owner, to, amount);

        return success;
    }

    function transferFrom(address from, address to, uint256 amount) public override whenNotPaused returns (bool) {
        bool success = super.transferFrom(from, to, amount);

        // Perform actual transfer in vault
        vault.transferFrom(from, to, amount);

        return success;
    }

    function approve(address spender, uint256 amount) public override whenNotPaused returns (bool) {
        bool success = super.approve(spender, amount);

        // Approve in vault as well
        vault.approve(spender, amount);

        return success;
    }

    // ========== MINT/BURN ==========

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);

        // Mint in vault
        vault.enter(address(this), address(this), 0, to, amount);
    }

    function burn(address from, uint256 amount) external onlyRole(BURNER_ROLE) {
        _burn(from, amount);

        // Burn in vault
        vault.exit(address(this), address(this), 0, from, amount);
    }

    // ========== INTERFACE SUPPORT ==========

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(AccessControlUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

}
