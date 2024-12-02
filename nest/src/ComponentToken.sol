// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import { IComponentToken } from "./interfaces/IComponentToken.sol";
import { IERC7540 } from "./interfaces/IERC7540.sol";
import { IERC7575 } from "./interfaces/IERC7575.sol";

/**
 * @title ComponentToken
 * @author Eugene Y. Q. Shen
 * @notice Abstract contract that implements the IComponentToken interface and can be extended
 *   with a concrete implementation that interfaces with an external real-world asset.
 */
abstract contract ComponentToken is
    Initializable,
    ERC4626Upgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC165,
    IERC7540
{

    // Storage

    /// @custom:storage-location erc7201:plume.storage.ComponentToken
    struct ComponentTokenStorage {
        /// @dev True if deposits are asynchronous; false otherwise
        bool asyncDeposit;
        /// @dev True if redemptions are asynchronous; false otherwise
        bool asyncRedeem;
        /// @dev Amount of assets deposited by each controller and not ready to claim
        mapping(address controller => uint256 assets) pendingDepositRequest;
        /// @dev Amount of assets deposited by each controller and ready to claim
        mapping(address controller => uint256 assets) claimableDepositRequest;
        /// @dev Amount of shares to send to the vault for each controller that deposited assets
        mapping(address controller => uint256 shares) sharesDepositRequest;
        /// @dev Amount of shares redeemed by each controller and not ready to claim
        mapping(address controller => uint256 shares) pendingRedeemRequest;
        /// @dev Amount of shares redeemed by each controller and ready to claim
        mapping(address controller => uint256 shares) claimableRedeemRequest;
        /// @dev Amount of assets to send to the controller for each controller that redeemed shares
        mapping(address controller => uint256 assets) assetsRedeemRequest;
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.ComponentToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant COMPONENT_TOKEN_STORAGE_LOCATION =
        0x40f2ca4cf3a525ed9b1b2649f0f850db77540accc558be58ba47f8638359e800;

    function _getComponentTokenStorage() internal pure returns (ComponentTokenStorage storage $) {
        assembly {
            $.slot := COMPONENT_TOKEN_STORAGE_LOCATION
        }
    }

    // Constants

    /// @notice All ComponentToken requests are fungible and all have ID = 0
    uint256 private constant REQUEST_ID = 0;
    /// @notice Role for the admin of the ComponentToken
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @notice Role for the upgrader of the ComponentToken
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    /// @notice Base that is used to divide all price inputs in order to represent e.g. 1.000001 as 1000001e12
    uint256 private constant _BASE = 1e18;

    // Events

    /**
     * @notice Emitted when the vault has been notified of the completion of a deposit request
     * @param controller Controller of the request
     * @param assets Amount of `asset` that has been deposited
     * @param shares Amount of shares to receive in exchange
     */
    event DepositNotified(address indexed controller, uint256 assets, uint256 shares);

    /**
     * @notice Emitted when the vault has been notified of the completion of a redeem request
     * @param controller Controller of the request
     * @param assets Amount of `asset` to receive in exchange
     * @param shares Amount of shares that has been redeemed
     */
    event RedeemNotified(address indexed controller, uint256 assets, uint256 shares);

    // Errors

    /// @notice Indicates a failure because the user tried to call an unimplemented function
    error Unimplemented();

    /// @notice Indicates a failure because the given amount is 0
    error ZeroAmount();

    /**
     * @notice Indicates a failure because the sender is not authorized to perform the action
     * @param sender Address of the sender that is not authorized
     * @param authorizedUser Address of the authorized user who can perform the action
     */
    error Unauthorized(address sender, address authorizedUser);

    /**
     * @notice Indicates a failure because the controller does not have enough requested
     * @param controller Address of the controller who does not have enough requested
     * @param amount Amount of assets or shares to be subtracted from the request
     * @param requestType Type of request that is insufficient
     *   0: Pending deposit request
     *   1: Claimable deposit request
     *   2: Pending redeem request
     *   3: Claimable redeem request
     */
    error InsufficientRequestBalance(address controller, uint256 amount, uint256 requestType);

    /**
     * @notice Indicates a failure because the user does not have enough assets
     * @param asset Asset used to mint and burn the ComponentToken
     * @param user Address of the user who is selling the assets
     * @param assets Amount of assets required in the failed transfer
     */
    error InsufficientBalance(IERC20 asset, address user, uint256 assets);

    // Initializer

    /**
     * @notice Prevent the implementation contract from being initialized or reinitialized
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the ComponentToken
     * @param owner Address of the owner of the ComponentToken
     * @param name Name of the ComponentToken
     * @param symbol Symbol of the ComponentToken
     * @param asset_ Asset used to mint and burn the ComponentToken
     * @param asyncDeposit True if deposits are asynchronous; false otherwise
     * @param asyncRedeem True if redemptions are asynchronous; false otherwise
     */
    function initialize(
        address owner,
        string memory name,
        string memory symbol,
        IERC20 asset_,
        bool asyncDeposit,
        bool asyncRedeem
    ) public onlyInitializing {
        __ERC20_init(name, symbol);
        __ERC4626_init(asset_);
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(ADMIN_ROLE, owner);
        _grantRole(UPGRADER_ROLE, owner);

        ComponentTokenStorage storage $ = _getComponentTokenStorage();
        $.asyncDeposit = asyncDeposit;
        $.asyncRedeem = asyncRedeem;
    }

    // Override Functions

    /**
     * @notice Revert when `msg.sender` is not authorized to upgrade the contract
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override(UUPSUpgradeable) onlyRole(UPGRADER_ROLE) { }

    /// @inheritdoc IERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(AccessControlUpgradeable, ERC165, IERC165) returns (bool supported) {
        if (
            super.supportsInterface(interfaceId) || interfaceId == type(IERC7575).interfaceId
                || interfaceId == 0xe3bc4e65
        ) {
            return true;
        }
        ComponentTokenStorage storage $ = _getComponentTokenStorage();
        return ($.asyncDeposit && interfaceId == 0xce3bbe50) || ($.asyncRedeem && interfaceId == 0x620ee8e4);
    }

    /// @inheritdoc IERC4626
    function asset() public view virtual override(ERC4626Upgradeable, IERC7540) returns (address assetTokenAddress) {
        return super.asset();
    }

    /// @inheritdoc IERC4626
    function totalAssets()
        public
        view
        virtual
        override(ERC4626Upgradeable, IERC7540)
        returns (uint256 totalManagedAssets)
    {
        return super.totalAssets();
    }

    /// @notice Total value held by the given owner
    /// @dev Reverts with Unimplemented() until convertToAssets is implemented by the concrete contract
    /// @param owner Address to query the balance of
    /// @return assets Total value held by the owner
    function assetsOf(
        address owner
    ) public view virtual returns (uint256 assets) {
        return convertToAssets(balanceOf(owner));
    }

    /// @inheritdoc IERC4626
    function convertToShares(
        uint256 assets
    ) public view virtual override(ERC4626Upgradeable, IERC7540) returns (uint256 shares) {
        revert Unimplemented();
    }

    /// @inheritdoc IERC4626
    function convertToAssets(
        uint256 shares
    ) public view virtual override(ERC4626Upgradeable, IERC7540) returns (uint256 assets) {
        revert Unimplemented();
    }

    // User Functions

    /// @inheritdoc IComponentToken
    function requestDeposit(
        uint256 assets,
        address controller,
        address owner
    ) public virtual nonReentrant returns (uint256 requestId) {
        if (assets == 0) {
            revert ZeroAmount();
        }
        if (msg.sender != owner) {
            revert Unauthorized(msg.sender, owner);
        }

        ComponentTokenStorage storage $ = _getComponentTokenStorage();
        if (!$.asyncDeposit) {
            revert Unimplemented();
        }

        if (!IERC20(asset()).transferFrom(owner, address(this), assets)) {
            revert InsufficientBalance(IERC20(asset()), owner, assets);
        }
        $.pendingDepositRequest[controller] += assets;

        emit DepositRequest(controller, owner, REQUEST_ID, owner, assets);
        return REQUEST_ID;
    }

    /**
     * @notice Notify the vault that the async request to buy shares has been completed
     * @param assets Amount of `asset` that was deposited by `requestDeposit`
     * @param shares Amount of shares to receive in exchange
     * @param controller Controller of the request
     */
    function _notifyDeposit(uint256 assets, uint256 shares, address controller) internal virtual nonReentrant {
        if (assets == 0) {
            revert ZeroAmount();
        }

        ComponentTokenStorage storage $ = _getComponentTokenStorage();
        if (!$.asyncDeposit) {
            revert Unimplemented();
        }
        if ($.pendingDepositRequest[controller] < assets) {
            revert InsufficientRequestBalance(controller, assets, 0);
        }

        $.pendingDepositRequest[controller] -= assets;
        $.claimableDepositRequest[controller] += assets;
        $.sharesDepositRequest[controller] += shares;

        emit DepositNotified(controller, assets, shares);
    }

    /// @inheritdoc IComponentToken
    function deposit(
        uint256 assets,
        address receiver,
        address controller
    ) public virtual nonReentrant returns (uint256 shares) {
        if (assets == 0) {
            revert ZeroAmount();
        }
        if (msg.sender != controller) {
            revert Unauthorized(msg.sender, controller);
        }

        ComponentTokenStorage storage $ = _getComponentTokenStorage();
        if ($.asyncDeposit) {
            if ($.claimableDepositRequest[controller] < assets) {
                revert InsufficientRequestBalance(controller, assets, 1);
            }
            shares = $.sharesDepositRequest[controller];
            $.claimableDepositRequest[controller] -= assets;
            $.sharesDepositRequest[controller] -= shares;
        } else {
            if (!IERC20(asset()).transferFrom(controller, address(this), assets)) {
                revert InsufficientBalance(IERC20(asset()), controller, assets);
            }
            shares = convertToShares(assets);
        }

        _mint(receiver, shares);

        emit Deposit(controller, receiver, assets, shares);
    }

    /// @inheritdoc IERC7540
    function mint(
        uint256 shares,
        address receiver,
        address controller
    ) public virtual nonReentrant returns (uint256 assets) {
        if (shares == 0) {
            revert ZeroAmount();
        }
        if (msg.sender != controller) {
            revert Unauthorized(msg.sender, controller);
        }

        ComponentTokenStorage storage $ = _getComponentTokenStorage();
        assets = convertToAssets(shares);

        if ($.asyncDeposit) {
            if ($.claimableDepositRequest[controller] < assets) {
                revert InsufficientRequestBalance(controller, assets, 1);
            }
            $.claimableDepositRequest[controller] -= assets;
            $.sharesDepositRequest[controller] -= shares;
        } else {
            if (!IERC20(asset()).transferFrom(controller, address(this), assets)) {
                revert InsufficientBalance(IERC20(asset()), controller, assets);
            }
        }

        _mint(receiver, shares);

        emit Deposit(controller, receiver, assets, shares);
    }

    /// @inheritdoc IComponentToken
    function requestRedeem(
        uint256 shares,
        address controller,
        address owner
    ) public virtual nonReentrant returns (uint256 requestId) {
        if (shares == 0) {
            revert ZeroAmount();
        }
        if (msg.sender != owner) {
            revert Unauthorized(msg.sender, owner);
        }

        ComponentTokenStorage storage $ = _getComponentTokenStorage();
        if (!$.asyncRedeem) {
            revert Unimplemented();
        }

        _burn(msg.sender, shares);
        $.pendingRedeemRequest[controller] += shares;

        emit RedeemRequest(controller, owner, REQUEST_ID, owner, shares);
        return REQUEST_ID;
    }

    /**
     * @notice Notify the vault that the async request to redeem assets has been completed
     * @param assets Amount of `asset` to receive in exchange
     * @param shares Amount of shares that was redeemed by `requestRedeem`
     * @param controller Controller of the request
     */
    function _notifyRedeem(uint256 assets, uint256 shares, address controller) internal virtual nonReentrant {
        if (shares == 0) {
            revert ZeroAmount();
        }

        ComponentTokenStorage storage $ = _getComponentTokenStorage();
        if (!$.asyncRedeem) {
            revert Unimplemented();
        }
        if ($.pendingRedeemRequest[controller] < shares) {
            revert InsufficientRequestBalance(controller, shares, 2);
        }

        $.pendingRedeemRequest[controller] -= shares;
        $.claimableRedeemRequest[controller] += shares;
        $.assetsRedeemRequest[controller] += assets;

        emit RedeemNotified(controller, assets, shares);
    }

    /// @inheritdoc IERC7540
    function redeem(
        uint256 shares,
        address receiver,
        address controller
    ) public virtual override(ERC4626Upgradeable, IERC7540) nonReentrant returns (uint256 assets) {
        if (shares == 0) {
            revert ZeroAmount();
        }
        if (msg.sender != controller) {
            revert Unauthorized(msg.sender, controller);
        }

        ComponentTokenStorage storage $ = _getComponentTokenStorage();
        if ($.asyncRedeem) {
            if ($.claimableRedeemRequest[controller] < shares) {
                revert InsufficientRequestBalance(controller, shares, 3);
            }
            assets = $.assetsRedeemRequest[controller];
            $.claimableRedeemRequest[controller] -= shares;
            $.assetsRedeemRequest[controller] -= assets;
        } else {
            _burn(controller, shares);
            assets = convertToAssets(shares);
        }

        if (!IERC20(asset()).transfer(receiver, assets)) {
            revert InsufficientBalance(IERC20(asset()), address(this), assets);
        }

        emit Withdraw(controller, receiver, controller, assets, shares);
    }

    /// @inheritdoc IERC7540
    function withdraw(
        uint256 assets,
        address receiver,
        address controller
    ) public virtual override(ERC4626Upgradeable, IERC7540) nonReentrant returns (uint256 shares) {
        if (assets == 0) {
            revert ZeroAmount();
        }
        if (msg.sender != controller) {
            revert Unauthorized(msg.sender, controller);
        }

        ComponentTokenStorage storage $ = _getComponentTokenStorage();
        shares = convertToShares(assets);

        if ($.asyncRedeem) {
            if ($.claimableRedeemRequest[controller] < shares) {
                revert InsufficientRequestBalance(controller, shares, 3);
            }
            $.claimableRedeemRequest[controller] -= shares;
            $.assetsRedeemRequest[controller] -= assets;
        } else {
            _burn(controller, shares);
        }

        if (!IERC20(asset()).transfer(receiver, assets)) {
            revert InsufficientBalance(IERC20(asset()), address(this), assets);
        }

        emit Withdraw(controller, receiver, controller, assets, shares);
    }

    // Getter View Functions

    /// @inheritdoc IERC7575
    function share() external view returns (address shareTokenAddress) {
        return address(this);
    }

    /// @inheritdoc IERC7540
    function isOperator(address, address) public pure returns (bool status) {
        return false;
    }

    /// @inheritdoc IComponentToken
    function pendingDepositRequest(uint256, address controller) public view returns (uint256 assets) {
        return _getComponentTokenStorage().pendingDepositRequest[controller];
    }

    /// @inheritdoc IComponentToken
    function claimableDepositRequest(uint256, address controller) public view returns (uint256 assets) {
        return _getComponentTokenStorage().claimableDepositRequest[controller];
    }

    /// @inheritdoc IComponentToken
    function pendingRedeemRequest(uint256, address controller) public view returns (uint256 shares) {
        return _getComponentTokenStorage().pendingRedeemRequest[controller];
    }

    /// @inheritdoc IComponentToken
    function claimableRedeemRequest(uint256, address controller) public view returns (uint256 shares) {
        return _getComponentTokenStorage().claimableRedeemRequest[controller];
    }

    /**
     * @inheritdoc IERC4626
     * @dev Must revert for all callers and inputs for asynchronous deposit vaults
     */
    function previewDeposit(
        uint256 assets
    ) public view virtual override(ERC4626Upgradeable, IERC4626) returns (uint256 shares) {
        if (_getComponentTokenStorage().asyncDeposit) {
            revert Unimplemented();
        }
        // Returns how many shares would be minted for given assets
        return convertToShares(assets);
    }

    /**
     * @inheritdoc IERC4626
     * @dev Must revert for all callers and inputs for asynchronous deposit vaults
     */
    function previewMint(
        uint256 shares
    ) public view virtual override(ERC4626Upgradeable, IERC4626) returns (uint256 assets) {
        if (_getComponentTokenStorage().asyncDeposit) {
            revert Unimplemented();
        }
        assets = super.previewDeposit(shares);
    }

    /**
     * @inheritdoc IERC4626
     * @dev Must revert for all callers and inputs for asynchronous redeem vaults
     */
    function previewRedeem(
        uint256 shares
    ) public view virtual override(ERC4626Upgradeable, IERC4626) returns (uint256 assets) {
        if (_getComponentTokenStorage().asyncRedeem) {
            revert Unimplemented();
        }
        // Returns how many assets would be withdrawn for given shares
        return convertToAssets(shares);
    }

    /**
     * @inheritdoc IERC4626
     * @dev Must revert for all callers and inputs for asynchronous redeem vaults
     */
    function previewWithdraw(
        uint256 assets
    ) public view virtual override(ERC4626Upgradeable, IERC4626) returns (uint256 shares) {
        if (_getComponentTokenStorage().asyncRedeem) {
            revert Unimplemented();
        }
        shares = super.previewWithdraw(assets);
    }

    /// @inheritdoc IERC7540
    function setOperator(address, bool) public pure returns (bool) {
        revert Unimplemented();
    }

}
