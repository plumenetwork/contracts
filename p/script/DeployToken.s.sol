// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";

import { Plume } from "../src/Plume.sol";
import { IDeployer } from "../src/interfaces/IDeployer.sol";
import { PlumeProxy } from "../src/proxy/PlumeProxy.sol";

/**
 * @title DeployToken
 * @author Eugene Y. Q. Shen
 * @notice Deploys Plume to a deterministic address 0x4C1746A800D224393fE2470C70A35717eD4eA5F1
 */
contract DeployToken is Script {

    bytes32 private constant DEPLOY_SALT = keccak256("P");
    address private constant DEPLOYER_ADDRESS = 0x6513Aedb4D1593BA12e50644401D976aebDc90d8;

    function run(
        address admin
    ) external {
        vm.startBroadcast();

        Plume plumeImpl = new Plume();
        console.log("plumeImpl deployed to:", address(plumeImpl));

        address plumeProxy = IDeployer(DEPLOYER_ADDRESS).deploy(
            abi.encodePacked(
                type(PlumeProxy).creationCode,
                abi.encode(plumeImpl, abi.encodeWithSelector(Plume.initialize.selector, admin))
            ),
            DEPLOY_SALT
        );
        console.log("plumeProxy deployed to:", plumeProxy);

        vm.stopBroadcast();
    }

}
