// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ComponentToken } from "./ComponentToken.sol";

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IVault {

    function enter(address from, address asset, uint256 assetAmount, address to, uint256 shareAmount) external;
    function exit(address to, address asset, uint256 assetAmount, address from, uint256 shareAmount) external;
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(
        address account
    ) external view returns (uint256);

}

/**
 * @title pUSD
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Unified Plume USD stablecoin implemented as both a ComponentToken and Vault-backed ERC20
 */
contract PUSD is ComponentToken {

    // ========== STORAGE ==========
    /// @custom:storage-location erc7201:plume.storage.PUSD
    struct PUSDStorage {
        IVault vault;
        bool paused;
    }

    // Using ERC-7201 namespaced storage pattern to avoid storage collisions during upgrades
    bytes32 private constant PUSD_STORAGE_LOCATION = keccak256("plume.storage.PUSD");

    function _getPUSDStorage() private pure returns (PUSDStorage storage $) {
        assembly {
            $.slot := PUSD_STORAGE_LOCATION
        }
    }

    // ========== EVENTS ==========
    event VaultChanged(address oldVault, address newVault);
    event Paused(address account);
    event Unpaused(address account);

    // ========== MODIFIERS ==========
    modifier whenNotPaused() {
        require(!_getPUSDStorage().paused, "PUSD: paused");
        _;
    }

    // ========== ROLES ==========
    bytes32 public constant VAULT_ADMIN_ROLE = keccak256("VAULT_ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // ========== CONSTRUCTOR ==========
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ========== INITIALIZER ==========
    function initialize(address admin, IERC20 asset_, address _vault) external initializer {
        // Initialize ComponentToken with pUSD metadata
        super.initialize(
            admin,
            "Plume USD",
            "pUSD",
            asset_,
            false, // synchronous deposits
            false // synchronous redemptions
        );

        PUSDStorage storage $ = _getPUSDStorage();
        $.vault = IVault(_vault);

        // Setup additional roles
        _grantRole(VAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
    }

    // ========== ADMIN FUNCTIONS ==========
    function setVault(
        address newVault
    ) external onlyRole(VAULT_ADMIN_ROLE) {
        PUSDStorage storage $ = _getPUSDStorage();
        address oldVault = address($.vault);
        $.vault = IVault(newVault);
        emit VaultChanged(oldVault, newVault);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _getPUSDStorage().paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _getPUSDStorage().paused = false;
        emit Unpaused(msg.sender);
    }

    // ========== UPGRADE FUNCTIONS ==========
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER_ROLE) { }

    // ========== GETTERS ==========
    function vault() external view returns (address) {
        return address(_getPUSDStorage().vault);
    }

    function paused() external view returns (bool) {
        return _getPUSDStorage().paused;
    }

    // ========== ERC20 OVERRIDES ==========
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function transfer(address to, uint256 amount) public override whenNotPaused returns (bool) {
        return _getPUSDStorage().vault.transferFrom(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override whenNotPaused returns (bool) {
        return _getPUSDStorage().vault.transferFrom(from, to, amount);
    }

    function approve(address spender, uint256 amount) public override whenNotPaused returns (bool) {
        bool success = super.approve(spender, amount);
        _getPUSDStorage().vault.approve(spender, amount);
        return success;
    }

    function balanceOf(
        address account
    ) public view override returns (uint256) {
        return _getPUSDStorage().vault.balanceOf(account);
    }

    // ========== COMPONENT TOKEN OVERRIDES ==========
    function deposit(
        uint256 assets,
        address receiver,
        address controller
    ) public override whenNotPaused returns (uint256 shares) {
        shares = super.deposit(assets, receiver, controller);
        _getPUSDStorage().vault.enter(address(this), address(asset()), assets, receiver, shares);
        return shares;
    }

    function redeem(
        uint256 shares,
        address receiver,
        address controller
    ) public override whenNotPaused returns (uint256 assets) {
        assets = super.redeem(shares, receiver, controller);
        _getPUSDStorage().vault.exit(receiver, address(asset()), assets, address(this), shares);
        return assets;
    }

    function convertToShares(
        uint256 assets
    ) public view override returns (uint256) {
        return assets; // 1:1 conversion for stablecoin
    }

    function convertToAssets(
        uint256 shares
    ) public view override returns (uint256) {
        return shares; // 1:1 conversion for stablecoin
    }

}
