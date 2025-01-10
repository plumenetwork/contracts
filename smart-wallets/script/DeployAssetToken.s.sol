// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Script } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { AssetToken } from "../src/token/AssetToken.sol";

contract DeployAssetToken is Script, Test {

    // Address of the admin
    address private constant ADMIN_ADDRESS = 0xb015762405De8fD24d29A6e0799c12e0Ea81c1Ff;

    // Address of the currency token
    address private constant CURRENCY_TOKEN_ADDRESS = 0x2DEc3B6AdFCCC094C31a2DCc83a43b5042220Ea2;

    function test() public { }

    function run() external {
        vm.startBroadcast(ADMIN_ADDRESS);

        AssetToken assetToken = new AssetToken(
            ADMIN_ADDRESS, // owner
            "Real World Asset Token", // name
            "RWA", // symbol
            ERC20(CURRENCY_TOKEN_ADDRESS), // currencyToken
            18, // decimals
            "https://metadata.uri", // tokenURI
            1000e18, // initialSupply
            1_000_000e18, // totalValue
            false // isWhitelistEnabled
        );

        console2.log("AssetToken deployed to:", address(assetToken));

        vm.stopBroadcast();
    }

}
