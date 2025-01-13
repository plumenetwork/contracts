// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Script } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { IAssetToken } from "../src/interfaces/IAssetToken.sol";

import { YieldTokenProxy } from "../src/proxy/YieldTokenProxy.sol";
import { YieldToken } from "../src/token/YieldToken.sol";

contract DeployYieldToken is Script, Test {

    // Change these addresses
    address private constant ADMIN_ADDRESS = 0xb015762405De8fD24d29A6e0799c12e0Ea81c1Ff;
    address private constant CURRENCY_TOKEN_ADDRESS = 0xdddD73F5Df1F0DC31373357beAC77545dC5A6f3F;
    address private constant ASSET_TOKEN_ADDRESS = 0x659619AEdf381c3739B0375082C2d61eC1fD8835;

    function test() public { }

    function run() external {
        vm.startBroadcast(ADMIN_ADDRESS);

        YieldToken yieldToken = new YieldToken();
        YieldTokenProxy yieldTokenProxy = new YieldTokenProxy(
            address(yieldToken),
            abi.encodeCall(
                yieldToken.initialize,
                (
                    ADMIN_ADDRESS,
                    "Yield Token",
                    "YLD",
                    IERC20(CURRENCY_TOKEN_ADDRESS),
                    18,
                    "https://metadata.uri",
                    IAssetToken(ASSET_TOKEN_ADDRESS),
                    1000e18
                )
            )
        );

        console2.log("YieldToken deployed to:", address(yieldTokenProxy));

        vm.stopBroadcast();
    }

}
