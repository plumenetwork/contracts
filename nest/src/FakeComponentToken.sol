// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IComponentToken } from "./interfaces/IComponentToken.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";

/**
 * @title ComponentTokenExample
 * @dev ERC20 token that represents a component of an AggregateToken
 * Invariant: the total value of all ComponentTokens minted is equal to the total value of all of its component tokens
 */
contract ComponentToken is IComponentToken, ERC20Upgradeable {
    IERC20 public currencyToken;

    // Base at which we do calculations in order to minimize rounding differences
    uint256 _BASE = 10 ** 18;

    // Price at which the vault manager is willing to sell the aggregate token, times the base
    uint256 askPrice;
    /* Price at which the vault manager is willing to buy back the aggregate token, times the base
     * This is always smaller than the ask price, so if the vault manager never changes either price,
     * then they will always be able to buy back all outstanding ComponentTokens at a profit
     */
    uint256 bidPrice;

    uint8 private _currencyDecimals;
    uint8 private _decimals;

    // Events

    /**
     * @dev Emitted when a user stakes currencyToken to receive aggregateToken in return
     * @param user Address of the user who staked the currencyToken
     * @param currencyTokenAmount Amount of currencyToken staked
     * @param aggregateTokenAmount Amount of aggregateToken received
     */
    event Buy(address indexed user, uint256 currencyTokenAmount, uint256 aggregateTokenAmount);

    /**
     * @dev Emitted when a user unstakes aggregateToken to receive currencyToken in return
     * @param user Address of the user who unstaked the aggregateToken
     * @param currencyTokenAmount Amount of currencyToken received
     * @param aggregateTokenAmount Amount of aggregateToken unstaked
     */
    event Sell(address indexed user, uint256 currencyTokenAmount, uint256 aggregateTokenAmount);

    function initialize(
        string memory name,
        string memory symbol,
        uint8 __decimals,
        string memory _tokenURI,
        address _currencyToken,
        uint256 _askPrice,
        uint256 _bidPrice
    ) public initializer {
        tokenURI = _tokenURI;

        currencyToken = IERC20(_currencyToken);
        _currencyDecimals = currencyToken.decimals();
        askPrice = _askPrice;
        bidPrice = _bidPrice;
        _decimals = __decimals;
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
     * @notice Stake the currencyToken to receive aggregateToken in return
     * @dev The user must approve the contract to spend the currencyToken
     * @param currencyTokenAmount Amount of currencyToken to stake
     */
    function buy(
        address currencyToken,
        uint256 currencyTokenAmount
    ) public {
        /*
        // TODO: figure decimals math
        uint256 aggregateTokenAmount = currencyTokenAmount * _BASE / askPrice;

        require(currencyToken.transferFrom(msg.sender, address(this), currencyTokenAmount), "AggregateToken: failed to transfer currencyToken");
        _mint(msg.sender, aggregateTokenAmount);

        emit Staked(msg.sender, currencyTokenAmount, aggregateTokenAmount);
        */

        DEX.swap(p, address(this));

    }

    /**
     * @notice Unstake the aggregateToken to receive currencyToken in return
     * @param currencyTokenAmount Amount of currencyToken to receive
     */
    function (
        address currencyToken,
        uint256 currencyTokenAmount
    ) public {
        // TODO: figure decimals math
        uint256 aggregateTokenAmount = currencyTokenAmount * _BASE / bidPrice;

        require(currencyToken.transfer(msg.sender, currencyTokenAmount), "AggregateToken: failed to transfer currencyToken");
        _burn(msg.sender, aggregateTokenAmount);

        emit Unstaked(msg.sender, currencyTokenAmount, aggregateTokenAmount);
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

    // Admin Setter Functions

    function setAskPrice(uint256 price) public onlyOwner {
        askPrice = price;
    }
    
    function setBidPrice(uint256 price) public onlyOwner {
        bidPrice = price;
    }
}