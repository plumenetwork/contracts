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

contract DeployTestStakingContracts is Script {

    address private constant NEST_ADMIN_ADDRESS = 0xb015762405De8fD24d29A6e0799c12e0Ea81c1Ff;
    address private constant PUSD_ADDRESS = 0xe644F07B1316f28a7F134998e021eA9f7135F351;
    address private constant USDT_ADDRESS = 0x2413b8C79Ce60045882559f63d308aE3DFE0903d;

    function test() public { }

    function run() external {
        vm.startBroadcast(NEST_ADMIN_ADDRESS);

        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        proposers[0] = NEST_ADMIN_ADDRESS;
        executors[0] = NEST_ADMIN_ADDRESS;
        TimelockController timelock = new TimelockController(2 minutes, proposers, executors, address(0));

        RWAStaking rwaStaking = new RWAStaking();
        PlumePreStaking plumePreStaking = new PlumePreStaking(
            address(rwaStaking), abi.encodeCall(RWAStaking.initialize, (timelock, NEST_ADMIN_ADDRESS))
        );
        RWAStaking(address(plumePreStaking)).allowStablecoin(IERC20(PUSD_ADDRESS));
        RWAStaking(address(plumePreStaking)).allowStablecoin(IERC20(USDT_ADDRESS));
        console2.log("Plume Pre-Staking Proxy deployed to:", address(plumePreStaking));

        SBTC sbtc = new SBTC(NEST_ADMIN_ADDRESS);
        STONE stone = new STONE(NEST_ADMIN_ADDRESS);
        ReserveStaking sbtcStaking = new ReserveStaking();
        PlumePreReserveFund plumePreReserveFund = new PlumePreReserveFund(
            address(sbtcStaking), abi.encodeCall(ReserveStaking.initialize, (timelock, NEST_ADMIN_ADDRESS, sbtc, stone))
        );
        console2.log("Plume Pre-Reserve Fund Proxy deployed to:", address(plumePreReserveFund));

        vm.stopBroadcast();
    }

}
