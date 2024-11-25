// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";

import { IComponentToken } from "../interfaces/IComponentToken.sol";

import { IAtomicQueue } from "../interfaces/IAtomicQueue.sol";

import { ITeller } from "../interfaces/ITeller.sol";
import { IVault } from "../interfaces/IVault.sol";

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import { ComponentToken } from "../ComponentToken.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

// TODO: REMOVE in production
import "forge-std/console2.sol";

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
    error InvalidSender();
    error InvalidController();
    error InvalidVault();

    error AssetNotSupported();
    error TellerPaused();

    // ========== STORAGE ==========

    struct BoringVault {
        ITeller teller;
        IVault vault;
        IAtomicQueue atomicqueue;
    }

    /// @custom:storage-location erc7201:plume.storage.pUSD
    struct pUSDStorage {
        BoringVault boringVault;
        uint8 tokenDecimals;
        string tokenName;
        string tokenSymbol;
        uint256 version;
    }

    // ========== CONSTANTS ==========
    address public constant USDC = 0x401eCb1D350407f13ba348573E5630B83638E30D;
    address public constant USDT = 0x2413b8C79Ce60045882559f63d308aE3DFE0903d;

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
    event Reinitialized(uint256 version);

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
     * @param atomicqueue_ Address of the AtomicQueue
     */
    //
    function initialize(
        address owner,
        IERC20 asset_,
        address vault_,
        address teller_,
        address atomicqueue_
    ) public initializer {
        require(owner != address(0), "Zero address owner");
        require(address(asset_) != address(0), "Zero address asset");

        require(vault_ != address(0), "Zero address vault");
        require(teller_ != address(0), "Zero address teller");
        require(atomicqueue_ != address(0), "Zero address AtomicQueue");

        // Validate asset interface support
        try IERC20Metadata(address(asset_)).decimals() returns (uint8) { }
        catch {
            revert InvalidAsset();
        }

        __UUPSUpgradeable_init(); // Add this line
        __AccessControl_init(); // Add this line
        __ERC20_init("Plume USD", "pUSD");
        __ReentrancyGuard_init();

        super.initialize(owner, "Plume USD", "pUSD", asset_, false, false);

        pUSDStorage storage $ = _getpUSDStorage();
        $.boringVault.teller = ITeller(teller_);
        $.boringVault.vault = IVault(vault_);
        $.boringVault.atomicqueue = IAtomicQueue(atomicqueue_);

        //$.vault = IVault(vault_);
        //$.atomicqueue = IAtomicQueue(atomicqueue_);
        $.version = 1; // Set initial version

        _grantRole(VAULT_ADMIN_ROLE, owner);
        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(UPGRADER_ROLE, owner); // Grant upgrader role to owner
    }

    function reinitialize(
        address owner,
        IERC20 asset_,
        address vault_,
        address teller_,
        address atomicqueue_
    ) public onlyRole(UPGRADER_ROLE) {
        // Reinitialize as needed
        require(owner != address(0), "Zero address owner");
        require(address(asset_) != address(0), "Zero address asset");

        require(vault_ != address(0), "Zero address vault");
        require(teller_ != address(0), "Zero address teller");
        require(atomicqueue_ != address(0), "Zero address AtomicQueue");

        pUSDStorage storage $ = _getpUSDStorage();

        // Increment version
        $.version += 1;
        $.boringVault.teller = ITeller(teller_);
        $.boringVault.vault = IVault(vault_);
        $.boringVault.atomicqueue = IAtomicQueue(atomicqueue_);

        _grantRole(VAULT_ADMIN_ROLE, owner);
        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(UPGRADER_ROLE, owner);

        emit Reinitialized($.version);
    }

    // ========== ADMIN FUNCTIONS ==========

    /**
     * @notice Internal function to authorize an upgrade to a new implementation
     * @dev Only callable by addresses with UPGRADER_ROLE
     * @param newImplementation Address of the new implementation contract
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override(ComponentToken, UUPSUpgradeable) onlyRole(UPGRADER_ROLE) {
        super._authorizeUpgrade(newImplementation); // Call ComponentToken's checks
    }

    // ========== VIEW FUNCTIONS ==========

    /**
     * @notice Get the current vault address
     * @return Address of the current vault
     */
    function getVault() external view returns (address) {
        return address(_getpUSDStorage().boringVault.vault);
    }

    /**
     * @notice Get the current teller address
     * @return Address of the current teller
     */
    function getTeller() external view returns (address) {
        return address(_getpUSDStorage().boringVault.teller);
    }

    /**
     * @notice Get the current AtomicQueue address
     * @return Address of the current AtomicQueue
     */
    function getAtomicqueue() external view returns (address) {
        return address(_getpUSDStorage().boringVault.atomicqueue);
    }

    /**
     * @notice Get the current pUSD version
     * @return uint256 version of the pUSD contract
     */
    function version() public view returns (uint256) {
        return _getpUSDStorage().version;
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
        address controller,
        uint256 minimumMint
    ) public virtual nonReentrant returns (uint256 shares) {
        if (receiver == address(0)) {
            revert InvalidReceiver();
        }

        ITeller teller = ITeller(address(_getpUSDStorage().boringVault.teller));

        // Verify deposit is allowed through teller
        if (teller.isPaused()) {
            revert TellerPaused();
        }
        if (!teller.isSupported(IERC20(asset()))) {
            revert AssetNotSupported();
        }

        // Transfer assets from sender to this contract first
        SafeERC20.safeTransferFrom(IERC20(asset()), msg.sender, address(this), assets);

        // Then approve teller to spend assets using forceApprove
        SafeERC20.forceApprove(IERC20(asset()), address(teller), assets);

        // Deposit through teller
        shares = teller.deposit(
            IERC20(asset()), // depositAsset
            assets, // depositAmount
            minimumMint // minimumMint
        );

        // Transfer shares to receiver
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
        return shares;
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
        address controller,
        uint256 price
    ) public virtual nonReentrant returns (uint256 assets) {
        if (receiver == address(0)) {
            revert InvalidReceiver();
        }
        if (controller == address(0)) {
            revert InvalidController();
        }

        // Get AtomicQueue from storage
        IAtomicQueue queue = _getpUSDStorage().boringVault.atomicqueue;

        // Create AtomicRequest struct
        IAtomicQueue.AtomicRequest memory request = IAtomicQueue.AtomicRequest({
            deadline: uint64(block.timestamp + 1 hours), // deadline to fulfill request
            atomicPrice: uint88(price), // In terms of want asset decimals
            offerAmount: uint96(shares), // The amount of offer asset the user wants to sell.
            inSolve: false
        });

        IERC20(address(this)).safeIncreaseAllowance(address(queue), shares);

        // Update atomic request
        queue.updateAtomicRequest(
            ERC20(address(this)), // offer token (pUSD shares)
            ERC20(asset()), // want token (underlying asset)
            request
        );

        // Get assets received from vault and transfer to receiver
        assets = IERC20(asset()).balanceOf(address(this));
        IERC20(asset()).safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, controller, assets, shares);
    }

    /**
     * @notice Calculate how many shares would be minted for a given amount of assets
     * @param assets Amount of assets to deposit
     * @return shares Amount of shares that would be minted
     */
    function previewDeposit(
        uint256 assets
    ) public view virtual override returns (uint256 shares) {
        pUSDStorage storage $ = _getpUSDStorage();

        if (address($.boringVault.vault) == address(0)) {
            revert InvalidVault();
        }
        // 1:1 conversion - 1 asset = 1 share
        return assets;
    }

    /**
     * @notice Calculate how many assets would be withdrawn for a given amount of shares
     * @param shares Amount of shares to redeem
     * @return assets Amount of assets that would be withdrawn
     */
    function previewRedeem(
        uint256 shares
    ) public view virtual override returns (uint256 assets) {
        pUSDStorage storage $ = _getpUSDStorage();
        if (address($.boringVault.vault) == address(0)) {
            revert InvalidVault();
        }
        // 1:1 conversion - 1 share = 1 asset
        return shares;
    }

    /// @inheritdoc ERC4626Upgradeable
    function convertToShares(
        uint256 assets
    ) public view virtual override returns (uint256) {
        // 1:1 conversion - 1 asset = 1 share
        return assets;
    }

    /// @inheritdoc ERC4626Upgradeable
    function convertToAssets(
        uint256 shares
    ) public view virtual override returns (uint256) {
        // 1:1 conversion - 1 share = 1 asset
        return shares;
    }

    // ========== ERC20 OVERRIDES ==========

    /**
     * @notice Transfer tokens to a specified address
     * @param to Address to transfer tokens to
     * @param amount Amount of tokens to transfer
     * @return bool indicating whether the transfer was successful
     */
    function transfer(address to, uint256 amount) public virtual override(ERC20Upgradeable, IERC20) returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
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
    ) public virtual override(ERC20Upgradeable, IERC20) returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    /**
     * @notice Get the token balance of an account
     * @param account Address to check balance for
     * @return Balance of the account
     */
    function balanceOf(
        address account
    ) public view override(IERC20, ERC20Upgradeable) returns (uint256) {
        pUSDStorage storage $ = _getpUSDStorage();
        address vaultAddress = address($.boringVault.vault);

        // Get balances of both USDC and USDT directly
        uint256 usdcBalance = IERC20(USDC).balanceOf(vaultAddress);
        uint256 usdtBalance = IERC20(USDT).balanceOf(vaultAddress);

        // Both USDC and USDT have 6 decimals, so we can simply add them
        return usdcBalance + usdtBalance;
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
