// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IAssetToken } from "../interfaces/IAssetToken.sol";
import { YieldToken } from "../token/YieldToken.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockYieldToken is YieldToken {

    constructor(
        address owner,
        string memory name,
        string memory symbol,
        IERC20 currencyToken,
        uint8 decimals_,
        string memory tokenURI_,
        IAssetToken assetToken,
        uint256 initialSupply
    ) YieldToken(owner, name, symbol, currencyToken, decimals_, tokenURI_, assetToken, initialSupply) { }

    // Expose internal functions for testing
    function notifyDeposit(uint256 assets, uint256 shares, address controller) external {
        _notifyDeposit(assets, shares, controller);
    }

    function notifyRedeem(uint256 assets, uint256 shares, address controller) external {
        _notifyRedeem(assets, shares, controller);
    }

}
