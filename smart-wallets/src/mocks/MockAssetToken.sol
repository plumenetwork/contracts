// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC20MockUpgradeable as ERC20Mock } from "../../lib/openzeppelin-contracts-upgradeable/contracts/mocks/token/ERC20MockUpgradeable.sol";
import { IAssetToken } from "../interfaces/IAssetToken.sol";
//import { ERC20Upgradeable as IERC20 } from "../../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

//import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title AssetTokenMock
 * @dev A simplified mock version of the AssetToken contract for testing purposes.
 */
abstract contract MockAssetToken is IAssetToken, ERC20Mock {
    IERC20 private currencyToken;

    // Constructor
    constructor(IERC20 _currencyToken) ERC20Mock("Asset Token", "AST", msg.sender, 1_000 ether) {
        currencyToken = _currencyToken;
    }

    // Function to simulate the getCurrencyToken method
    function getCurrencyToken() external view returns (IERC20 currencyToken) {
        return currencyToken;
    }

    // Simulate yield redistribution (simplified for testing)
    function requestYield(address from) external override {
        // In the real implementation, this would redistribute yield from the smart wallet.
        // For now, this is just a placeholder to satisfy the IAssetToken interface.
    }
    /*
    function depositYield(uint256 timestamp, uint256 currencyTokenAmount) external;
    function getBalanceAvailable(address user) external view returns (uint256 balanceAvailable);
*/


}
