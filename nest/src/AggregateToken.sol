// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IComponentToken } from "./interfaces/IComponentToken.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";

/**
 * @title AggregateToken
 * @dev ERC20 token that represents a basket of other ERC20 tokens
 * Invariant: the total value of all AggregateTokens minted is equal to the total value of all of its component tokens
 */
contract AggregateToken is IComponentToken, ERC20Upgradeable {
    IERC20 public currencyToken;
    IComponentToken[] public componentTokens;
    string public tokenURI;

    // Base at which we do calculations in order to minimize rounding differences
    uint256 _BASE = 10 ** 18;

    // Price at which the vault manager is willing to sell the aggregate token, times the base
    uint256 askPrice;
    /* Price at which the vault manager is willing to buy back the aggregate token, times the base
     * This is always smaller than the ask price, so if the vault manager never changes either price,
     * then they will always be able to buy back all outstanding AggregateTokens at a profit
     */
    uint256 bidPrice;

    uint8 private _currencyDecimals;
    uint8 private _decimals;

    // Events

    /**
     * @dev Emitted when a user buys aggregateToken using currencyToken
     * @param user Address of the user who buys the aggregateToken
     * @param currencyTokenAmount Amount of currencyToken paid
     * @param aggregateTokenAmount Amount of aggregateToken bought
     */
    event Buy(address indexed user, uint256 currencyTokenAmount, uint256 aggregateTokenAmount);

    /**
     * @dev Emitted when a user sells aggregateToken for currencyToken
     * @param user Address of the user who sells the aggregateToken
     * @param currencyTokenAmount Amount of currencyToken received
     * @param aggregateTokenAmount Amount of aggregateToken sold
     */
    event Sell(address indexed user, uint256 currencyTokenAmount, uint256 aggregateTokenAmount);

    function initialize(
        string memory name,
        string memory symbol,
        uint8 __decimals,
        string memory _tokenURI,
        address _currencyToken,
        address[] _componentTokens,
        uint256 _askPrice,
        uint256 _bidPrice
    ) public initializer {
        ERC20__init(name, symbol);
        _decimals = __decimals;
        tokenURI = _tokenURI;
        currencyToken = IERC20(_currencyToken);
        _currencyDecimals = currencyToken.decimals();
        componentTokens = _componentTokens; // TODO initialize the array
        askPrice = _askPrice;
        bidPrice = _bidPrice;
    }

    // Override Functions

    /**
     * @notice Returns the number of decimals of the aggregateToken
     */
    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    // User Functions

    /**
     * @notice Buy the aggregateToken using currencyToken
     * @dev The user must approve the contract to spend the currencyToken
     * @param currencyTokenAmount Amount of currencyToken to pay for the aggregateToken
     */
    function buy(
        uint256 currencyTokenAmount
    ) public {
        // TODO: figure decimals math
        uint256 aggregateTokenAmount = currencyTokenAmount * _BASE / askPrice;

        require(currencyToken.transferFrom(msg.sender, address(this), currencyTokenAmount), "AggregateToken: failed to transfer currencyToken");
        _mint(msg.sender, aggregateTokenAmount);

        emit Buy(msg.sender, currencyTokenAmount, aggregateTokenAmount);
    }

    /**
     * @notice Sell the aggregateToken to receive currencyToken
     * @param currencyTokenAmount Amount of currencyToken to receive for the aggregateToken
     */
    function sell(
        uint256 currencyTokenAmount
    ) public {
        // TODO: figure decimals math
        uint256 aggregateTokenAmount = currencyTokenAmount * _BASE / bidPrice;

        require(currencyToken.transfer(msg.sender, currencyTokenAmount), "AggregateToken: failed to transfer currencyToken");
        _burn(msg.sender, aggregateTokenAmount);

        emit Sell(msg.sender, currencyTokenAmount, aggregateTokenAmount);
    }

    /**
     * @notice 
     */
    function claim(uint256 amount) public {
        // TODO - rebasing vs. streaming
    }

    function claimAll() public {
        uint256 amount = claimableAmount(msg.sender);
        claim(amount);
    }

    // Admin Functions

    function buyComponentToken(address token, uint256 amount) public onlyOwner {
        // TODO verify it's allowed
        IComponentToken(token).buy(amount);
    }

    function sellComponentToken(address token, uint256 amount) public onlyOwner {
        IComponentToken(token).sell(amount);
    }

    // Admin Setter Functions

    function setTokenURI(string memory uri) public onlyOwner {
        tokenURI = uri;
    }

    function addAllowedComponentToken(
        address token,
    ) public onlyOwner {
        componentTokens.push(IComponentToken(token));
    }

    function removeAllowedComponentToken(
        address token,
    ) public onlyOwner {
        componentTokens.push(IComponentToken(token));
    }

    function setAskPrice(uint256 price) public onlyOwner {
        askPrice = price;
    }
    
    function setBidPrice(uint256 price) public onlyOwner {
        bidPrice = price;
    }

    // View Functions

    function claimableAmount(address user) public view returns (uint256 amount) {
        amount = 0;
    }

    function allowedComponentTokens() public view returns (address[] memory) {

    }
}