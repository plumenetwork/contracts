// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

import { IComponentToken } from "../interfaces/IComponentToken.sol";

import { ITeller } from "../interfaces/ITeller.sol";
import { IVault } from "../interfaces/IVault.sol";

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import { ComponentToken } from "../ComponentToken.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
/**
 * @title pUSD
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Unified Plume USD stablecoin
 */

contract pUSD is
    Initializable,
    ERC20Upgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ComponentToken,
    ReentrancyGuardUpgradeable
{

    using SafeERC20 for IERC20;
    using Math for uint256;

    // ========== ERRORS ==========
    error ZeroAddress();

    error InvalidAsset();
    error InvalidReceiver();
    error InvalidController();
    error InvalidVault();

    error AssetNotSupported();
    error TellerPaused();

    // ========== STORAGE ==========
    /// @custom:storage-location erc7201:plume.storage.pUSD

    struct pUSDStorage {
        IVault vault;
        uint8 tokenDecimals;
        string tokenName;
        string tokenSymbol;
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.pUSD")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PUSD_STORAGE_LOCATION = 0x54ae4f9578cdf7faaee986bff2a08b358f01b852b4da3af4f67309dae312ee00;

    function _getpUSDStorage() private pure returns (pUSDStorage storage $) {
        bytes32 position = PUSD_STORAGE_LOCATION;
        assembly {
            $.slot := position
        }
    }

    // ========== EVENTS ==========
    event VaultChanged(address oldVault, address newVault);

    // ========== ROLES ==========
    bytes32 public constant VAULT_ADMIN_ROLE = keccak256("VAULT_ADMIN_ROLE");

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
    //
    function initialize(address owner, IERC20 asset_, address vault_) public initializer {
        require(owner != address(0), "Zero address owner");
        require(address(asset_) != address(0), "Zero address asset");
        require(vault_ != address(0), "Zero address vault");

        // Validate asset interface support
        try IERC20Metadata(address(asset_)).decimals() returns (uint8) { }
        catch {
            revert InvalidAsset();
        }

        super.initialize(owner, "Plume USD", "pUSD", asset_, false, false);
        __ReentrancyGuard_init();

        pUSDStorage storage $ = _getpUSDStorage();
        $.vault = IVault(vault_);

        _grantRole(VAULT_ADMIN_ROLE, owner);
    }

    // ========== ADMIN FUNCTIONS ==========

    /**
     * @notice Set a new vault address for the pUSD token
     * @param newVault Address of the new vault to be set
     */
    function setVault(
        address newVault
    ) external nonReentrant onlyRole(VAULT_ADMIN_ROLE) {
        if (newVault == address(0)) {
            revert InvalidVault();
        }

 
        // Validate teller interface support
        // TODO: this should rather validate some function in the vault contract.
        try ITeller(newVault).isPaused() returns (bool) { }
        catch {
            revert InvalidVault();
        }

        pUSDStorage storage $ = _getpUSDStorage();
        address oldVault = address($.vault);
        $.vault = IVault(newVault);
        emit VaultChanged(oldVault, newVault);
    }

    // ========== VIEW FUNCTIONS ==========

    /**
     * @notice Get the current vault address
     * @return Address of the current vault
     */
    function vault() external view returns (address) {
        return address(_getpUSDStorage().vault);
    }

    // ========== COMPONENT TOKEN INTEGRATION ==========

    /**
     * @notice Deposit assets and mint corresponding shares
     * @param assets Amount of assets to deposit
     * @param receiver Address that will receive the shares
     * @param controller Address that will control the shares (unused in this implementation)
     * @return shares Amount of shares minted
     */
    function deposit(
        uint256 assets,
        address receiver,
        address controller
    ) public virtual override nonReentrant returns (uint256 shares) {
        if (receiver == address(0)) {
            revert InvalidReceiver();
        }

        ITeller teller = ITeller(address(_getpUSDStorage().vault));

        // Verify deposit is allowed through teller
        if (teller.isPaused()) {
            revert TellerPaused();
        }
        if (!teller.isSupported(IERC20(asset()))) {
            revert AssetNotSupported();
        }

        // Calculate shares to mint
        shares = previewDeposit(assets);

        // Approve teller to spend assets
        IERC20 assetToken = IERC20(asset());
        assetToken.safeIncreaseAllowance(address(teller), assets);

        // Deposit through teller
        shares = teller.deposit(IERC20(asset()), assets, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /**
     * @notice Burn shares and withdraw corresponding assets
     * @param shares Amount of shares to burn
     * @param receiver Address that will receive the assets
     * @param controller Address that currently controls the shares
     * @return assets Amount of assets withdrawn
     */
    function redeem(
        uint256 shares,
        address receiver,
        address controller
    ) public virtual override nonReentrant returns (uint256 assets) {
        if (receiver == address(0)) {
            revert InvalidReceiver();
        }
        if (controller == address(0)) {
            revert InvalidController();
        }

        // Calculate expected assets
        assets = previewRedeem(shares);

        ITeller teller = ITeller(address(_getpUSDStorage().vault));

        // Use teller's bulkWithdraw for redemption
        assets = teller.bulkWithdraw(IERC20(asset()), shares, assets, receiver);

        emit Withdraw(msg.sender, receiver, controller, assets, shares);
    }

    /// @inheritdoc ERC4626Upgradeable
    function convertToShares(
        uint256 assets
    ) public view virtual override returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    /// @inheritdoc ERC4626Upgradeable
    function convertToAssets(
        uint256 shares
    ) public view virtual override returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Floor);
    }

    // ========== ERC20 OVERRIDES ==========

    /**
     * @notice Transfer tokens to a specified address
     * @param to Address to transfer tokens to
     * @param amount Amount of tokens to transfer
     * @return bool indicating whether the transfer was successful
     */
    function transfer(
        address to,
        uint256 amount
    ) public virtual override(ERC20Upgradeable, IERC20) nonReentrant returns (bool) {
        // Since balances are tracked in the vault, we only need to update the vault's records
        return _getpUSDStorage().vault.transferFrom(msg.sender, to, amount);
    }

    /**
     * @notice Transfer tokens from one address to another
     * @param from Address to transfer tokens from
     * @param to Address to transfer tokens to
     * @param amount Amount of tokens to transfer
     * @return bool indicating whether the transfer was successful
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override(ERC20Upgradeable, IERC20) nonReentrant returns (bool) {
        require(from != address(0), "ERC20: transfer from zero address");
        require(to != address(0), "ERC20: transfer to zero address");

        // Handle allowance using OpenZeppelin's ERC20 spending mechanism
        if (from != msg.sender) {
            _spendAllowance(from, msg.sender, amount);
        }

        // Delegate the actual transfer to the vault
        return _getpUSDStorage().vault.transferFrom(from, to, amount);
    }

    /**
     * @notice Get the token balance of an account
     * @param account Address to check balance for
     * @return Balance of the account
     */
    function balanceOf(
        address account
    ) public view override(IERC20, ERC20Upgradeable) returns (uint256) {
        return _getpUSDStorage().vault.balanceOf(account);
    }

    // ========== METADATA OVERRIDES ==========

    /**
     * @notice Get the number of decimals for the token
     * @return Number of decimals (6)
     */
    function decimals() public pure override(ERC4626Upgradeable, ERC20Upgradeable, IERC20Metadata) returns (uint8) {
        return 6;
    }

    /**
     * @notice Get the name of the token
     * @return Name of the token
     */
    function name() public pure override(ERC20Upgradeable, IERC20Metadata) returns (string memory) {
        return "Plume USD";
    }

    /**
     * @notice Get the symbol of the token
     * @return Symbol of the token
     */
    function symbol() public pure override(ERC20Upgradeable, IERC20Metadata) returns (string memory) {
        return "pUSD";
    }

    /**
     * @notice Check if the contract supports a given interface
     * @param interfaceId Interface identifier to check
     * @return bool indicating whether the interface is supported
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(AccessControlUpgradeable, ComponentToken) returns (bool) {
        return interfaceId == type(IERC20).interfaceId || interfaceId == type(IAccessControl).interfaceId
            || super.supportsInterface(interfaceId);
    }

}
