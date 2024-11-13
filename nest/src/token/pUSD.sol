// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";

interface BeforeTransferHook {

    function beforeTransfer(address from, address to, address operator) external view;

}

interface IVault {

    function enter(address from, address asset, uint256 assetAmount, address to, uint256 shareAmount) external;
    function exit(address to, address asset, uint256 assetAmount, address from, uint256 shareAmount) external;
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function manage(address target, bytes calldata data, uint256 value) external returns (bytes memory);
    function manage(
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values
    ) external returns (bytes[] memory);
    function setBeforeTransferHook(
        address hook
    ) external;

}

/**
 * @title pUSD
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Unified Plume USD stablecoin
 */
contract PUSD is Initializable, ERC20Upgradeable, AccessControlUpgradeable, UUPSUpgradeable {

    using SafeTransferLib for ERC20;

    // ========== ROLES ==========
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant VAULT_ADMIN_ROLE = keccak256("VAULT_ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // ========== STATE VARIABLES ==========
    IVault public vault;
    bool public paused;
    BeforeTransferHook public hook;

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
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _vault, address admin) external initializer {
        __ERC20_init("", ""); // Empty strings since we override name() and symbol()
        __AccessControl_init();
        __UUPSUpgradeable_init();

        vault = IVault(_vault);

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

    function setBeforeTransferHook(
        address _hook
    ) external onlyRole(VAULT_ADMIN_ROLE) {
        hook = BeforeTransferHook(_hook);
        vault.setBeforeTransferHook(_hook);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        paused = false;
        emit Unpaused(msg.sender);
    }

    function manage(
        address target,
        bytes calldata data,
        uint256 value
    ) external onlyRole(VAULT_ADMIN_ROLE) returns (bytes memory) {
        return vault.manage(target, data, value);
    }

    function manage(
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values
    ) external onlyRole(VAULT_ADMIN_ROLE) returns (bytes[] memory) {
        return vault.manage(targets, data, values);
    }

    // Required override for UUPSUpgradeable
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER_ROLE) { }

    // ========== TRANSFER HOOKS ==========
    function _callBeforeTransfer(
        address from
    ) internal view {
        if (address(hook) != address(0)) {
            hook.beforeTransfer(from);
        }
    }

    // ========== ERC20 OVERRIDES ==========
    function transfer(address to, uint256 amount) public override whenNotPaused returns (bool) {
        _callBeforeTransfer(msg.sender);
        bool success = super.transfer(to, amount);
        vault.transferFrom(msg.sender, to, amount);
        return success;
    }

    function transferFrom(address from, address to, uint256 amount) public override whenNotPaused returns (bool) {
        _callBeforeTransfer(from);
        bool success = super.transferFrom(from, to, amount);
        vault.transferFrom(from, to, amount);
        return success;
    }

    function approve(address spender, uint256 amount) public override whenNotPaused returns (bool) {
        bool success = super.approve(spender, amount);
        vault.approve(spender, amount);
        return success;
    }

    // ========== MINT/BURN ==========
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
        vault.enter(address(this), address(this), 0, to, amount);
    }

    function burn(address from, uint256 amount) external onlyRole(BURNER_ROLE) {
        _burn(from, amount);
        vault.exit(address(this), address(this), 0, from, amount);
    }

    // ========== INTERFACE SUPPORT ==========
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(AccessControlUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

}
