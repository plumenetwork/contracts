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
    address private constant CURRENCY_TOKEN_ADDRESS = 0x3938A812c54304fEffD266C7E2E70B48F9475aD6;
    address private constant ASSET_TOKEN_ADDRESS = 0x2Ac2227eaD821F0499798AC844924F49CB9cFD90;

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
                    "Mineral Vault I Yield Token",
                    "yMNRL",
                    IERC20(CURRENCY_TOKEN_ADDRESS),
                    18,
                    "https://mineralvault.io/metadata/yMNRL.json",
                    IAssetToken(ASSET_TOKEN_ADDRESS),
                    1_000_000e18
                )
            )
        );

        console2.log("YieldToken deployed to:", address(yieldTokenProxy));

        vm.stopBroadcast();
    }

}
