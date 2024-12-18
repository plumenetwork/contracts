// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { USDTProxy } from "../src/proxy/USDTProxy.sol";
import { USDT } from "../src/token/USDT.sol";
import { USDTAsset } from "../src/token/USDTAsset.sol";

contract DeployUSDT is Script {

    address private constant NEST_ADMIN_ADDRESS = 0xb015762405De8fD24d29A6e0799c12e0Ea81c1Ff;

    function run() external {
        vm.startBroadcast(NEST_ADMIN_ADDRESS);

        USDTAsset usdtAsset = new USDTAsset(NEST_ADMIN_ADDRESS);
        console2.log("USDT Asset deployed to:", address(usdtAsset));

        USDT usdt = new USDT();
        USDTProxy usdtProxy =
            new USDTProxy(address(usdt), abi.encodeCall(USDT.initialize, (NEST_ADMIN_ADDRESS, usdtAsset)));
        console2.log("USDT Component Token Proxy deployed to:", address(usdtProxy));

        vm.stopBroadcast();
    }

}
