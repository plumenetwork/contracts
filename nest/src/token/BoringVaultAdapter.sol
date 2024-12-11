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
import { IBoringVault } from "../interfaces/IBoringVault.sol";
import { IBoringVaultAdapter } from "../interfaces/IBoringVaultAdapter.sol";
import { IComponentToken } from "../interfaces/IComponentToken.sol";
import { ILens } from "../interfaces/ILens.sol";
import { ITeller } from "../interfaces/ITeller.sol";

import { ComponentToken } from "../ComponentToken.sol";

/**
 * @title BoringVaultAdapter
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice ComponentToken adapter for BoringVault
 */
abstract contract BoringVaultAdapter is
    Initializable,
    ERC20Upgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ComponentToken
{

    using SafeERC20 for IERC20;
    using FixedPointMathLib for uint256;

    // ========== ERRORS ==========
    error ZeroAddress();

    error InvalidAsset();
    error InvalidReceiver();
    error InvalidSender();
    error InvalidController();
    error InvalidVault();
    error InvalidAccountant();

    error AssetNotSupported();
    error TellerPaused();
    error DeadlineExpired();

    // ========== STORAGE ==========

    struct BoringVault {
        ITeller teller;
        IBoringVault vault;
        IAtomicQueue atomicQueue;
        ILens lens;
        IAccountantWithRateProviders accountant;
    }

    /// @custom:storage-location erc7201:plume.storage.BoringVaultAdapter
    struct BoringVaultAdapterStorage {
        BoringVault boringVault;
        uint256 version;
        IERC20 asset;
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.BoringVaultAdapter")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BORING_VAULT_ADAPTER_STORAGE_LOCATION =
        0xe9c78db21140f8c0fa40a4ee265a8dbdd963fe6e2feb8d1e0ba55235ac089900;

    function _getBoringVaultAdapterStorage() private pure returns (BoringVaultAdapterStorage storage $) {
        bytes32 position = BORING_VAULT_ADAPTER_STORAGE_LOCATION;
        assembly {
            $.slot := position
        }
    }

    // ========== EVENTS ==========

    event VaultChanged(address oldVault, address newVault);
    event Reinitialized(uint256 version);

    // ========== INITIALIZERS ==========

    /**
     * @notice Prevent the implementation contract from being initialized or reinitialized
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize BoringVaultAdapter
     * @param owner Address of the owner of BoringVaultAdapter
     * @param asset_ Address of the underlying asset
     * @param vault_ Address of the BoringVault
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
        address accountant_,
        string memory name,
        string memory symbol
    ) public onlyInitializing {
        if (
            owner == address(0) || address(asset_) == address(0) || vault_ == address(0) || teller_ == address(0)
                || atomicQueue_ == address(0) || lens_ == address(0) || accountant_ == address(0)
        ) {
            revert ZeroAddress();
        }

        // Validate asset interface support
        try IERC20Metadata(address(asset_)).decimals() returns (uint8) { }
        catch {
            revert InvalidAsset();
        }

        // Set async redeem to true
        super.initialize(owner, name, symbol, asset_, false, true);

        BoringVaultAdapterStorage storage $ = _getBoringVaultAdapterStorage();
        $.boringVault.teller = ITeller(teller_);
        $.boringVault.vault = IBoringVault(vault_);
        $.boringVault.atomicQueue = IAtomicQueue(atomicQueue_);
        $.boringVault.lens = ILens(lens_);
        $.boringVault.accountant = IAccountantWithRateProviders(accountant_);
        $.asset = asset_;

        $.version = 1; // Set initial version

        // Set approvals for the underlying asset
        SafeERC20.forceApprove(asset_, vault_, type(uint256).max);
        SafeERC20.forceApprove(asset_, teller_, type(uint256).max);
        SafeERC20.forceApprove(asset_, atomicQueue_, type(uint256).max);

        // Set approvals for the pUSD token itself
        _approve(address(this), vault_, type(uint256).max);
        _approve(address(this), teller_, type(uint256).max);
        _approve(address(this), atomicQueue_, type(uint256).max);
    }

    function reinitialize(
        address owner,
        IERC20 asset_,
        address vault_,
        address teller_,
        address atomicQueue_,
        address lens_,
        address accountant_
    ) public virtual onlyRole(UPGRADER_ROLE) {
        // Reinitialize as needed
        if (
            owner == address(0) || address(asset_) == address(0) || vault_ == address(0) || teller_ == address(0)
                || atomicQueue_ == address(0) || lens_ == address(0) || accountant_ == address(0)
        ) {
            revert ZeroAddress();
        }

        BoringVaultAdapterStorage storage $ = _getBoringVaultAdapterStorage();

        // Increment version
        $.version += 1;
        $.boringVault.teller = ITeller(teller_);
        $.boringVault.vault = IBoringVault(vault_);
        $.boringVault.atomicQueue = IAtomicQueue(atomicQueue_);
        $.boringVault.lens = ILens(lens_);
        $.boringVault.accountant = IAccountantWithRateProviders(accountant_);

        // Set approvals for the underlying asset
        SafeERC20.forceApprove(asset_, vault_, type(uint256).max);
        SafeERC20.forceApprove(asset_, teller_, type(uint256).max);
        SafeERC20.forceApprove(asset_, atomicQueue_, type(uint256).max);

        // Set approvals for the pUSD token itself
        _approve(address(this), vault_, type(uint256).max);
        _approve(address(this), teller_, type(uint256).max);
        _approve(address(this), atomicQueue_, type(uint256).max);

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
        return address(_getBoringVaultAdapterStorage().boringVault.vault);
    }

    /**
     * @notice Get the current teller address
     * @return Address of the current teller
     */
    function getTeller() external view returns (address) {
        return address(_getBoringVaultAdapterStorage().boringVault.teller);
    }

    /**
     * @notice Get the current AtomicQueue address
     * @return Address of the current AtomicQueue
     */
    function getAtomicQueue() external view returns (address) {
        return address(_getBoringVaultAdapterStorage().boringVault.atomicQueue);
    }

    /**
     * @notice Get the current BoringVaultAdapter version
     * @return uint256 version of the BoringVaultAdapter contract
     */
    function version() public view returns (uint256) {
        return _getBoringVaultAdapterStorage().version;
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

        ITeller teller = _getBoringVaultAdapterStorage().boringVault.teller;

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

        IAtomicQueue queue = _getBoringVaultAdapterStorage().boringVault.atomicQueue;
        queue.updateAtomicRequest(IERC20(address(this)), IERC20(asset()), request);

        return REQUEST_ID;
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
    ) public view override(ComponentToken) returns (uint256 shares) {
        BoringVaultAdapterStorage storage $ = _getBoringVaultAdapterStorage();

        try $.boringVault.vault.decimals() returns (uint8 shareDecimals) {
            try $.boringVault.accountant.getRateInQuote(ERC20(asset())) returns (uint256 rate) {
                shares = assets.mulDivDown(10 ** shareDecimals, rate);
            } catch {
                revert InvalidAccountant(); // Or could create a new error like `InvalidAccountant`
            }
        } catch {
            revert InvalidVault();
        }
    }

    /**
     * @notice Calculate how many assets would be withdrawn for a given amount of shares
     * @param shares Amount of shares to redeem
     * @return assets Amount of assets that would be withdrawn
     */
    function previewRedeem(
        uint256 shares
    ) public view virtual override(ComponentToken) returns (uint256 assets) {
        BoringVaultAdapterStorage storage $ = _getBoringVaultAdapterStorage();

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
        BoringVaultAdapterStorage storage $ = _getBoringVaultAdapterStorage();

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
        BoringVaultAdapterStorage storage $ = _getBoringVaultAdapterStorage();
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
        _transfer(msg.sender, to, amount);
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
        _spendAllowance(from, msg.sender, amount);
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
        return super.balanceOf(account);
    }

    /**
     * @notice Get the balance in terms of assets for an account
     * @param account The address to check the balance for
     * @return The value of shares in terms of assets owned by the account
     */
    function assetsOf(
        address account
    ) public view virtual override(ComponentToken) returns (uint256) {
        return super.assetsOf(account);
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
     * @notice Check if the contract supports a given interface
     * @param interfaceId Interface identifier to check
     * @return bool indicating whether the interface is supported
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ComponentToken, AccessControlUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId) || interfaceId == type(IBoringVaultAdapter).interfaceId;
    }

}
