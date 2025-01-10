// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Script } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { YieldToken } from "../src/token/YieldToken.sol";

contract UpgradeYieldToken is Script, Test {

    // Address of the admin
    address private constant ADMIN_ADDRESS = 0xb015762405De8fD24d29A6e0799c12e0Ea81c1Ff;

    // Address of the deployed YieldToken proxy
    UUPSUpgradeable private constant YIELD_TOKEN_PROXY =
        UUPSUpgradeable(payable(0x659619AEdf381c3739B0375082C2d61eC1fD8835)); // Replace with actual proxy address

    function test() public { }

    function run() external {
        vm.startBroadcast(ADMIN_ADDRESS);

        // Deploy new implementation
        YieldToken newYieldTokenImpl = new YieldToken();
        assertGt(address(newYieldTokenImpl).code.length, 0, "YieldToken should be deployed");
        console2.log("New YieldToken Implementation deployed to:", address(newYieldTokenImpl));

        // Upgrade to new implementation
        YIELD_TOKEN_PROXY.upgradeToAndCall(address(newYieldTokenImpl), "");
        console2.log("YieldToken proxy upgraded to new implementation");

        // Get the upgraded contract instance
        YieldToken yieldToken = YieldToken(address(YIELD_TOKEN_PROXY));

        console2.log("Upgrade complete. Proxy address:", address(YIELD_TOKEN_PROXY));

        vm.stopBroadcast();
    }

}
