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
    address private constant USDT_ADDRESS = 0x2413b8C79Ce60045882559f63d308aE3DFE0903d;

    address private constant VAULT_TOKEN = 0xe644F07B1316f28a7F134998e021eA9f7135F351;
    address private constant ATOMIC_QUEUE = 0x9fEcc2dFA8B64c27B42757B0B9F725fe881Ddb2a;
    address private constant TELLER_ADDRESS = 0xE010B6fdcB0C1A8Bf00699d2002aD31B4bf20B86;
    address private constant LENS_ADDRESS = 0x39e4A070c3af7Ea1Cc51377D6790ED09D761d274;
    address private constant ACCOUNTANT_ADDRESS = 0x607e6E4dC179Bf754f88094C09d9ee9Af990482a;

    function run() external {
        vm.startBroadcast(NEST_ADMIN_ADDRESS);

        // Deploy pUSD implementation
        pUSD pUSDToken = new pUSD();
        console2.log("pUSD implementation deployed to:", address(pUSDToken));

        // Deploy pUSD proxy
        ERC1967Proxy pUSDProxyContract = new ERC1967Proxy(
            address(pUSDToken),
            abi.encodeCall(
                pUSD.initialize,
                (
                    NEST_ADMIN_ADDRESS,
                    IERC20(USDC_ADDRESS),
                    IERC20(USDT_ADDRESS),
                    address(VAULT_TOKEN),
                    TELLER_ADDRESS,
                    ATOMIC_QUEUE,
                    LENS_ADDRESS,
                    ACCOUNTANT_ADDRESS
                )
            )
        );
        console2.log("pUSD proxy deployed to:", address(pUSDProxyContract));

        vm.stopBroadcast();
    }

}
