// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ERC1155Holder } from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ComponentToken } from "./ComponentToken.sol";
import { IAggregateToken } from "./interfaces/IAggregateToken.sol";

import { IAtomicQueue } from "./interfaces/IAtomicQueue.sol";
import { IComponentToken } from "./interfaces/IComponentToken.sol";
import { ITeller } from "./interfaces/ITeller.sol";

/**
 * @title AggregateToken
 * @author Eugene Y. Q. Shen
 * @notice Implementation of the abstract ComponentToken that represents a basket of ComponentTokens
 */
contract AggregateToken is ComponentToken, IAggregateToken, ERC1155Holder {

    // Storage

    /// @custom:storage-location erc7201:plume.storage.AggregateToken
    struct AggregateTokenStorage {
        /// @dev List of all ComponentTokens that have ever been added to the AggregateToken
        IComponentToken[] componentTokenList;
        /// @dev Mapping of all ComponentTokens that have ever been added to the AggregateToken
        mapping(IComponentToken componentToken => bool exists) componentTokenMap;
        /// @dev Price at which users can buy the AggregateToken using `asset`, times the base
        uint256 askPrice;
        /// @dev Price at which users can sell the AggregateToken to receive `asset`, times the base
        uint256 bidPrice;
        /// @dev True if the AggregateToken contract is paused for deposits, false otherwise
        bool paused;
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.AggregateToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant AGGREGATE_TOKEN_STORAGE_LOCATION =
        0xd3be8f8d43881152ac95daeff8f4c57e01616286ffd74814a5517f422a6b6200;

    function _getAggregateTokenStorage() private pure returns (AggregateTokenStorage storage $) {
        assembly {
            $.slot := AGGREGATE_TOKEN_STORAGE_LOCATION
        }
    }

    // Constants

    /// @notice Role for the price updater of the AggregateToken
    bytes32 public constant PRICE_UPDATER_ROLE = keccak256("PRICE_UPDATER_ROLE");
    /// @notice Role for the manager of the AggregateToken
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    // Events

    /// @notice Emitted when the AggregateToken contract is paused for deposits
    event Paused();

    /// @notice Emitted when the AggregateToken contract is unpaused for deposits
    event Unpaused();

    /// @notice Emitted when the asset token is updated
    event AssetTokenUpdated(IERC20 indexed oldAsset, IERC20 indexed newAsset);

    /// @notice Emitted when vault tokens are bought
    event VaultTokenBought(address indexed buyer, address indexed token, uint256 assets, uint256 shares);

    /// @notice Emitted when a vault token sell request is created
    event VaultTokenSellRequested(address indexed sender, address indexed token, uint256 shares, uint256 price);
    // Errors

    /**
     * @notice Indicates a failure because the ComponentToken is already in the component token list
     * @param componentToken ComponentToken that is already in the component token list
     */
    error ComponentTokenAlreadyListed(IComponentToken componentToken);

    /// @notice Emitted when a ComponentToken is removed from the component token list
    event ComponentTokenRemoved(IComponentToken indexed componentToken);

    /**
     * @notice Indicates a failure because the ComponentToken is not in the component token list
     * @param componentToken ComponentToken that is not in the component token list
     */
    error ComponentTokenNotListed(IComponentToken componentToken);

    /**
     * @notice Indicates a failure because the ComponentToken has a non-zero balance
     * @param componentToken ComponentToken that has a non-zero balance
     */
    error ComponentTokenBalanceNonZero(IComponentToken componentToken);

    /**
     * @notice Indicates a failure because the ComponentToken is the current `asset
     * @param componentToken ComponentToken that is the current `asset`
     */
    error ComponentTokenIsAsset(IComponentToken componentToken);

    /**
     * @notice Indicates a failure because the given `asset` does not match the actual `asset`
     * @param invalidAsset Asset that does not match the actual `asset`
     * @param asset Actual `asset` for the AggregateToken
     */
    error InvalidAsset(IERC20 invalidAsset, IERC20 asset);

    /// @notice Indicates a failure because the contract is paused for deposits
    error DepositPaused();

    /// @notice Indicates a failure because the contract is already paused for deposits
    error AlreadyPaused();

    /// @notice Indicates a failure because the contract is not paused for deposits
    error NotPaused();

    /// @notice Indicates the teller is paused
    error TellerPaused();

    /// @notice Indicates the asset is not supported by the teller
    error AssetNotSupported();

    /// @notice Indicates an invalid receiver address
    error InvalidReceiver();

    /// @notice Indicates the deadline has expired
    error DeadlineExpired();

    // Initializer

    /**
     * @notice Prevent the implementation contract from being initialized or reinitialized
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the AggregateToken
     * @param owner Address of the owner of the AggregateToken
     * @param name Name of the AggregateToken
     * @param symbol Symbol of the AggregateToken
     * @param asset_ Asset used to mint and burn the AggregateToken
     * @param askPrice Price at which users can buy the AggregateToken using `asset`, times the base
     * @param bidPrice Price at which users can sell the AggregateToken to receive `asset`, times the base
     */
    function initialize(
        address owner,
        string memory name,
        string memory symbol,
        IComponentToken asset_,
        uint256 askPrice,
        uint256 bidPrice
    ) public initializer {
        super.initialize(owner, name, symbol, IERC20(address(asset_)), false, true);

        AggregateTokenStorage storage $ = _getAggregateTokenStorage();
        $.componentTokenList.push(asset_);
        $.componentTokenMap[asset_] = true;
        $.askPrice = askPrice;
        $.bidPrice = bidPrice;
        $.paused = false;
    }

    /**
     * @notice Reinitialize the AggregateToken
     * @param owner Address of the owner of the AggregateToken
     * @param name Name of the AggregateToken
     * @param symbol Symbol of the AggregateToken
     * @param asset_ Asset used to mint and burn the AggregateToken
     * @param askPrice Price at which users can buy the AggregateToken using `asset`, times the base
     * @param bidPrice Price at which users can sell the AggregateToken to receive `asset`, times the base
     */
    function reinitialize(
        address owner,
        string memory name,
        string memory symbol,
        IComponentToken asset_,
        uint256 askPrice,
        uint256 bidPrice
    ) public onlyRole(UPGRADER_ROLE) reinitializer(2) {
        super.reinitialize(owner, name, symbol, IERC20(address(asset_)), false, true);

        AggregateTokenStorage storage $ = _getAggregateTokenStorage();
        if (!$.componentTokenMap[asset_]) {
            $.componentTokenList.push(asset_);
            $.componentTokenMap[asset_] = true;
            emit ComponentTokenListed(asset_);
        }
        $.askPrice = askPrice;
        $.bidPrice = bidPrice;
    }

    // Override Functions

    /**
     * @inheritdoc IERC4626
     * @dev 1:1 conversion rate between USDT and base asset
     */
    function convertToShares(
        uint256 assets
    ) public view override(ComponentToken, IComponentToken) returns (uint256 shares) {
        return assets * _BASE / _getAggregateTokenStorage().askPrice;
    }

    /**
     * @inheritdoc IERC4626
     * @dev 1:1 conversion rate between USDT and base asset
     */
    function convertToAssets(
        uint256 shares
    ) public view override(ComponentToken, IComponentToken) returns (uint256 assets) {
        return shares * _getAggregateTokenStorage().bidPrice / _BASE;
    }

    /// @inheritdoc IComponentToken
    function asset() public view override(ComponentToken, IComponentToken) returns (address assetTokenAddress) {
        return super.asset();
    }

    /// @inheritdoc IComponentToken
    /// @dev Do not add reentrancy guard here, as it is already handled in the parent contract
    function deposit(
        uint256 assets,
        address receiver,
        address controller
    ) public override(ComponentToken, IComponentToken) returns (uint256 shares) {
        if (_getAggregateTokenStorage().paused) {
            revert DepositPaused();
        }
        return super.deposit(assets, receiver, controller);
    }

    /**
     * @inheritdoc ERC4626Upgradeable
     * @dev Overridden to add pause check before deposit. Do not add reentrancy guard here, as it is already handled in
     * the parent contract
     * @param assets Amount of assets to deposit
     * @param receiver Address that will receive the shares
     * @return shares Amount of shares minted
     */
    function deposit(
        uint256 assets,
        address receiver
    ) public override(ERC4626Upgradeable, IERC4626) returns (uint256 shares) {
        if (_getAggregateTokenStorage().paused) {
            revert DepositPaused();
        }
        return super.deposit(assets, receiver);
    }

    /**
     * @inheritdoc ComponentToken
     * @dev Overridden to add pause check before minting. Do not add reentrancy guard here, as it is already handled in
     * the parent contract
     * @param shares Amount of shares to mint
     * @param receiver Address that will receive the shares
     * @param controller Address that controls the minting
     * @return assets Amount of assets deposited
     */
    function mint(
        uint256 shares,
        address receiver,
        address controller
    ) public override(ComponentToken) returns (uint256 assets) {
        if (_getAggregateTokenStorage().paused) {
            revert DepositPaused();
        }
        return super.mint(shares, receiver, controller);
    }

    /**
     * @inheritdoc ERC4626Upgradeable
     * @dev Overridden to add pause check before minting. Do not add reentrancy guard here, as it is already handled in
     * the parent contract
     * @param shares Amount of shares to mint
     * @param receiver Address that will receive the shares
     * @return assets Amount of assets deposited
     */
    function mint(
        uint256 shares,
        address receiver
    ) public override(ERC4626Upgradeable, IERC4626) returns (uint256 assets) {
        if (_getAggregateTokenStorage().paused) {
            revert DepositPaused();
        }
        return super.mint(shares, receiver);
    }

    /// @inheritdoc IComponentToken
    /// @dev Do not add reentrancy guard here, as it is already handled in the parent contract
    function redeem(
        uint256 shares,
        address receiver,
        address controller
    ) public override(ComponentToken, IComponentToken) returns (uint256 assets) {
        return super.redeem(shares, receiver, controller);
    }

    /// @inheritdoc IComponentToken
    function totalAssets() public view override(ComponentToken, IComponentToken) returns (uint256 totalManagedAssets) {
        return super.totalAssets();
    }

    // Admin Functions

    /**
     * @notice Approve the given ComponentToken to spend the given amount of `asset`
     * @dev Only the manager can call this function
     * @param componentToken ComponentToken to approve
     * @param amount Amount of `asset` to approve
     */
    function approveComponentToken(
        IComponentToken componentToken,
        uint256 amount
    ) external nonReentrant onlyRole(MANAGER_ROLE) {
        // Verify the componentToken is in componentTokenMap
        if (!_getAggregateTokenStorage().componentTokenMap[componentToken]) {
            revert ComponentTokenNotListed(componentToken);
        }
        IERC20(componentToken.asset()).approve(address(componentToken), amount);
    }

    /**
     * @notice Add a ComponentToken to the component token list
     * @dev Only the owner can call this function, and there is no way to remove a ComponentToken later
     * @param componentToken ComponentToken to add
     */
    function addComponentToken(
        IComponentToken componentToken
    ) external nonReentrant onlyRole(ADMIN_ROLE) {
        AggregateTokenStorage storage $ = _getAggregateTokenStorage();
        if ($.componentTokenMap[componentToken]) {
            revert ComponentTokenAlreadyListed(componentToken);
        }
        $.componentTokenList.push(componentToken);
        $.componentTokenMap[componentToken] = true;
        emit ComponentTokenListed(componentToken);
    }

    /**
     * @notice Remove a ComponentToken from the component token list
     * @dev Only the owner can call this function. The ComponentToken must have zero balance to be removed.
     * @param componentToken ComponentToken to remove
     */
    function removeComponentToken(
        IComponentToken componentToken
    ) external nonReentrant onlyRole(ADMIN_ROLE) {
        AggregateTokenStorage storage $ = _getAggregateTokenStorage();

        // Check if component token exists
        if (!$.componentTokenMap[componentToken]) {
            revert ComponentTokenNotListed(componentToken);
        }

        // Check if it's the current asset
        if (address(componentToken) == asset()) {
            revert ComponentTokenIsAsset(componentToken);
        }

        // Remove from mapping
        $.componentTokenMap[componentToken] = false;

        // Remove from array by finding and replacing with last element
        for (uint256 i = 0; i < $.componentTokenList.length; i++) {
            if ($.componentTokenList[i] == componentToken) {
                $.componentTokenList[i] = $.componentTokenList[$.componentTokenList.length - 1];
                $.componentTokenList.pop();
                break;
            }
        }

        emit ComponentTokenUnlisted(componentToken);
    }

    /**
     * @notice Buy vault tokens by depositing assets through a teller
     * @dev Will revert if teller is paused or asset is not supported
     * @param token Address of the token to deposit
     * @param assets Amount of tokens to deposit
     * @param minimumMint Minimum amount of shares to receive (slippage protection)
     * @param _teller Address of the teller contract to use for deposit
     * @return shares Amount of vault shares minted to the caller
     */
    function buyVaultToken(
        address token,
        uint256 assets,
        uint256 minimumMint,
        address _teller
    ) public nonReentrant returns (uint256 shares) {
        if (msg.sender == address(0)) {
            revert InvalidReceiver();
        }

        ITeller teller = ITeller(_teller);

        // Verify deposit is allowed through teller
        if (teller.isPaused()) {
            revert TellerPaused();
        }
        if (!teller.isSupported(IERC20(token))) {
            revert AssetNotSupported();
        }

        // Transfer assets from sender to this contract
        SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), assets);

        // Approve teller to spend assets
        SafeERC20.forceApprove(IERC20(token), address(teller), assets);

        // Deposit through teller
        shares = teller.deposit(
            IERC20(token), // depositAsset
            assets, // depositAmount
            minimumMint // minimumMint
        );

        emit VaultTokenBought(msg.sender, token, assets, shares);
        return shares;
    }

    /**
     * @notice Create an atomic sell request for vault tokens
     * @dev Only the manager can call this function
     * @param offerToken Address of the vault token to sell
     * @param wantToken Address of the vault token to buy
     * @param shares Amount of shares to sell
     * @param price Price per share in terms of asset
     * @param deadline Timestamp after which the request expires
     * @param _atomicQueue Address of the atomic queue contract
     * @return REQUEST_ID Identifier for the atomic request
     */
    function sellVaultToken(
        address offerToken,
        address wantToken,
        uint256 shares,
        uint256 price,
        uint64 deadline,
        address _atomicQueue
    ) public nonReentrant onlyRole(MANAGER_ROLE) returns (uint256) {
        if (deadline < block.timestamp) {
            revert DeadlineExpired();
        }

        // Create and submit atomic request
        IAtomicQueue.AtomicRequest memory request = IAtomicQueue.AtomicRequest({
            deadline: deadline,
            atomicPrice: uint88(price), // Price per share in terms of asset
            offerAmount: uint96(shares),
            inSolve: false
        });

        IAtomicQueue queue = IAtomicQueue(_atomicQueue);
        queue.updateAtomicRequest(IERC20(offerToken), IERC20(wantToken), request);

        emit VaultTokenSellRequested(msg.sender, offerToken, shares, price);

        return REQUEST_ID;
    }

    /**
     * @notice Buy ComponentToken using `asset`
     * @dev Only the manager can call this function, will revert if
     *   the AggregateToken does not have enough `asset` to buy the ComponentToken
     * @param componentToken ComponentToken to buy
     * @param assets Amount of `asset` to pay to receive the ComponentToken
     */
    function buyComponentToken(
        IComponentToken componentToken,
        uint256 assets
    ) public nonReentrant onlyRole(MANAGER_ROLE) {
        AggregateTokenStorage storage $ = _getAggregateTokenStorage();

        if (!$.componentTokenMap[componentToken]) {
            $.componentTokenList.push(componentToken);
            $.componentTokenMap[componentToken] = true;
            emit ComponentTokenListed(componentToken);
        }

        uint256 componentTokenAmount = componentToken.deposit(assets, address(this), address(this));
        emit ComponentTokenBought(msg.sender, componentToken, componentTokenAmount, assets);
    }

    /**
     * @notice Sell ComponentToken to receive `asset`
     * @dev Only the manager can call this function, will revert if
     *   the ComponentToken does not have enough `asset` to sell to the AggregateToken
     * @param componentToken ComponentToken to sell
     * @param componentTokenAmount Amount of ComponentToken to sell
     */
    function sellComponentToken(
        IComponentToken componentToken,
        uint256 componentTokenAmount
    ) public nonReentrant onlyRole(MANAGER_ROLE) {
        uint256 assets = componentToken.redeem(componentTokenAmount, address(this), address(this));
        emit ComponentTokenSold(msg.sender, componentToken, componentTokenAmount, assets);
    }

    /**
     * @notice Request to buy ComponentToken.
     * @dev Only the manager can call this function. This function requests
     * the purchase of ComponentToken, which will be processed later.
     * @param componentToken ComponentToken to buy
     * @param assets Amount of `asset` to pay to receive the ComponentToken
     */
    function requestBuyComponentToken(
        IComponentToken componentToken,
        uint256 assets
    ) public nonReentrant onlyRole(MANAGER_ROLE) {
        uint256 requestId = componentToken.requestDeposit(assets, address(this), address(this));
        emit ComponentTokenBuyRequested(msg.sender, componentToken, assets, requestId);
    }

    /**
     * @notice Request to sell ComponentToken.
     * @dev Only the manager can call this function. This function requests
     * the sale of ComponentToken, which will be processed later.
     * @param componentToken ComponentToken to sell
     * @param componentTokenAmount Amount of ComponentToken to sell
     */
    function requestSellComponentToken(
        IComponentToken componentToken,
        uint256 componentTokenAmount
    ) public nonReentrant onlyRole(MANAGER_ROLE) {
        uint256 requestId = componentToken.requestRedeem(componentTokenAmount, address(this), address(this));
        emit ComponentTokenSellRequested(msg.sender, componentToken, componentTokenAmount, requestId);
    }

    // Admin Functions

    /**
     * @notice Set the price at which users can buy the AggregateToken using `asset`
     * @dev Only the owner can call this setter
     * @param askPrice New ask price
     */
    function setAskPrice(
        uint256 askPrice
    ) external nonReentrant onlyRole(PRICE_UPDATER_ROLE) {
        _getAggregateTokenStorage().askPrice = askPrice;
    }

    /**
     * @notice Set the price at which users can sell the AggregateToken to receive `asset`
     * @dev Only the owner can call this setter
     * @param bidPrice New bid price
     */
    function setBidPrice(
        uint256 bidPrice
    ) external nonReentrant onlyRole(PRICE_UPDATER_ROLE) {
        _getAggregateTokenStorage().bidPrice = bidPrice;
    }

    /**
     * @notice Pause the AggregateToken contract for deposits
     * @dev Only the owner can pause the AggregateToken contract for deposits
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        AggregateTokenStorage storage $ = _getAggregateTokenStorage();
        if ($.paused) {
            revert AlreadyPaused();
        }
        $.paused = true;
        emit Paused();
    }

    /**
     * @notice Unpause the AggregateToken contract for deposits
     * @dev Only the owner can unpause the AggregateToken contract for deposits
     */
    function unpause() external nonReentrant onlyRole(ADMIN_ROLE) {
        AggregateTokenStorage storage $ = _getAggregateTokenStorage();
        if (!$.paused) {
            revert NotPaused();
        }
        $.paused = false;
        emit Unpaused();
    }

    // Getter View Functions

    /// @notice Price at which users can buy the AggregateToken using `asset`, times the base
    function getAskPrice() external view returns (uint256) {
        return _getAggregateTokenStorage().askPrice;
    }

    /// @notice Price at which users can sell the AggregateToken to receive `asset`, times the base
    function getBidPrice() external view returns (uint256) {
        return _getAggregateTokenStorage().bidPrice;
    }

    /// @notice Get all ComponentTokens that have ever been added to the AggregateToken
    function getComponentTokenList() public view returns (IComponentToken[] memory) {
        return _getAggregateTokenStorage().componentTokenList;
    }

    /// @notice Returns true if the AggregateToken contract is paused for deposits
    function isPaused() external view returns (bool) {
        return _getAggregateTokenStorage().paused;
    }

    /**
     * @notice Check if the given ComponentToken is in the component token list
     * @param componentToken ComponentToken to check
     * @return isListed Boolean indicating if the ComponentToken is in the component token list
     */
    function getComponentToken(
        IComponentToken componentToken
    ) public view returns (bool isListed) {
        return _getAggregateTokenStorage().componentTokenMap[componentToken];
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ComponentToken, ERC1155Holder) returns (bool) {
        return super.supportsInterface(interfaceId) || interfaceId == type(IAggregateToken).interfaceId;
    }

}
