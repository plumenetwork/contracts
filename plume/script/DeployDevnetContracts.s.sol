// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { Faucet } from "../src/Faucet.sol";
import { FaucetProxy } from "../src/proxy/FaucetProxy.sol";

contract DeployDevnetContracts is Script {

    address private constant FAUCET_ADMIN_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;
    address private constant PLUME_ADDRESS = address(1);
    address private constant USDT_ADDRESS = 0x2413b8C79Ce60045882559f63d308aE3DFE0903d;

    string[] private tokens = ["PLUME"];
    address[] private tokenAddresses = [PLUME_ADDRESS];

    function run() external {
        vm.startBroadcast(FAUCET_ADMIN_ADDRESS);

        Faucet faucet = new Faucet();
        FaucetProxy faucetProxy = new FaucetProxy(
            address(faucet), abi.encodeCall(Faucet.initialize, (FAUCET_ADMIN_ADDRESS, tokens, tokenAddresses))
        );
        console2.log("Faucet Proxy deployed to:", address(faucetProxy));

        vm.stopBroadcast();
    }

}
