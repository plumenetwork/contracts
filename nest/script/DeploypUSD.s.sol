// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { pUSDProxy } from "../src/proxy/pUSDProxy.sol";
import { pUSD } from "../src/token/pUSD.sol";

contract DeploypUSD is Script {

    address private constant NEST_ADMIN_ADDRESS = 0xb015762405De8fD24d29A6e0799c12e0Ea81c1Ff;
    address private constant USDC_ADDRESS = 0x401eCb1D350407f13ba348573E5630B83638E30D;
    address private constant VAULT_TOKEN = 0xe644F07B1316f28a7F134998e021eA9f7135F351;

    function run() external {
        vm.startBroadcast(NEST_ADMIN_ADDRESS);

        // Deploy pUSD implementation
        pUSD pUSDToken = new pUSD();
        console2.log("pUSD implementation deployed to:", address(pUSDToken));

        // Deploy pUSD proxy
        ERC1967Proxy pUSDProxy = new ERC1967Proxy(
            address(pUSDToken),
            abi.encodeCall(
                pUSD.initialize,
                (
                    NEST_ADMIN_ADDRESS, // owner
                    IERC20(USDC_ADDRESS), // asset token (USDC)
                    VAULT_TOKEN // vault token address
                )
            )
        );
        console2.log("pUSD proxy deployed to:", address(pUSDProxy));

        vm.stopBroadcast();
    }

}
