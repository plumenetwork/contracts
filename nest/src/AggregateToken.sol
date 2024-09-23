// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAggregateToken } from "./interfaces/IAggregateToken.sol";
import { IComponentToken } from "./interfaces/IComponentToken.sol";

/**
 * @title AggregateToken
 * @author Eugene Y. Q. Shen
 * @notice ERC20 token that represents a basket of ComponentTokens
 * @dev Invariant: the total value of all AggregateTokens minted is approximately
 *   equal to the total value of all of its constituent ComponentTokens
 */
contract AggregateToken is
    Initializable,
    ERC20Upgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    IAggregateToken
{

    // Storage

    /// @custom:storage-location erc7201:plume.storage.AggregateToken
    struct AggregateTokenStorage {
        /// @dev List of all ComponentTokens that have ever been added to the AggregateToken
        IComponentToken[] componentTokenList;
        /// @dev Mapping of all ComponentTokens that have ever been added to the AggregateToken
        mapping(IComponentToken componentToken => bool exists) componentTokenMap;
        /// @dev CurrencyToken used to mint and burn the AggregateToken
        IERC20 currencyToken;
        /// @dev Number of decimals of the AggregateToken
        uint8 decimals;
        /// @dev Price at which users can buy the AggregateToken using CurrencyToken, times the base
        uint256 askPrice;
        /// @dev Price at which users can sell the AggregateToken to receive CurrencyToken, times the base
        uint256 bidPrice;
        /// @dev URI for the AggregateToken metadata
        string tokenURI;
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

    /// @notice Role for the upgrader of the AggregateToken
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // Base that is used to divide all price inputs in order to represent e.g. 1.000001 as 1000001e12
    uint256 private constant _BASE = 1e18;

    // Events

    /**
     * @notice Emitted when a user buys AggregateToken using CurrencyToken
     * @param user Address of the user who bought the AggregateToken
     * @param currencyToken CurrencyToken used to buy the AggregateToken
     * @param currencyTokenAmount Amount of CurrencyToken paid
     * @param aggregateTokenAmount Amount of AggregateToken received
     */
    event AggregateTokenBought(
        address indexed user, IERC20 indexed currencyToken, uint256 currencyTokenAmount, uint256 aggregateTokenAmount
    );

    /**
     * @notice Emitted when a user sells AggregateToken to receive CurrencyToken
     * @param user Address of the user who sold the AggregateToken
     * @param currencyToken CurrencyToken received in exchange for the AggregateToken
     * @param currencyTokenAmount Amount of CurrencyToken received
     * @param aggregateTokenAmount Amount of AggregateToken sold
     */
    event AggregateTokenSold(
        address indexed user, IERC20 indexed currencyToken, uint256 currencyTokenAmount, uint256 aggregateTokenAmount
    );

    /**
     * @notice Emitted when a ComponentToken is added to the component token list
     * @param componentToken ComponentToken that is added to the component token list
     */
    event ComponentTokenListed(IComponentToken componentToken);

    /**
     * @notice Emitted when a ComponentToken is removed from the component token list
     * @param componentToken ComponentToken that is removed from the component token list
     */
    event ComponentTokenUnlisted(IComponentToken componentToken);

    /**
     * @notice Emitted when the owner buys ComponentToken using CurrencyToken
     * @param owner Address of the owner who bought the ComponentToken
     * @param currencyToken CurrencyToken used to buy the ComponentToken
     * @param currencyTokenAmount Amount of CurrencyToken paid
     * @param componentTokenAmount Amount of ComponentToken received
     */
    event ComponentTokenBought(
        address indexed owner, IERC20 indexed currencyToken, uint256 currencyTokenAmount, uint256 componentTokenAmount
    );

    /**
     * @notice Emitted when the owner sells ComponentToken to receive CurrencyToken
     * @param owner Address of the owner who sold the ComponentToken
     * @param currencyToken CurrencyToken received in exchange for the ComponentToken
     * @param currencyTokenAmount Amount of CurrencyToken received
     * @param componentTokenAmount Amount of ComponentToken sold
     */
    event ComponentTokenSold(
        address indexed owner, IERC20 indexed currencyToken, uint256 currencyTokenAmount, uint256 componentTokenAmount
    );

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
     * @notice Indicates a failure because the ComponentToken is the current CurrencyToken
     * @param componentToken ComponentToken that is the current CurrencyToken
     */
    error ComponentTokenIsCurrencyTOken(IComponentToken componentToken);

    /**
     * @notice Indicates a failure because the given CurrencyToken does not match the actual CurrencyToken
     * @param invalidCurrencyToken CurrencyToken that does not match the actual CurrencyToken
     * @param currencyToken Actual CurrencyToken used to mint and burn the AggregateToken
     */
    error InvalidCurrencyToken(IERC20 invalidCurrencyToken, IERC20 currencyToken);

    /**
     * @notice Indicates a failure because the AggregateToken does not have enough CurrencyToken
     * @param currencyToken CurrencyToken used to mint and burn the AggregateToken
     * @param amount Amount of CurrencyToken required in the failed transfer
     */
    error CurrencyTokenInsufficientBalance(IERC20 currencyToken, uint256 amount);

    /**
     * @notice Indicates a failure because the user does not have enough CurrencyToken
     * @param currencyToken CurrencyToken used to mint and burn the AggregateToken
     * @param user Address of the user who is selling the CurrencyToken
     * @param amount Amount of CurrencyToken required in the failed transfer
     */
    error UserCurrencyTokenInsufficientBalance(IERC20 currencyToken, address user, uint256 amount);

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
     * @param currencyToken CurrencyToken used to mint and burn the AggregateToken
     * @param decimals_ Number of decimals of the AggregateToken
     * @param askPrice Price at which users can buy the AggregateToken using CurrencyToken, times the base
     * @param bidPrice Price at which users can sell the AggregateToken to receive CurrencyToken, times the base
     * @param tokenURI URI of the AggregateToken metadata
     */
    function initialize(
        address owner,
        string memory name,
        string memory symbol,
        IComponentToken currencyToken,
        uint8 decimals_,
        uint256 askPrice,
        uint256 bidPrice,
        string memory tokenURI
    ) public initializer {
        __ERC20_init(name, symbol);
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(UPGRADER_ROLE, owner);

        AggregateTokenStorage storage $ = _getAggregateTokenStorage();
        $.componentTokenList.push(currencyToken);
        $.componentTokenMap[currencyToken] = true;
        $.currencyToken = IERC20(currencyToken);
        $.decimals = decimals_;
        $.askPrice = askPrice;
        $.bidPrice = bidPrice;
        $.tokenURI = tokenURI;
    }

    // Override Functions

    /**
     * @notice Revert when `msg.sender` is not authorized to upgrade the contract
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) { }

    /// @notice Number of decimals of the AggregateToken
    function decimals() public view override returns (uint8) {
        return _getAggregateTokenStorage().decimals;
    }

    // User Functions

    /**
     * @notice Buy AggregateToken using CurrencyToken
     * @dev The user must approve the contract to spend the CurrencyToken
     * @param currencyToken CurrencyToken used to buy the AggregateToken
     * @param currencyTokenAmount Amount of CurrencyToken to pay for the AggregateToken
     * @return aggregateTokenAmount Amount of AggregateToken received
     */
    function buy(IERC20 currencyToken, uint256 currencyTokenAmount) public returns (uint256 aggregateTokenAmount) {
        AggregateTokenStorage storage $ = _getAggregateTokenStorage();

        if (currencyToken != $.currencyToken) {
            revert InvalidCurrencyToken(currencyToken, $.currencyToken);
        }
        if (!currencyToken.transferFrom(msg.sender, address(this), currencyTokenAmount)) {
            revert UserCurrencyTokenInsufficientBalance(currencyToken, msg.sender, currencyTokenAmount);
        }

        aggregateTokenAmount = currencyTokenAmount * _BASE / $.askPrice;

        _mint(msg.sender, aggregateTokenAmount);

        emit AggregateTokenBought(msg.sender, currencyToken, currencyTokenAmount, aggregateTokenAmount);
    }

    /**
     * @notice Sell AggregateToken to receive CurrencyToken
     * @param currencyToken CurrencyToken received in exchange for the AggregateToken
     * @param currencyTokenAmount Amount of CurrencyToken to receive in exchange for the AggregateToken
     * @return aggregateTokenAmount Amount of AggregateToken sold
     */
    function sell(IERC20 currencyToken, uint256 currencyTokenAmount) public returns (uint256 aggregateTokenAmount) {
        AggregateTokenStorage storage $ = _getAggregateTokenStorage();

        if (currencyToken != $.currencyToken) {
            revert InvalidCurrencyToken(currencyToken, $.currencyToken);
        }
        if (!currencyToken.transfer(msg.sender, currencyTokenAmount)) {
            revert CurrencyTokenInsufficientBalance(currencyToken, currencyTokenAmount);
        }

        aggregateTokenAmount = currencyTokenAmount * _BASE / $.bidPrice;

        _burn(msg.sender, aggregateTokenAmount);

        emit AggregateTokenSold(msg.sender, currencyToken, currencyTokenAmount, aggregateTokenAmount);
    }

    // Admin Functions

    /**
     * @notice Add a ComponentToken to the component token list
     * @dev Only the owner can call this function
     * @param componentToken ComponentToken to add
     */
    function addComponentToken(IComponentToken componentToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
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
     * @dev Only the owner can call this function
     * @param componentToken ComponentToken to remove
     */
    function removeComponentToken(IComponentToken componentToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        AggregateTokenStorage storage $ = _getAggregateTokenStorage();
        if (!$.componentTokenMap[componentToken]) {
            revert ComponentTokenNotListed(componentToken);
        }
        if (componentToken.balanceOf(address(this)) > 0) {
            revert ComponentTokenBalanceNonZero(componentToken);
        }
        if (componentToken == $.currencyToken) {
            revert ComponentTokenIsCurrencyTOken(componentToken);
        }
        uint256 length = $.componentTokenList.length;
        for (uint256 i = 0; i < length; ++i) {
            if ($.componentTokenList[i] == componentToken) {
                $.componentTokenList[i] = $.componentTokenList[length - 1];
                $.componentTokenList.pop();
                break;
            }
        }
        $.componentTokenMap[componentToken] = false;
        emit ComponentTokenUnlisted(componentToken);
    }

    /**
     * @notice Buy ComponentToken using CurrencyToken
     * @dev Only the owner can call this function, will revert if
     *   the AggregateToken does not have enough CurrencyToken to buy the ComponentToken
     * @param componentToken ComponentToken to buy
     * @param currencyTokenAmount Amount of CurrencyToken to pay to receive the ComponentToken
     */
    function buyComponentToken(
        IComponentToken componentToken,
        uint256 currencyTokenAmount
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        AggregateTokenStorage storage $ = _getAggregateTokenStorage();

        if (!$.componentTokenMap[componentToken]) {
            $.componentTokenList.push(componentToken);
            $.componentTokenMap[componentToken] = true;
            emit ComponentTokenListed(componentToken);
        }

        IERC20 currencyToken = $.currencyToken;
        currencyToken.approve(address(componentToken), currencyTokenAmount);
        uint256 componentTokenAmount = componentToken.buy(currencyToken, currencyTokenAmount);
        componentToken.approve(address(componentToken), 0);

        emit ComponentTokenBought(msg.sender, $.currencyToken, currencyTokenAmount, componentTokenAmount);
    }

    /**
     * @notice Sell ComponentToken to receive CurrencyToken
     * @dev Only the owner can call this function, will revert if
     *   the ComponentToken does not have enough CurrencyToken to sell to the AggregateToken
     * @param componentToken ComponentToken to sell
     * @param currencyTokenAmount Amount of CurrencyToken to receive in exchange for the ComponentToken
     */
    function sellComponentToken(
        IComponentToken componentToken,
        uint256 currencyTokenAmount
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20 currencyToken = _getAggregateTokenStorage().currencyToken;

        uint256 componentTokenAmount = componentToken.sell(currencyToken, currencyTokenAmount);

        emit ComponentTokenSold(msg.sender, currencyToken, currencyTokenAmount, componentTokenAmount);
    }

    // Admin Setter Functions

    /**
     * @notice Set the CurrencyToken used to mint and burn the AggregateToken
     * @dev Only the owner can call this setter
     * @param currencyToken New CurrencyToken
     */
    function setCurrencyToken(IERC20 currencyToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _getAggregateTokenStorage().currencyToken = currencyToken;
    }

    /**
     * @notice Set the price at which users can buy the AggregateToken using CurrencyToken
     * @dev Only the owner can call this setter
     * @param askPrice New ask price
     */
    function setAskPrice(uint256 askPrice) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _getAggregateTokenStorage().askPrice = askPrice;
    }

    /**
     * @notice Set the price at which users can sell the AggregateToken to receive CurrencyToken
     * @dev Only the owner can call this setter
     * @param bidPrice New bid price
     */
    function setBidPrice(uint256 bidPrice) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _getAggregateTokenStorage().bidPrice = bidPrice;
    }

    /**
     * @notice Set the URI for the AggregateToken metadata
     * @dev Only the owner can call this setter
     * @param tokenURI New token URI
     */
    function setTokenURI(string memory tokenURI) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _getAggregateTokenStorage().tokenURI = tokenURI;
    }

    // Getter View Functions

    /// @notice CurrencyToken used to mint and burn the AggregateToken
    function getCurrencyToken() external view returns (IERC20) {
        return _getAggregateTokenStorage().currencyToken;
    }

    /// @notice Price at which users can buy the AggregateToken using CurrencyToken, times the base
    function getAskPrice() external view returns (uint256) {
        return _getAggregateTokenStorage().askPrice;
    }

    /// @notice Price at which users can sell the AggregateToken to receive CurrencyToken, times the base
    function getBidPrice() external view returns (uint256) {
        return _getAggregateTokenStorage().bidPrice;
    }

    /// @notice URI for the AggregateToken metadata
    function getTokenURI() external view returns (string memory) {
        return _getAggregateTokenStorage().tokenURI;
    }

    /// @notice Get all ComponentTokens that have ever been added to the AggregateToken
    function getComponentTokenList() public view returns (IComponentToken[] memory) {
        return _getAggregateTokenStorage().componentTokenList;
    }

    /**
     * @notice Check if the given ComponentToken is in the component token list
     * @param componentToken ComponentToken to check
     * @return isListed Boolean indicating if the ComponentToken is in the component token list
     */
    function getComponentToken(IComponentToken componentToken) public view returns (bool isListed) {
        return _getAggregateTokenStorage().componentTokenMap[componentToken];
    }

}
