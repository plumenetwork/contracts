// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { WalletUtils } from "../WalletUtils.sol";
import { IAssetToken } from "../interfaces/IAssetToken.sol";

import { IComponentToken } from "../interfaces/IComponentToken.sol";
import { ISmartWallet } from "../interfaces/ISmartWallet.sol";
import { IYieldDistributionToken } from "../interfaces/IYieldDistributionToken.sol";
import { IYieldToken } from "../interfaces/IYieldToken.sol";
import { YieldDistributionToken } from "./YieldDistributionToken.sol";

/**
 * @title YieldToken
 * @author Eugene Y. Q. Shen
 * @notice ERC20 token that receives yield redistributions from an AssetToken
 */
contract YieldToken is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    YieldDistributionToken,
    ERC4626Upgradeable,
    WalletUtils,
    IYieldToken,
    IComponentToken
{

    // Storage

    /// @custom:storage-location erc7201:plume.storage.YieldToken
    struct YieldTokenStorage {
        /// @dev AssetToken that redistributes yield to the YieldToken
        IAssetToken assetToken;
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

    /// @notice Role for the admin of the ComponentToken
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @notice Role for the upgrader of the ComponentToken
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // keccak256(abi.encode(uint256(keccak256("plume.storage.YieldToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant YIELD_TOKEN_STORAGE_LOCATION =
        0xe0df32b9dab2596a95926c5b17cc961f10a49277c3685726d2657c9ac0b50e00;

    function _getYieldTokenStorage() private pure returns (YieldTokenStorage storage $) {
        assembly {
            $.slot := YIELD_TOKEN_STORAGE_LOCATION
        }
    }

    // Constants

    /// @notice All ComponentToken requests are fungible and all have ID = 0
    uint256 private constant REQUEST_ID = 0;

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

    /// @notice Indicates a failure because the given address is 0
    /// @param what Description of which address was zero
    error ZeroAddress(string what);

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

    // Errors

    /**
     * @notice Indicates a failure because the given CurrencyToken does not match the actual CurrencyToken
     * @param invalidCurrencyToken CurrencyToken that does not match the actual CurrencyToken
     * @param currencyToken Actual CurrencyToken used to mint and burn the AggregateToken
     */
    error InvalidCurrencyToken(IERC20 invalidCurrencyToken, IERC20 currencyToken);

    /**
     * @notice Indicates a failure because the given AssetToken does not match the actual AssetToken
     * @param invalidAssetToken AssetToken that does not match the actual AssetToken
     * @param assetToken Actual AssetToken that redistributes yield to the YieldToken
     */
    error InvalidAssetToken(IAssetToken invalidAssetToken, IAssetToken assetToken);

    // Constructor

    /**
     * @notice Prevent the implementation contract from being initialized or reinitialized
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the YieldToken
     * @param owner Address of the owner of the YieldToken
     * @param name Name of the YieldToken
     * @param symbol Symbol of the YieldToken
     * @param currencyToken Token in which the yield is deposited and denominated
     * @param decimals_ Number of decimals of the YieldToken
     * @param tokenURI_ URI of the YieldToken metadata
     * @param assetToken AssetToken that redistributes yield to the YieldToken
     * @param initialSupply Initial supply of the YieldToken
     */
    function initialize(
        address owner,
        string memory name,
        string memory symbol,
        IERC20 currencyToken,
        uint8 decimals_,
        string memory tokenURI_,
        IAssetToken assetToken,
        uint256 initialSupply
    ) public initializer {
        if (owner == address(0)) {
            revert ZeroAddress("owner");
        }
        if (address(currencyToken) == address(0)) {
            revert ZeroAddress("currency token");
        }
        if (address(assetToken) == address(0)) {
            revert ZeroAddress("asset token");
        }

        if (currencyToken != assetToken.getCurrencyToken()) {
            revert InvalidCurrencyToken(currencyToken, assetToken.getCurrencyToken());
        }

        __YieldDistributionToken_init(owner, name, symbol, currencyToken, decimals_, tokenURI_);
        __ERC4626_init(currencyToken);

        _getYieldTokenStorage().assetToken = assetToken;

        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(ADMIN_ROLE, owner);
        _grantRole(UPGRADER_ROLE, owner);

        _mint(owner, initialSupply);
    }

    /**
     * @notice Reinitialize the YieldToken with updated parameters
     * @dev This function can be called multiple times, but only by the owner and with increasing version numbers
     * @param version Version number for the reinitialization
     * @param newName Optional new name for the token (empty string to keep current)
     * @param newSymbol Optional new symbol for the token (empty string to keep current)
     * @param newTokenURI Optional new token URI (empty string to keep current)
     * @param newAssetToken Optional new asset token (address(0) to keep current)
     */
    function reinitialize(
        uint8 version,
        string memory newName,
        string memory newSymbol,
        string memory newTokenURI,
        IAssetToken newAssetToken
    ) public onlyRole(UPGRADER_ROLE) reinitializer(2) {
        YieldTokenStorage storage $ = _getYieldTokenStorage();

        // Update name if provided
        if (bytes(newName).length > 0) {
            _setName(newName);
        }

        // Update symbol if provided
        if (bytes(newSymbol).length > 0) {
            _setSymbol(newSymbol);
        }

        // Update tokenURI if provided
        if (bytes(newTokenURI).length > 0) {
            _getYieldDistributionTokenStorage().tokenURI = newTokenURI;
        }

        // Update assetToken if provided
        if (address(newAssetToken) != address(0)) {
            // Verify the new asset token uses the same currency token
            if (_getYieldDistributionTokenStorage().currencyToken != newAssetToken.getCurrencyToken()) {
                revert InvalidCurrencyToken(
                    IERC20(newAssetToken.getCurrencyToken()), _getYieldDistributionTokenStorage().currencyToken
                );
            }
            $.assetToken = newAssetToken;
        }
    }

    // Admin Functions

    /**
     * @notice Mint new YieldTokens to the user
     * @dev Only the owner can call this function
     * @param user Address of the user to mint YieldTokens to
     * @param yieldTokenAmount Amount of YieldTokens to mint
     */
    function adminMint(address user, uint256 yieldTokenAmount) external onlyRole(ADMIN_ROLE) {
        _mint(user, yieldTokenAmount);
    }

    /**
     * @notice Revert when `msg.sender` is not authorized to upgrade the contract
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override(UUPSUpgradeable) onlyRole(UPGRADER_ROLE) { }

    // Override Functions

    /**
     * @notice Make the SmartWallet redistribute yield from their AssetToken into this YieldToken
     * @dev The Solidity compiler adds a check that the target address has `extcodesize > 0`
     *   and otherwise reverts for high-level calls, so we have to use a low-level call here
     * @param from Address of the SmartWallet to request the yield from
     */
    function requestYield(
        address from
    ) external override(YieldDistributionToken, IYieldDistributionToken) {
        // Have to override both until updated in https://github.com/ethereum/solidity/issues/12665
        (bool success,) = from.call(
            abi.encodeWithSelector(ISmartWallet.claimAndRedistributeYield.selector, _getYieldTokenStorage().assetToken)
        );
        if (!success) {
            revert SmartWalletCallFailed(from);
        }
    }

    /// @inheritdoc IERC4626
    function asset() public view override(ERC4626, IComponentToken) returns (address assetTokenAddress) {
        return super.asset();
    }

    /// @inheritdoc IERC4626
    function totalAssets() public view override(ERC4626, IComponentToken) returns (uint256 totalManagedAssets) {
        return super.totalAssets();
    }

    /// @inheritdoc IComponentToken
    function assetsOf(
        address owner
    ) public view override returns (uint256 assets) {
        return convertToAssets(balanceOf(owner));
    }

    /// @inheritdoc IERC4626
    function convertToShares(
        uint256 assets
    ) public view override(ERC4626, IComponentToken) returns (uint256 shares) {
        uint256 supply = totalSupply();
        uint256 totalAssets_ = totalAssets();
        if (supply == 0 || totalAssets_ == 0) {
            return assets;
        }
        return (assets * supply) / totalAssets_;
    }

    /// @inheritdoc IERC4626
    function convertToAssets(
        uint256 shares
    ) public view override(ERC4626, IComponentToken) returns (uint256 assets) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return shares;
        }
        return (shares * totalAssets()) / supply;
    }

    /// @inheritdoc ERC20
    function decimals() public view override(YieldDistributionToken, ERC4626) returns (uint8) {
        return super.decimals();
    }

    /// @inheritdoc ERC20
    function _update(
        address from,
        address to,
        uint256 value
    ) internal virtual override(YieldDistributionToken, ERC20) {
        super._update(from, to, value);
    }

    // User Functions

    /**
     * @notice Receive yield into the YieldToken
     * @dev Anyone can call this function to deposit yield from their AssetToken into the YieldToken
     * @param assetToken AssetToken that redistributes yield to the YieldToken
     * @param currencyToken CurrencyToken in which the yield is received and denominated
     * @param currencyTokenAmount Amount of CurrencyToken to receive as yield
     */
    function receiveYield(IAssetToken assetToken, IERC20 currencyToken, uint256 currencyTokenAmount) external {
        if (assetToken != _getYieldTokenStorage().assetToken) {
            revert InvalidAssetToken(assetToken, _getYieldTokenStorage().assetToken);
        }
        if (currencyToken != _getYieldDistributionTokenStorage().currencyToken) {
            revert InvalidCurrencyToken(currencyToken, _getYieldDistributionTokenStorage().currencyToken);
        }
        _depositYield(currencyTokenAmount);
    }

    /// @inheritdoc IComponentToken
    function requestDeposit(uint256 assets, address controller, address owner) public returns (uint256 requestId) {
        if (assets == 0) {
            revert ZeroAmount();
        }
        if (msg.sender != owner) {
            revert Unauthorized(msg.sender, owner);
        }

        YieldTokenStorage storage $ = _getYieldTokenStorage();
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
    function _notifyDeposit(uint256 assets, uint256 shares, address controller) internal virtual {
        if (assets == 0) {
            revert ZeroAmount();
        }

        YieldTokenStorage storage $ = _getYieldTokenStorage();
        if ($.pendingDepositRequest[controller] < assets) {
            revert InsufficientRequestBalance(controller, assets, 0);
        }

        $.pendingDepositRequest[controller] -= assets;
        $.claimableDepositRequest[controller] += assets;
        $.sharesDepositRequest[controller] += shares;

        emit DepositNotified(controller, assets, shares);
    }

    /// @inheritdoc IComponentToken
    function deposit(uint256 assets, address receiver, address controller) public returns (uint256 shares) {
        if (assets == 0) {
            revert ZeroAmount();
        }
        if (receiver == address(0)) {
            revert ZeroAddress("receiver");
        }
        if (msg.sender != controller) {
            revert Unauthorized(msg.sender, controller);
        }

        YieldTokenStorage storage $ = _getYieldTokenStorage();
        if ($.claimableDepositRequest[controller] < assets) {
            revert InsufficientRequestBalance(controller, assets, 1);
        }
        shares = $.sharesDepositRequest[controller];
        $.claimableDepositRequest[controller] -= assets;
        $.sharesDepositRequest[controller] -= shares;

        _mint(receiver, shares);

        emit Deposit(controller, receiver, assets, shares);
    }

    /**
     * @notice Fulfill a request to buy shares by minting shares to the receiver
     * @param shares Amount of shares to mint
     * @param receiver Address to receive the shares
     * @param controller Controller of the request
     */
    function mint(uint256 shares, address receiver, address controller) public returns (uint256 assets) {
        if (shares == 0) {
            revert ZeroAmount();
        }
        if (receiver == address(0)) {
            revert ZeroAddress("receiver");
        }
        if (msg.sender != controller) {
            revert Unauthorized(msg.sender, controller);
        }

        YieldTokenStorage storage $ = _getYieldTokenStorage();
        assets = convertToAssets(shares);

        if ($.claimableDepositRequest[controller] < assets) {
            revert InsufficientRequestBalance(controller, assets, 1);
        }
        $.claimableDepositRequest[controller] -= assets;
        $.sharesDepositRequest[controller] -= shares;

        _mint(receiver, shares);

        emit Deposit(controller, receiver, assets, shares);
    }

    /// @inheritdoc IComponentToken
    function requestRedeem(uint256 shares, address controller, address owner) public returns (uint256 requestId) {
        if (shares == 0) {
            revert ZeroAmount();
        }
        if (msg.sender != owner) {
            revert Unauthorized(msg.sender, owner);
        }

        YieldTokenStorage storage $ = _getYieldTokenStorage();

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
    function _notifyRedeem(uint256 assets, uint256 shares, address controller) internal {
        if (shares == 0) {
            revert ZeroAmount();
        }

        YieldTokenStorage storage $ = _getYieldTokenStorage();
        if ($.pendingRedeemRequest[controller] < shares) {
            revert InsufficientRequestBalance(controller, shares, 2);
        }

        $.pendingRedeemRequest[controller] -= shares;
        $.claimableRedeemRequest[controller] += shares;
        $.assetsRedeemRequest[controller] += assets;

        emit RedeemNotified(controller, assets, shares);
    }

    /// @inheritdoc IERC4626
    function redeem(
        uint256 shares,
        address receiver,
        address controller
    ) public override(ERC4626, IComponentToken) returns (uint256 assets) {
        if (shares == 0) {
            revert ZeroAmount();
        }
        if (receiver == address(0)) {
            revert ZeroAddress("receiver");
        }
        if (msg.sender != controller) {
            revert Unauthorized(msg.sender, controller);
        }

        YieldTokenStorage storage $ = _getYieldTokenStorage();
        if ($.claimableRedeemRequest[controller] < shares) {
            revert InsufficientRequestBalance(controller, shares, 3);
        }
        assets = $.assetsRedeemRequest[controller];
        $.claimableRedeemRequest[controller] -= shares;
        $.assetsRedeemRequest[controller] -= assets;

        if (!IERC20(asset()).transfer(receiver, assets)) {
            revert InsufficientBalance(IERC20(asset()), address(this), assets);
        }

        emit Withdraw(controller, receiver, controller, assets, shares);
    }

    /// @inheritdoc IERC4626
    function withdraw(
        uint256 assets,
        address receiver,
        address controller
    ) public override(ERC4626) returns (uint256 shares) {
        if (assets == 0) {
            revert ZeroAmount();
        }
        if (receiver == address(0)) {
            revert ZeroAddress("receiver");
        }
        if (msg.sender != controller) {
            revert Unauthorized(msg.sender, controller);
        }

        YieldTokenStorage storage $ = _getYieldTokenStorage();
        shares = convertToShares(assets);

        if ($.claimableRedeemRequest[controller] < shares) {
            revert InsufficientRequestBalance(controller, shares, 3);
        }
        $.claimableRedeemRequest[controller] -= shares;
        $.assetsRedeemRequest[controller] -= assets;

        if (!IERC20(asset()).transfer(receiver, assets)) {
            revert InsufficientBalance(IERC20(asset()), address(this), assets);
        }

        emit Withdraw(controller, receiver, controller, assets, shares);
    }

    // Getter View Functions

    /// @inheritdoc IComponentToken
    function pendingDepositRequest(uint256, address controller) public view returns (uint256 assets) {
        return _getYieldTokenStorage().pendingDepositRequest[controller];
    }

    /// @inheritdoc IComponentToken
    function claimableDepositRequest(uint256, address controller) public view returns (uint256 assets) {
        return _getYieldTokenStorage().claimableDepositRequest[controller];
    }

    /// @inheritdoc IComponentToken
    function pendingRedeemRequest(uint256, address controller) public view returns (uint256 shares) {
        return _getYieldTokenStorage().pendingRedeemRequest[controller];
    }

    /// @inheritdoc IComponentToken
    function claimableRedeemRequest(uint256, address controller) public view returns (uint256 shares) {
        return _getYieldTokenStorage().claimableRedeemRequest[controller];
    }

}
