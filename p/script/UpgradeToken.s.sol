// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { P } from "../src/P.sol";
import { IDeployer } from "../src/interfaces/IDeployer.sol";
import { PProxy } from "../src/proxy/PProxy.sol";
import "forge-std/Script.sol";

interface IUpgradeableProxy {

    function upgradeToAndCall(address, bytes memory) external payable;

}

contract DeployScript is Script {

    function run(address proxy) external {
        vm.startBroadcast();

        P pImpl = new P();
        console.log("pImpl deployed to:", address(pImpl));

        IUpgradeableProxy(proxy).upgradeToAndCall(address(pImpl), "");
        console.log("pProxy upgraded at:", proxy);

        vm.stopBroadcast();
    }

}
