// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
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
    ERC165,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
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
    uint256 internal constant REQUEST_ID = 0;
    /// @notice Role for the admin of the ComponentToken
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @notice Role for the upgrader of the ComponentToken
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    /// @notice Base that is used to divide all price inputs in order to represent e.g. 1.000001 as 1000001e12
    uint256 internal constant _BASE = 1e18;

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
     * @notice Indicates a failure because the operation was called in async mode
     * @dev This error is thrown when trying to perform a synchronous operation while async mode is enabled
     */
    error AsyncOperationsEnabled();

    /**
     * @notice Indicates a failure because the operation was called in sync mode
     * @dev This error is thrown when trying to perform an asynchronous operation while async mode is disabled
     */
    error AsyncOperationsDisabled();

    /**
     * @notice Indicates a failure because there are no claimable deposits for the controller
     * @dev This error is thrown when trying to claim a deposit but either the assets
     *   or shares amount in the request is zero
     */
    error NoClaimableDeposit();

    /**
     * @notice Indicates a failure because there are no claimable redemptions for the controller
     * @dev This error is thrown when trying to claim a redemption but either the assets
     *   or shares amount in the request is zero
     */
    error NoClaimableRedeem();

    /**
     * @notice Indicates a failure because the deposit amount doesn't match the claimable amount
     * @param provided Amount of assets provided for deposit
     * @param required Amount of assets required (claimable amount)
     */
    error InvalidDepositAmount(uint256 provided, uint256 required);

    /**
     * @notice Indicates a failure because the redeem amount doesn't match the claimable amount
     * @param provided Amount of shares provided for redemption
     * @param required Amount of shares required (claimable amount)
     */
    error InvalidRedeemAmount(uint256 provided, uint256 required);

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
        ComponentTokenStorage storage $ = _getComponentTokenStorage();
        return super.supportsInterface(interfaceId) || interfaceId == type(IERC20).interfaceId
            || interfaceId == type(IAccessControl).interfaceId || interfaceId == type(IERC7575).interfaceId
            || interfaceId == type(IComponentToken).interfaceId || interfaceId == 0xe3bc4e65
            || ($.asyncDeposit && interfaceId == 0xce3bbe50) || ($.asyncRedeem && interfaceId == 0x620ee8e4);
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

        SafeERC20.safeTransferFrom(IERC20(asset()), owner, address(this), assets);
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
            // For async deposits, we must use the full claimable amount
            uint256 claimableAssets = $.claimableDepositRequest[controller];
            shares = $.sharesDepositRequest[controller];

            if (claimableAssets == 0 || shares == 0) {
                revert NoClaimableDeposit();
            }
            if (assets != claimableAssets) {
                revert InvalidDepositAmount(assets, claimableAssets);
            }

            // Reset state atomically
            $.claimableDepositRequest[controller] = 0;
            $.sharesDepositRequest[controller] = 0;
        } else {
            SafeERC20.safeTransferFrom(IERC20(asset()), controller, address(this), assets);
            shares = convertToShares(assets);
        }

        _mint(receiver, shares);
        emit Deposit(controller, receiver, assets, shares);
        return shares;
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
        if ($.asyncDeposit) {
            // Check shares directly instead of converting to assets
            if ($.sharesDepositRequest[controller] < shares) {
                revert InsufficientRequestBalance(controller, shares, 1);
            }

            // Get the pre-calculated values
            uint256 claimableShares = $.sharesDepositRequest[controller];

            // Verify shares match exactly
            if (shares != claimableShares) {
                revert InvalidDepositAmount(shares, claimableShares);
            }

            assets = $.claimableDepositRequest[controller];
            $.claimableDepositRequest[controller] = 0;
            $.sharesDepositRequest[controller] = 0;
        } else {
            assets = previewMint(shares);
            SafeERC20.safeTransferFrom(IERC20(asset()), controller, address(this), assets);
        }
        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
        return assets;
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

    /**
     * @notice Fulfill a synchronous request to redeem assets by transferring assets to the receiver
     * @dev This function can only be called when async redemptions are disabled
     * @param shares Amount of shares to redeem
     * @param receiver Address to receive the assets
     * @param controller Controller of the request
     * @return assets Amount of assets sent to the receiver
     */
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
            // For async redemptions, we must use the full claimable amount
            uint256 claimableShares = $.claimableRedeemRequest[controller];
            assets = $.assetsRedeemRequest[controller];

            if (claimableShares == 0 || assets == 0) {
                revert NoClaimableRedeem();
            }
            if (shares != claimableShares) {
                revert InvalidRedeemAmount(shares, claimableShares);
            }

            // Reset state atomically
            $.claimableRedeemRequest[controller] = 0;
            $.assetsRedeemRequest[controller] = 0;
        } else {
            // For sync redemptions, process normally
            _burn(controller, shares);
            assets = convertToAssets(shares);
        }

        SafeERC20.safeTransfer(IERC20(asset()), receiver, assets);

        emit Withdraw(controller, receiver, controller, assets, shares);
        return assets;
    }

    /**
     * @notice Claim an approved asynchronous redeem request and transfer assets to the receiver
     * @dev This function can only be called when async redemptions are enabled
     *   and will revert if there are no claimable redemptions for the controller.
     *   All state for the request is atomically reset after a successful claim.
     * @param receiver Address to receive the redeemed assets
     * @param controller Controller of the redeem request
     * @return assets Amount of assets sent to the receiver
     * @return shares Amount of shares that were redeemed
     */
    function claimRedeem(
        address receiver,
        address controller
    ) public virtual nonReentrant returns (uint256 assets, uint256 shares) {
        if (msg.sender != controller) {
            revert Unauthorized(msg.sender, controller);
        }

        ComponentTokenStorage storage $ = _getComponentTokenStorage();
        if (!$.asyncRedeem) {
            revert AsyncOperationsDisabled();
        }

        shares = $.claimableRedeemRequest[controller];
        assets = $.assetsRedeemRequest[controller];

        if (shares == 0 || assets == 0) {
            revert NoClaimableRedeem();
        }

        // Reset state atomically
        $.claimableRedeemRequest[controller] = 0;
        $.assetsRedeemRequest[controller] = 0;

        if (!IERC20(asset()).transfer(receiver, assets)) {
            revert InsufficientBalance(IERC20(asset()), address(this), assets);
        }

        emit Withdraw(controller, receiver, controller, assets, shares);
        return (assets, shares);
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
        if ($.asyncRedeem) {
            if ($.assetsRedeemRequest[controller] < assets) {
                revert InsufficientRequestBalance(controller, assets, 3);
            }
            // Get the pre-calculated values
            uint256 claimableAssets = $.assetsRedeemRequest[controller];
            shares = $.claimableRedeemRequest[controller];

            // Verify assets match exactly
            if (assets != claimableAssets) {
                revert InvalidRedeemAmount(assets, claimableAssets);
            }

            // Reset state atomically
            $.claimableRedeemRequest[controller] = 0;
            $.assetsRedeemRequest[controller] = 0;

            // No _burn needed here as shares were already burned in requestRedeem
            SafeERC20.safeTransfer(IERC20(asset()), receiver, assets);
            emit Withdraw(controller, receiver, controller, assets, shares);
        } else {
            shares = previewWithdraw(assets);
            _withdraw(controller, receiver, controller, assets, shares);
        }
        return shares;
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
        assets = convertToAssets(shares);
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
        shares = convertToShares(assets);
    }

    /// @inheritdoc IERC7540
    function setOperator(address, bool) public pure returns (bool) {
        revert Unimplemented();
    }

}
