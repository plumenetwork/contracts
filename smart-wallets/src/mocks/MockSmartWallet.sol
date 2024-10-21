// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { WalletUtils } from "../WalletUtils.sol";
import { AssetToken } from "../token/AssetToken.sol";

contract MockSmartWallet is WalletUtils {
    function deployAssetToken(
        string memory name,
        string memory symbol,
        ERC20 currencyToken,
        uint8 decimals,
        string memory tokenURI,
        uint256 initialSupply,
        uint256 totalValue,
        bool isWhitelistEnabled
    ) external onlyWallet returns (AssetToken) {
        return new AssetToken(
            address(this),
            name,
            symbol,
            currencyToken,
            decimals,
            tokenURI,
            initialSupply,
            totalValue,
            isWhitelistEnabled
        );
    }


    function verifySetup() public pure returns (bool) {
        return true;
    }


}