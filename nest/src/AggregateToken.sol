// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ERC1155Holder } from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import { ComponentToken } from "./ComponentToken.sol";
import { IAggregateToken } from "./interfaces/IAggregateToken.sol";
import { IComponentToken } from "./interfaces/IComponentToken.sol";

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

    // Events

    /// @notice Emitted when the AggregateToken contract is paused for deposits
    event Paused();

    /// @notice Emitted when the AggregateToken contract is unpaused for deposits
    event Unpaused();

    // Errors

    /**
     * @notice Indicates a failure because the ComponentToken is already in the component token list
     * @param componentToken ComponentToken that is already in the component token list
     */
    error ComponentTokenAlreadyListed(IComponentToken componentToken);

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
        super.initialize(owner, name, symbol, IERC20(address(asset_)), false, false);

        AggregateTokenStorage storage $ = _getAggregateTokenStorage();
        $.componentTokenList.push(asset_);
        $.componentTokenMap[asset_] = true;
        $.askPrice = askPrice;
        $.bidPrice = bidPrice;
        $.paused = false;
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

    /// @inheritdoc IComponentToken
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
     * @dev Only the owner can call this function
     * @param componentToken ComponentToken to approve
     * @param amount Amount of `asset` to approve
     */
    function approveComponentToken(
        IComponentToken componentToken,
        uint256 amount
    ) external nonReentrant onlyRole(ADMIN_ROLE) {
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
     * @notice Buy ComponentToken using `asset`
     * @dev Only the owner can call this function, will revert if
     *   the AggregateToken does not have enough `asset` to buy the ComponentToken
     * @param componentToken ComponentToken to buy
     * @param assets Amount of `asset` to pay to receive the ComponentToken
     */
    function buyComponentToken(
        IComponentToken componentToken,
        uint256 assets
    ) public nonReentrant onlyRole(ADMIN_ROLE) {
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
     * @dev Only the owner can call this function, will revert if
     *   the ComponentToken does not have enough `asset` to sell to the AggregateToken
     * @param componentToken ComponentToken to sell
     * @param componentTokenAmount Amount of ComponentToken to sell
     */
    function sellComponentToken(
        IComponentToken componentToken,
        uint256 componentTokenAmount
    ) public nonReentrant onlyRole(ADMIN_ROLE) {
        uint256 assets = componentToken.redeem(componentTokenAmount, address(this), address(this));
        emit ComponentTokenSold(msg.sender, componentToken, componentTokenAmount, assets);
    }

    /**
     * @notice Request to buy ComponentToken.
     * @dev Only the owner can call this function. This function requests the purchase of ComponentToken, which will be
     * processed later.
     * @param componentToken ComponentToken to buy
     * @param assets Amount of `asset` to pay to receive the ComponentToken
     */
    function requestBuyComponentToken(
        IComponentToken componentToken,
        uint256 assets
    ) public nonReentrant onlyRole(ADMIN_ROLE) {
        uint256 requestId = componentToken.requestDeposit(assets, address(this), address(this));
        emit ComponentTokenBuyRequested(msg.sender, componentToken, assets, requestId);
    }

    /**
     * @notice Request to sell ComponentToken.
     * @dev Only the owner can call this function. This function requests the sale of ComponentToken, which will be
     * processed later.
     * @param componentToken ComponentToken to sell
     * @param componentTokenAmount Amount of ComponentToken to sell
     */
    function requestSellComponentToken(
        IComponentToken componentToken,
        uint256 componentTokenAmount
    ) public nonReentrant onlyRole(ADMIN_ROLE) {
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
        // IAggregateToken interface ID - calculated in CalculateAggregateTokenInterfaceId.s.sol
        return super.supportsInterface(interfaceId) || interfaceId == 0x5f3838d6;
    }

}
