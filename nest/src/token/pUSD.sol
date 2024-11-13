// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { ComponentToken } from "../ComponentToken.sol";
import { IComponentToken } from "../interfaces/IComponentToken.sol";

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
 * @notice Implementation of the abstract ComponentToken for Plume USD stablecoin using Boring Vault
 */
contract pUSD is ComponentToken {

    // ========== STORAGE ==========
    /// @custom:storage-location erc7201:plume.storage.pUSD
    struct pUSDStorage {
        IVault vault;
        bool paused;
        string tokenName;
        string tokenSymbol;
        uint8 tokenDecimals;
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.pUSD")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PUSD_STORAGE_LOCATION =
        0x54ae4f9578cdf7faaee986bff2a08b358f01b852b4da3af4f67309dae312ee00;

    function _getpUSDStorage() private pure returns (pUSDStorage storage $) {
        bytes32 position = PUSD_STORAGE_POSITION;
        assembly {
            $.slot := position
        }
    }

    // ========== EVENTS ==========
    event VaultChanged(address oldVault, address newVault);
    event Paused(address account);
    event Unpaused(address account);

    // ========== ROLES ==========
    bytes32 public constant VAULT_ADMIN_ROLE = keccak256("VAULT_ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // ========== MODIFIERS ==========
    modifier whenNotPaused() {
        require(!_getpUSDStorage().paused, "pUSD: paused");
        _;
    }

    /**
     * @notice Prevent the implementation contract from being initialized or reinitialized
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize pUSD
     * @param owner Address of the owner of pUSD
     * @param asset_ Address of the underlying asset
     * @param vault_ Address of the Boring Vault
     */
    function initialize(address owner, IERC20 asset_, address vault_) public initializer {
        ComponentToken.initialize(owner, "", "", asset_, false, false);

        pUSDStorage storage $ = _getpUSDStorage();
        $.vault = IVault(vault_);
        $.tokenName = "Plume USD";
        $.tokenSymbol = "pUSD";
        $.tokenDecimals = 6;

        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(VAULT_ADMIN_ROLE, owner);
        _grantRole(PAUSER_ROLE, owner);
        _grantRole(UPGRADER_ROLE, owner);
    }

    // ========== ADMIN FUNCTIONS ==========
    function setVault(
        address newVault
    ) external onlyRole(VAULT_ADMIN_ROLE) {
        pUSDStorage storage $ = _getpUSDStorage();
        address oldVault = address($.vault);
        $.vault = IVault(newVault);
        emit VaultChanged(oldVault, newVault);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _getpUSDStorage().paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _getpUSDStorage().paused = false;
        emit Unpaused(msg.sender);
    }

    // ========== VIEW FUNCTIONS ==========
    function vault() external view returns (address) {
        return address(_getpUSDStorage().vault);
    }

    // ========== COMPONENT TOKEN INTEGRATION ==========
    function deposit(
        uint256 assets,
        address receiver,
        address controller
    ) public virtual override whenNotPaused returns (uint256 shares) {
        shares = super.deposit(assets, receiver, controller);
        _getpUSDStorage().vault.enter(address(this), address(asset()), assets, receiver, shares);
        return shares;
    }

    function redeem(
        uint256 shares,
        address receiver,
        address controller
    ) public virtual override whenNotPaused returns (uint256 assets) {
        assets = super.redeem(shares, receiver, controller);
        _getpUSDStorage().vault.exit(receiver, address(asset()), assets, address(this), shares);
        return assets;
    }

    // ========== ERC20 FUNCTIONS ==========
    function transfer(
        address to,
        uint256 amount
    ) public virtual override(ERC20Upgradeable, IERC20) whenNotPaused returns (bool) {
        return _getpUSDStorage().vault.transferFrom(msg.sender, to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override(ERC20Upgradeable, IERC20) whenNotPaused returns (bool) {
        return _getpUSDStorage().vault.transferFrom(from, to, amount);
    }

    function balanceOf(
        address account
    ) public view virtual override(ERC20Upgradeable, IERC20) returns (uint256) {
        return _getpUSDStorage().vault.balanceOf(account);
    }

}
