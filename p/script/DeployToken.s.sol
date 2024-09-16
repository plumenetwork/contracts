// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";

import { P } from "../src/P.sol";
import { IDeployer } from "../src/interfaces/IDeployer.sol";
import { PProxy } from "../src/proxy/PProxy.sol";

/**
 * @title DeployToken
 * @author Eugene Y. Q. Shen
 * @notice Deploys P to a deterministic address 0x4C1746A800D224393fE2470C70A35717eD4eA5F1
 */
contract DeployToken is Script {

    bytes32 private constant DEPLOY_SALT = keccak256("P");
    address private constant DEPLOYER_ADDRESS = 0x6513Aedb4D1593BA12e50644401D976aebDc90d8;

    function run(address admin) external {
        vm.startBroadcast();

        P pImpl = new P();
        console.log("pImpl deployed to:", address(pImpl));

        address pProxy = IDeployer(DEPLOYER_ADDRESS).deploy(
            abi.encodePacked(
                type(PProxy).creationCode, abi.encode(pImpl, abi.encodeWithSelector(P.initialize.selector, admin))
            ),
            DEPLOY_SALT
        );
        console.log("pProxy deployed to:", pProxy);

        vm.stopBroadcast();
    }

}