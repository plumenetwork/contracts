// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { RWAStaking } from "../src/RWAStaking.sol";
import { ReserveStaking } from "../src/ReserveStaking.sol";
import { SBTC } from "../src/SBTC.sol";
import { STONE } from "../src/STONE.sol";
import { PlumePreReserveFund } from "../src/proxy/PlumePreReserveFund.sol";
import { PlumePreStaking } from "../src/proxy/PlumePreStaking.sol";

contract DeployStakingContracts is Script {

    address private constant DEPLOYER_ADDRESS = 0xDE1509CC56D740997c70E1661BA687e950B4a241;
    address private constant MULTISIG_ADDRESS = 0xa472f6bDf1E676C7B773591d5D820aDC27a2D51c;
    address private constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT_ADDRESS = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant SBTC_ADDRESS = 0x094c0e36210634c3CfA25DC11B96b562E0b07624;
    address private constant STONE_ADDRESS = 0x7122985656e38BDC0302Db86685bb972b145bD3C;

    function test() public { }

    function run() external {
        vm.startBroadcast(DEPLOYER_ADDRESS);

        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        proposers[0] = MULTISIG_ADDRESS;
        executors[0] = MULTISIG_ADDRESS;
        TimelockController timelock = new TimelockController(2 days, proposers, executors, address(0));

        RWAStaking rwaStaking = new RWAStaking();
        PlumePreStaking plumePreStaking = new PlumePreStaking(
            address(rwaStaking), abi.encodeCall(RWAStaking.initialize, (timelock, DEPLOYER_ADDRESS))
        );
        RWAStaking(address(plumePreStaking)).allowStablecoin(IERC20(USDC_ADDRESS));
        RWAStaking(address(plumePreStaking)).allowStablecoin(IERC20(USDT_ADDRESS));
        console2.log("Plume Pre-Staking Proxy deployed to:", address(plumePreStaking));

        ReserveStaking sbtcStaking = new ReserveStaking();
        PlumePreReserveFund plumePreReserveFund = new PlumePreReserveFund(
            address(sbtcStaking),
            abi.encodeCall(
                ReserveStaking.initialize, (timelock, DEPLOYER_ADDRESS, IERC20(SBTC_ADDRESS), IERC20(STONE_ADDRESS))
            )
        );
        console2.log("Plume Pre-Reserve Fund Proxy deployed to:", address(plumePreReserveFund));

        vm.stopBroadcast();
    }

}
