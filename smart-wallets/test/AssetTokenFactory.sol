// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;


import { WalletUtils } from "../src/WalletUtils.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/token/AssetToken.sol";

contract AssetTokenFactory is WalletUtils {
    address public owner;

    constructor(address _owner) {
        owner = _owner;
    }

    function deployAssetToken(
        address tokenOwner,
        string memory name,
        string memory symbol,
        ERC20 currencyToken,
        uint8 decimals,
        string memory tokenURI,
        uint256 initialSupply,
        uint256 totalValue,
        bool isWhitelistEnabled
    ) external returns (AssetToken) {
        require(msg.sender == owner, "Only owner can deploy AssetToken");
        return new AssetToken{salt: keccak256(abi.encodePacked(block.timestamp))}(
            tokenOwner,
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
}