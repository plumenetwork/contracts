// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Script } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { AssetToken } from "../src/token/AssetToken.sol";

contract UpgradeAssetToken is Script, Test {

    // Address of the admin
    address private constant ADMIN_ADDRESS = 0xb015762405De8fD24d29A6e0799c12e0Ea81c1Ff;

    // Address of the deployed AssetToken proxy
    UUPSUpgradeable private constant ASSET_TOKEN_PROXY =
        UUPSUpgradeable(payable(0x659619AEdf381c3739B0375082C2d61eC1fD8835));

    function test() public { }

    function run() external {
        vm.startBroadcast(ADMIN_ADDRESS);

        // Deploy new implementation
        AssetToken newAssetTokenImpl = new AssetToken();
        assertGt(address(newAssetTokenImpl).code.length, 0, "AssetToken should be deployed");
        console2.log("New AssetToken Implementation deployed to:", address(newAssetTokenImpl));

        // Upgrade to new implementation
        ASSET_TOKEN_PROXY.upgradeToAndCall(address(newAssetTokenImpl), "");
        console2.log("AssetToken proxy upgraded to new implementation");

        // Get the upgraded contract instance
        AssetToken assetToken = AssetToken(address(ASSET_TOKEN_PROXY));

        console2.log("Upgrade complete. Proxy address:", address(ASSET_TOKEN_PROXY));

        vm.stopBroadcast();
    }

}
