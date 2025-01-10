// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Script } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { IAssetToken } from "../src/interfaces/IAssetToken.sol";
import { YieldToken } from "../src/token/YieldToken.sol";

contract DeployYieldToken is Script, Test {

    address private constant ADMIN_ADDRESS = 0xb015762405De8fD24d29A6e0799c12e0Ea81c1Ff;
    address private constant CURRENCY_TOKEN_ADDRESS = 0x2DEc3B6AdFCCC094C31a2DCc83a43b5042220Ea2;
    address private constant ASSET_TOKEN_ADDRESS = 0x659619AEdf381c3739B0375082C2d61eC1fD8835;

    function test() public { }

    function run() external {
        vm.startBroadcast(ADMIN_ADDRESS);

        YieldToken yieldToken = new YieldToken(
            ADMIN_ADDRESS, // owner
            "Yield Token", // name
            "YLD", // symbol
            IERC20(CURRENCY_TOKEN_ADDRESS), // currencyToken
            18, // decimals
            "https://metadata.uri", // tokenURI
            IAssetToken(ASSET_TOKEN_ADDRESS), // assetToken
            1000e18 // initialSupply
        );

        console2.log("YieldToken deployed to:", address(yieldToken));

        vm.stopBroadcast();
    }

}
