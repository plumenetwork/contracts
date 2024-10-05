// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IComponentToken } from "./interfaces/IComponentToken.sol";

/**
 * @title ComponentToken
 * @author Eugene Y. Q. Shen
 * @notice Abstract contract that implements the IComponentToken interface and can be extended
 *   with a concrete implementation that interfaces with an external real-world asset.
 */
abstract contract ComponentToken is
    Initializable,
    ERC20Upgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    IComponentToken
{

    // Storage

    /// @notice Represents a request to buy or sell ComponentToken using assets
    struct Request {
        /// @dev Unique identifier for the request
        uint256 requestId;
        /// @dev Amount of assets for a buy; amount of shares for a sell
        uint256 amount;
        /// @dev Address of the user or smart contract who requested the buy or sell
        address requestor;
        /// @dev True for a buy request; false for a sell request
        bool isBuy;
        /// @dev True if the request has been executed; false otherwise
        bool isExecuted;
    }

    /// @custom:storage-location erc7201:plume.storage.ComponentToken
    struct ComponentTokenStorage {
        /// @dev Asset used to mint and burn the ComponentToken
        IERC20 asset;
        /// @dev Number of decimals of the ComponentToken
        uint8 decimals;
        /// @dev Version of the ComponentToken interface
        uint256 version;
        /// @dev Requests to buy or sell ComponentToken using assets
        Request[] requests;
        /// @dev Total amount of yield that has ever been accrued by all users
        uint256 totalYieldAccrued;
        /// @dev Total amount of yield that has ever been withdrawn by all users
        uint256 totalYieldWithdrawn;
        /// @dev Total amount of yield that has ever been accrued by each user
        mapping(address user => uint256 assets) yieldAccrued;
        /// @dev Total amount of yield that has ever been withdrawn by each user
        mapping(address user => uint256 assets) yieldWithdrawn;
        /// @dev True if deposits are asynchronous; false otherwise
        bool asyncDeposit;
        /// @dev True if redemptions are asynchronous; false otherwise
        bool asyncRedeem;
        /// @dev Amount of assets deposited by each controller and not ready to claim
        mapping(address controller => uint256 assets) pendingDepositRequest;
        /// @dev Amount of assets deposited by each controller and ready to claim
        mapping(address controller => uint256 assets) claimableDepositRequest;
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

    // Events

    /**
     * @notice Emitted when a user requests to buy ComponentToken using assets
     * @param user Address of the user who requested to buy the ComponentToken
     * @param asset Asset to be used to buy the ComponentToken
     * @param assets Amount of assets offered to be paid
     */
    event BuyRequested(address indexed user, IERC20 indexed asset, uint256 assets);

    /**
     * @notice Emitted when a user requests to sell ComponentToken to receive assets
     * @param user Address of the user who requested to sell the ComponentToken
     * @param asset Asset to be received in exchange for the ComponentToken
     * @param shares Amount of ComponentToken offered to be sold
     */
    event SellRequested(address indexed user, IERC20 indexed asset, uint256 shares);

    /**
     * @notice Emitted when a user buys ComponentToken using assets
     * @param user Address of the user who bought the ComponentToken
     * @param asset Asset used to buy the ComponentToken
     * @param assets Amount of assets paid
     * @param shares Amount of shares received
     */
    event BuyExecuted(address indexed user, IERC20 indexed asset, uint256 asset, uint256 shares);

    /**
     * @notice Emitted when a user sells ComponentToken to receive assets
     * @param user Address of the user who sold the ComponentToken
     * @param asset Asset received in exchange for the ComponentToken
     * @param assets Amount of assets received
     * @param shares Amount of shares sold
     */
    event SellExecuted(address indexed user, IERC20 indexed asset, uint256 assets, uint256 shares);

    /**
     * @notice Emitted when anyone claims yield that has accrued to a user
     * @param user Address of the user who receives the claimed yield
     * @param asset Asset used to denominate the claimed yield
     * @param assets Amount of assets claimed as yield
     */
    event YieldClaimed(address indexed user, IERC20 indexed asset, uint256 assets);

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
     * @notice Indicates a failure because the given request ID is invalid
     * @param invalidRequestId Request ID that is invalid
     * @param errorType Type of error that occurred
     *   0: Request ID does not exist
     *   1: Request amount does not match the amount the user is trying to execute
     *   2: Requestor is not the user trying to execute the request
     *   3: Request is not a buy request, but the user is trying to execute a buy
     *   4: Request is not a sell request, but the user is trying to execute a sell
     *   5: Request has already been executed
     */
    error InvalidRequest(uint256 invalidRequestId, uint256 errorType);

    /**
     * @notice Indicates a failure because the given version is not higher than the current version
     * @param invalidVersion Invalid version that is not higher than the current version
     * @param version Current version of the ComponentToken
     */
    error InvalidVersion(uint256 invalidVersion, uint256 version);

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
     * @param asset Asset used to mint and burn the ComponentToken
     * @param decimals_ Number of decimals of the ComponentToken
     * @param asyncDeposit True if deposits are asynchronous; false otherwise
     * @param asyncRedeem True if redemptions are asynchronous; false otherwise
     */
    function initialize(
        address owner,
        string memory name,
        string memory symbol,
        IERC20 asset,
        uint8 decimals_,
        bool asyncDeposit,
        bool asyncRedeem
    ) public initializer {
        __ERC20_init(name, symbol);
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(ADMIN_ROLE, owner);
        _grantRole(UPGRADER_ROLE, owner);

        ComponentTokenStorage storage $ = _getComponentTokenStorage();
        $.asset = asset;
        $.decimals = decimals_;
        $.asyncDeposit = asyncDeposit;
        $.asyncRedeem = asyncRedeem;
    }

    // Override Functions

    /**
     * @notice Revert when `msg.sender` is not authorized to upgrade the contract
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override(UUPSUpgradeable) onlyRole(UPGRADER_ROLE) { }

    /// @notice Number of decimals of the ComponentToken
    function decimals() public view override returns (uint8) {
        return _getComponentTokenStorage().decimals;
    }

    // User Functions

    /**
     * @inheritdoc IComponentToken
     * @dev Must revert for all callers and inputs for asynchronous deposit vaults
     */
    function previewDeposit(uint256 assets) external view returns (uint256 shares) {
        ComponentTokenStorage storage $ = _getComponentTokenStorage();
        if ($.asyncDeposit) {
            revert Unimplemented();
        }
    }

    /**
     * @inheritdoc IComponentToken
     * @dev Must revert for all callers and inputs for asynchronous deposit vaults
     */
    function previewMint(uint256 shares) external view returns (uint256 assets) {
        ComponentTokenStorage storage $ = _getComponentTokenStorage();
        if ($.asyncDeposit) {
            revert Unimplemented();
        }
    }

    /**
     * @inheritdoc IComponentToken
     * @dev Must revert for all callers and inputs for asynchronous redeem vaults
     */
    function previewRedeem(uint256 shares) external view returns (uint256 assets) {
        ComponentTokenStorage storage $ = _getComponentTokenStorage();
        if ($.asyncRedeem) {
            revert Unimplemented();
        }
    }

    /**
     * @inheritdoc IComponentToken
     * @dev Must revert for all callers and inputs for asynchronous redeem vaults
     */
    function previewWithdraw(uint256 assets) external view returns (uint256 shares) {
        ComponentTokenStorage storage $ = _getComponentTokenStorage();
        if ($.asyncRedeem) {
            revert Unimplemented();
        }
    }

    /// @inheritdoc IComponentToken
    function requestDeposit(
        uint256 assets,
        address controller,
        address owner
    ) public virtual returns (uint256 requestId) {
        if (assets == 0) {
            revert ZeroAmount();
        }
        if (msg.sender != owner) {
            revert Unauthorized(msg.sender, owner);
        }

        ComponentTokenStorage storage $ = _getComponentTokenStorage();
        IERC20 asset = $.asset;

        if (!asset.transferFrom(owner, address(this), assets)) {
            revert InsufficientBalance(asset, owner, assets);
        }
        $.pendingDepositRequest[controller] += assets;

        emit DepositRequest(controller, owner, REQUEST_ID, owner, assets);
        return REQUEST_ID;
    }

    /// @inheritdoc IComponentToken
    function pendingDepositRequest(uint256 requestId, address controller) public view returns (uint256 assets) {
        return _getComponentTokenStorage().pendingDepositRequest[controller];
    }

    /// @inheritdoc IComponentToken
    function claimableDepositRequest(uint256 requestId, address controller) public view returns (uint256 assets) {
        return _getComponentTokenStorage().claimableDepositRequest[controller];
    }

    /// @inheritdoc IComponentToken
    function deposit(uint256 assets, address receiver, address controller) public virtual {
        if (assets == 0) {
            revert ZeroAmount();
        }
        if (msg.sender != controller) {
            revert Unauthorized(msg.sender, controller);
        }

        ComponentTokenStorage storage $ = _getComponentTokenStorage();
        if ($.claimableDepositRequest[controller] < assets) {
            revert InsufficientRequestBalance(controller, assets, 1);
        }

        _mint(receiver, shares);
        $.claimableDepositRequest[controller] -= assets;

        emit Deposit(controller, receiver, assets, shares);
    }

    /// @inheritdoc IComponentToken
    function mint(uint256 shares, address receiver, address controller) public virtual {
        revert Unimplemented();
    }

    /// @inheritdoc IComponentToken
    function requestRedeem(
        uint256 shares,
        address controller,
        address owner
    ) public virtual returns (uint256 requestId) {
        if (shares == 0) {
            revert ZeroAmount();
        }
        if (msg.sender != owner) {
            revert Unauthorized(msg.sender, owner);
        }

        ComponentTokenStorage storage $ = _getComponentTokenStorage();
        IERC20 asset = $.asset;

        _burn(msg.sender, shares);
        $.pendingRedeemRequest[controller] += assets;

        emit RedeemRequest(controller, owner, REQUEST_ID, owner, shares);
        return REQUEST_ID;
    }

    /// @inheritdoc IComponentToken
    function pendingRedeemRequest(uint256 requestId, address controller) public view returns (uint256 shares) {
        return _getComponentTokenStorage().pendingRedeemRequest[controller];
    }

    /// @inheritdoc IComponentToken
    function claimableRedeemRequest(uint256 requestId, address controller) public view returns (uint256 shares) {
        return _getComponentTokenStorage().claimableRedeemRequest[controller];
    }

    /// @inheritdoc IComponentToken
    function redeem(uint256 shares, address receiver, address controller) public virtual {
        if (shares == 0) {
            revert ZeroAmount();
        }
        if (msg.sender != controller) {
            revert Unauthorized(msg.sender, controller);
        }

        ComponentTokenStorage storage $ = _getComponentTokenStorage();
        if ($.claimableRedeemRequest[controller] < shares) {
            revert InsufficientRequestBalance(controller, shares, 1);
        }

        IERC20 asset = $.asset;
        if (!asset.transfer(receiver, assets)) {
            revert InsufficientBalance(asset, address(this), assets);
        }
        $.claimableRedeemRequest[controller] -= shares;

        emit Withdraw(msg.sender, receiver, controller, assets, shares);
    }

    /// @inheritdoc IComponentToken
    function withdraw(uint256 assets, address receiver, address controller) public virtual {
        revert Unimplemented();
    }

    /**
     * @notice Claim all the remaining yield that has been accrued to a user
     * @dev Anyone can call this function to claim yield for any user
     * @param user Address of the user to claim yield for
     * @return assets Amount of assets claimed as yield
     */
    function claimYield(address user) external returns (uint256 assets) {
        ComponentTokenStorage storage $ = _getComponentTokenStorage();
        IERC20 asset = $.asset;

        assets = unclaimedYield(user);
        asset.transfer(user, assets);
        $.yieldWithdrawn[user] += assets;
        $.totalYieldWithdrawn += assets;

        emit YieldClaimed(user, asset, assets);
    }

    // Admin Setter Functions

    /**
     * @notice Set the version of the ComponentToken
     * @dev Only the owner can call this setter
     * @param version New version of the ComponentToken
     */
    function setVersion(uint256 version) external onlyRole(ADMIN_ROLE) {
        ComponentTokenStorage storage $ = _getComponentTokenStorage();
        if (version <= $.version) {
            revert InvalidVersion(version, $.version);
        }
        $.version = version;
    }

    /**
     * @notice Set the asset used to mint and burn the ComponentToken
     * @dev Only the owner can call this setter
     * @param asset New asset token to be used
     */
    function setAsset(IERC20 asset) external onlyRole(ADMIN_ROLE) {
        _getComponentTokenStorage().asset = asset;
    }

    // Getter View Functions

    /// @notice Returns the version of the ComponentToken interface
    function getVersion() external view returns (uint256) {
        return _getComponentTokenStorage().version;
    }

    /// @notice Asset used to buy and sell the ComponentToken
    function asset() external view returns (address) {
        return address(_getComponentTokenStorage().asset);
    }

    /// @notice Total yield distributed to the ComponentToken for all users
    function totalYield() external view returns (uint256 amount) {
        return _getComponentTokenStorage().totalYieldAccrued;
    }

    /// @notice Claimed yield across the ComponentToken for all users
    function claimedYield() external view returns (uint256 amount) {
        return _getComponentTokenStorage().totalYieldWithdrawn;
    }

    /// @notice Unclaimed yield across the ComponentToken for all users
    function unclaimedYield() external view returns (uint256 amount) {
        ComponentTokenStorage storage $ = _getComponentTokenStorage();
        return $.totalYieldAccrued - $.totalYieldWithdrawn;
    }

    /**
     * @notice Total yield distributed to a specific user
     * @param user Address of the user for which to get the total yield
     * @return amount Total yield distributed to the user
     */
    function totalYield(address user) external view returns (uint256 amount) {
        return _getComponentTokenStorage().yieldAccrued[user];
    }

    /**
     * @notice Amount of yield that a specific user has claimed
     * @param user Address of the user for which to get the claimed yield
     * @return amount Amount of yield that the user has claimed
     */
    function claimedYield(address user) external view returns (uint256 amount) {
        return _getComponentTokenStorage().yieldWithdrawn[user];
    }

    /**
     * @notice Amount of yield that a specific user has not yet claimed
     * @param user Address of the user for which to get the unclaimed yield
     * @return amount Amount of yield that the user has not yet claimed
     */
    function unclaimedYield(address user) public view returns (uint256 amount) {
        ComponentTokenStorage storage $ = _getComponentTokenStorage();
        return $.yieldAccrued[user] - $.yieldWithdrawn[user];
    }

}
