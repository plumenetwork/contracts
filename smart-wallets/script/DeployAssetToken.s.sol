// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Script } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { AssetTokenProxy } from "../src/proxy/AssetTokenProxy.sol";
import { AssetToken } from "../src/token/AssetToken.sol";

contract DeployAssetToken is Script, Test {

    // Address of the admin
    // Change this address to your own
    address private constant ADMIN_ADDRESS = 0xb015762405De8fD24d29A6e0799c12e0Ea81c1Ff;

    // Address of the currency token
    // USDC in Plume Mainnet
    address private constant CURRENCY_TOKEN_ADDRESS = 0x3938A812c54304fEffD266C7E2E70B48F9475aD6;

    function test() public { }

    function run() external {
        vm.startBroadcast(ADMIN_ADDRESS);

        AssetToken assetToken = new AssetToken();
        AssetTokenProxy assetTokenProxy = new AssetTokenProxy(
            address(assetToken),
            abi.encodeCall(
                assetToken.initialize,
                (
                    ADMIN_ADDRESS, // owner
                    "Mineral Vault I Security Token", // name
                    "aMNRL", // symbol
                    ERC20(CURRENCY_TOKEN_ADDRESS), // currencyToken
                    18, // decimals
                    "https://mineralvault.io/metadata/aMNRL.json", // tokenURI
                    1_000_000e18, // initialSupply
                    10_000_000e18, // totalValue
                    false // isWhitelistEnabled
                )
            )
        );

        console2.log("AssetToken deployed to:", address(assetTokenProxy));

        vm.stopBroadcast();
    }

}
