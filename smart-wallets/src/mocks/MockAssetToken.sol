// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IAssetToken } from "../interfaces/IAssetToken.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MockAssetToken
 * @dev A simplified mock version of the AssetToken contract for testing purposes.
 */
contract MockAssetToken is IAssetToken, ERC20Upgradeable, OwnableUpgradeable {

    IERC20 private _currencyToken;
    bool public isWhitelistEnabled;
    mapping(address => bool) private _whitelist;
    uint256 private _totalValue;

    function initialize(
        address owner,
        string memory name,
        string memory symbol,
        IERC20 currencyToken_,
        bool isWhitelistEnabled_
    ) public initializer {
        __ERC20_init(name, symbol);
        __Ownable_init(owner);
        _currencyToken = currencyToken_;
        isWhitelistEnabled = isWhitelistEnabled_;
    }

    function getCurrencyToken() external view override returns (IERC20) {
        return _currencyToken;
    }

    function requestYield(address from) external override {
        // Mock implementation for testing
    }

    function claimYield(address user) external override returns (IERC20, uint256) {
        // Mock implementation
        return (_currencyToken, 0);
    }

    function getBalanceAvailable(address user) external view override returns (uint256) {
        return balanceOf(user);
    }

    function accrueYield(address user) external override {
        // Mock implementation
    }

    function depositYield(uint256 currencyTokenAmount) external override {
        // Mock implementation
    }

    // Additional functions to mock AssetToken behavior

    function addToWhitelist(address user) external onlyOwner {
        _whitelist[user] = true;
    }

    function removeFromWhitelist(address user) external onlyOwner {
        _whitelist[user] = false;
    }

    function isAddressWhitelisted(address user) external view returns (bool) {
        return _whitelist[user];
    }

    function setTotalValue(uint256 totalValue_) external onlyOwner {
        _totalValue = totalValue_;
    }

    function getTotalValue() external view returns (uint256) {
        return _totalValue;
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    // Updated transfer function with explicit override
    function transfer(address to, uint256 amount) public virtual override(ERC20Upgradeable, IERC20) returns (bool) {
        if (isWhitelistEnabled) {
            require(_whitelist[_msgSender()] && _whitelist[to], "Transfer not allowed: address not whitelisted");
        }
        return super.transfer(to, amount);
    }

    // Updated transferFrom function with explicit override
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override(ERC20Upgradeable, IERC20) returns (bool) {
        if (isWhitelistEnabled) {
            require(_whitelist[from] && _whitelist[to], "Transfer not allowed: address not whitelisted");
        }
        return super.transferFrom(from, to, amount);
    }

}
