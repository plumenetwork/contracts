// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Script } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { AssetToken } from "../src/token/AssetToken.sol";

contract UpgradeAssetToken is Script, Test {

    // Address of the admin
    address private constant ADMIN_ADDRESS = 0xb015762405De8fD24d29A6e0799c12e0Ea81c1Ff;
    address private constant CURRENCY_TOKEN_ADDRESS = 0x3938A812c54304fEffD266C7E2E70B48F9475aD6;

    // Address of the deployed AssetToken proxy
    UUPSUpgradeable private constant ASSET_TOKEN_PROXY =
        UUPSUpgradeable(payable(0x2Ac2227eaD821F0499798AC844924F49CB9cFD90));

    function test() public { }

    function run() external {
        vm.startBroadcast(ADMIN_ADDRESS);

        // Deploy new implementation
        AssetToken newAssetTokenImpl = new AssetToken();
        assertGt(address(newAssetTokenImpl).code.length, 0, "AssetToken should be deployed");
        console2.log("New AssetToken Implementation deployed to:", address(newAssetTokenImpl));

        // Upgrade to new implementation
        ASSET_TOKEN_PROXY.upgradeToAndCall(address(newAssetTokenImpl), "");

        AssetToken(address(ASSET_TOKEN_PROXY)).initialize(
            ADMIN_ADDRESS, // owner
            "Mineral Vault I Security Token", // name
            "aMNRL", // symbol
            ERC20(CURRENCY_TOKEN_ADDRESS), // currencyToken
            18, // decimals
            "https://mineralvault.io/metadata/aMNRL.json", // tokenURI
            1_000_000e18, // initialSupply
            10_000_000e18, // totalValue
            false // isWhitelistEnabled
        );

        console2.log("AssetToken proxy upgraded to new implementation");

        console2.log("Upgrade complete. Proxy address:", address(ASSET_TOKEN_PROXY));

        vm.stopBroadcast();
    }

}
