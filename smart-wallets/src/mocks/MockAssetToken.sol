// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC20MockUpgradeable } from "@openzeppelin/contracts-upgradeable/mocks/token/ERC20MockUpgradeable.sol";
import { IAssetToken } from "../interfaces/IAssetToken.sol";
//import { ERC20Upgradeable as IERC20 } from "../../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

//import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";




/**
 * @title AssetTokenMock
 * @dev A simplified mock version of the AssetToken contract for testing purposes.
 */
 contract MockAssetToken is IAssetToken, ERC20MockUpgradeable {


    
    IERC20 private currencyToken;

    // Use upgradeable pattern, no constructor, use initializer instead
   constructor(IERC20 currencyToken_) public initializer {
        currencyToken = currencyToken_;
        __ERC20Mock_init(); // Initialize the base ERC20Mock contract
    }

    function getCurrencyToken() external view override returns (IERC20) {
        return currencyToken;
    }

    function requestYield(address from) external override {
        // Mock implementation for testing
    }


    function claimYield(address user) external override returns (IERC20 currencyToken, uint256 currencyTokenAmount){}

function getBalanceAvailable(address user) external override view returns (uint256 balanceAvailable)  {}

  function accrueYield(address user) external override {}
     function depositYield(uint256 currencyTokenAmount) external override {}






}
