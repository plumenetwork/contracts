// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";

import { IAccountantWithRateProviders } from "../interfaces/IAccountantWithRateProviders.sol";
import { IAtomicQueue } from "../interfaces/IAtomicQueue.sol";

import { IVault } from "../interfaces/IBoringVault.sol";
import { IComponentToken } from "../interfaces/IComponentToken.sol";
import { ILens } from "../interfaces/ILens.sol";
import { ITeller } from "../interfaces/ITeller.sol";

import { ComponentToken } from "../ComponentToken.sol";

/**
 * @title pUSD
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Unified Plume USD stablecoin
 */
contract pUSD is Initializable, ERC20Upgradeable, AccessControlUpgradeable, UUPSUpgradeable, ComponentToken {

    using SafeERC20 for IERC20;
    using FixedPointMathLib for uint256;

    // ========== ERRORS ==========
    error ZeroAddress();

    error InvalidAsset();
    error InvalidReceiver();
    error InvalidSender();
    error InvalidController();
    error InvalidVault();

    error AssetNotSupported();
    error TellerPaused();
    error DeadlineExpired();

    // ========== STORAGE ==========

    struct BoringVault {
        ITeller teller;
        IVault vault;
        IAtomicQueue atomicQueue;
        ILens lens;
        IAccountantWithRateProviders accountant;
    }

    /// @custom:storage-location erc7201:plume.storage.pUSD
    struct pUSDStorage {
        BoringVault boringVault;
        uint8 tokenDecimals;
        string tokenName;
        string tokenSymbol;
        uint256 version;
        IERC20 asset;
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
     * @param atomicQueue_ Address of the AtomicQueue
     */
    //
    function initialize(
        address owner,
        IERC20 asset_,
        address vault_,
        address teller_,
        address atomicQueue_,
        address lens_,
        address accountant_
    ) public initializer {
        if (
            owner == address(0) || address(asset_) == address(0) || vault_ == address(0) || teller_ == address(0)
                || atomicQueue_ == address(0)
        ) {
            revert ZeroAddress();
        }

        // Validate asset interface support
        try IERC20Metadata(address(asset_)).decimals() returns (uint8) { }
        catch {
            revert InvalidAsset();
        }

        // No need to initialize ReentrancyGuard, as it's inherited from ComponentToken.
        // Having ReentrancyGuard here would cause double initialization.
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __ERC20_init("Plume USD", "pUSD");

        // Set async redeem to true
        super.initialize(owner, "Plume USD", "pUSD", asset_, false, true);

        pUSDStorage storage $ = _getpUSDStorage();
        $.boringVault.teller = ITeller(teller_);
        $.boringVault.vault = IVault(vault_);
        $.boringVault.atomicQueue = IAtomicQueue(atomicQueue_);
        $.boringVault.lens = ILens(lens_);
        $.boringVault.accountant = IAccountantWithRateProviders(accountant_);
        $.asset = asset_;

        $.version = 1; // Set initial version

        _grantRole(ADMIN_ROLE, owner);
        _grantRole(VAULT_ADMIN_ROLE, owner);
        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(UPGRADER_ROLE, owner);
    }

    function reinitialize(
        address owner,
        IERC20 asset_,
        address vault_,
        address teller_,
        address atomicQueue_,
        address lens_,
        address accountant_
    ) public onlyRole(UPGRADER_ROLE) {
        // Reinitialize as needed
        if (
            owner == address(0) || address(asset_) == address(0) || vault_ == address(0) || teller_ == address(0)
                || atomicQueue_ == address(0)
        ) {
            revert ZeroAddress();
        }

        pUSDStorage storage $ = _getpUSDStorage();

        // Increment version
        $.version += 1;
        $.boringVault.teller = ITeller(teller_);
        $.boringVault.vault = IVault(vault_);
        $.boringVault.atomicQueue = IAtomicQueue(atomicQueue_);
        $.boringVault.lens = ILens(lens_);
        $.boringVault.accountant = IAccountantWithRateProviders(accountant_);

        _grantRole(ADMIN_ROLE, owner);
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
    function getAtomicQueue() external view returns (address) {
        return address(_getpUSDStorage().boringVault.atomicQueue);
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
    ) public virtual returns (uint256 shares) {
        if (receiver == address(0)) {
            revert InvalidReceiver();
        }

        ITeller teller = _getpUSDStorage().boringVault.teller;

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
     * @notice Request to redeem shares for assets through the atomic queue
     * @param shares Amount of shares to burn
     * @param receiver Address that will receive the assets
     * @param controller Address that will control the redemption
     * @param price Price in terms of underlying asset (e.g., USDC) per share
     * @param deadline Deadline for the atomic request
     */
    function requestRedeem(
        uint256 shares,
        address receiver,
        address controller,
        uint256 price,
        uint64 deadline
    ) public virtual returns (uint256) {
        if (receiver == address(0)) {
            revert InvalidReceiver();
        }
        if (controller == address(0)) {
            revert InvalidController();
        }
        if (deadline < block.timestamp) {
            revert DeadlineExpired();
        }

        // Request the redeem through ComponentToken (burns shares and records pending request)
        super.requestRedeem(shares, controller, msg.sender);

        // Create and submit atomic request
        IAtomicQueue.AtomicRequest memory request = IAtomicQueue.AtomicRequest({
            deadline: deadline,
            atomicPrice: uint88(price), // Price per share in terms of asset
            offerAmount: uint96(shares),
            inSolve: false
        });

        IAtomicQueue queue = _getpUSDStorage().boringVault.atomicQueue;
        queue.updateAtomicRequest(IERC20(address(this)), IERC20(asset()), request);

        return 0; // ComponentToken's standard REQUEST_ID
    }

    /**
     * @notice Called by protocol after atomic queue processes the redemption
     * @param assets Amount of assets received from atomic queue
     * @param shares Amount of shares redeemed
     * @param controller Address that controls the redemption
     */
    function notifyRedeem(uint256 assets, uint256 shares, address controller) external onlyRole(ADMIN_ROLE) {
        _notifyRedeem(assets, shares, controller);
    }

    /**
     * @notice Complete the redemption after atomic queue processing
     * @param shares Amount of shares to redeem
     * @param receiver Address that will receive the assets
     * @param controller Address that controls the redemption
     */
    function redeem(
        uint256 shares,
        address receiver,
        address controller
    ) public virtual override(ComponentToken) returns (uint256 assets) {
        // Check claimableRedeemRequest, transfer assets to receiver, clean up request state.
        return super.redeem(shares, receiver, controller);
    }

    /**
     * @notice Calculate how many shares would be minted for a given amount of assets
     * @param assets Amount of assets to deposit
     * @return shares Amount of shares that would be minted
     */
    function previewDeposit(
        uint256 assets
    ) public view virtual override(ComponentToken) returns (uint256) {
        pUSDStorage storage $ = _getpUSDStorage();

        return $.boringVault.lens.previewDeposit(
            IERC20(address($.asset)), assets, $.boringVault.vault, $.boringVault.accountant
        );
    }

    /**
     * @notice Calculate how many assets would be withdrawn for a given amount of shares
     * @param shares Amount of shares to redeem
     * @return assets Amount of assets that would be withdrawn
     */
    function previewRedeem(
        uint256 shares
    ) public view virtual override(ComponentToken) returns (uint256 assets) {
        pUSDStorage storage $ = _getpUSDStorage();

        try $.boringVault.vault.decimals() returns (uint8 shareDecimals) {
            assets = shares.mulDivDown($.boringVault.accountant.getRateInQuote(ERC20(asset())), 10 ** shareDecimals);
        } catch {
            revert InvalidVault();
        }
    }

    /// @inheritdoc ERC4626Upgradeable
    function convertToShares(
        uint256 assets
    ) public view virtual override(ComponentToken) returns (uint256 shares) {
        pUSDStorage storage $ = _getpUSDStorage();

        try $.boringVault.vault.decimals() returns (uint8 shareDecimals) {
            shares = assets.mulDivDown(10 ** shareDecimals, $.boringVault.accountant.getRateInQuote(ERC20(asset())));
        } catch {
            revert InvalidVault();
        }
    }

    /// @inheritdoc ERC4626Upgradeable
    function convertToAssets(
        uint256 shares
    ) public view virtual override(ComponentToken) returns (uint256 assets) {
        pUSDStorage storage $ = _getpUSDStorage();
        try $.boringVault.vault.decimals() returns (uint8 shareDecimals) {
            assets = shares.mulDivDown($.boringVault.accountant.getRateInQuote(ERC20(asset())), 10 ** shareDecimals);
        } catch {
            revert InvalidVault();
        }
    }
    // ========== ERC20 OVERRIDES ==========

    /**
     * @notice Transfer tokens to a specified address
     * @param to Address to transfer tokens to
     * @param amount Amount of tokens to transfer
     * @return bool indicating whether the transfer was successful
     */
    function transfer(address to, uint256 amount) public virtual override(ERC20Upgradeable, IERC20) returns (bool) {
        address owner = msg.sender;
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
        address spender = msg.sender;
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    /**
     * @notice Get the balance of shares for an account
     * @param account The address to check the balance for
     * @return The number of shares owned by the account
     */
    function balanceOf(
        address account
    ) public view override(IERC20, ERC20Upgradeable) returns (uint256) {
        pUSDStorage storage $ = _getpUSDStorage();
        return $.boringVault.lens.balanceOf(account, $.boringVault.vault);
    }

    /**
     * @notice Get the balance in terms of assets for an account
     * @param account The address to check the balance for
     * @return The value of shares in terms of assets owned by the account
     */
    function assetsOf(
        address account
    ) public view virtual override(ComponentToken) returns (uint256) {
        pUSDStorage storage $ = _getpUSDStorage();
        return $.boringVault.lens.balanceOfInAssets(account, $.boringVault.vault, $.boringVault.accountant);
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
    ) public view virtual override(ComponentToken, AccessControlUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

}
