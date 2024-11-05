// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { RWAStaking } from "../src/RWAStaking.sol";
import { ReserveStaking } from "../src/ReserveStaking.sol";

contract UpgradeTestTimelockContracts is Script {

    address private constant DEPLOYER_ADDRESS = 0xDE1509CC56D740997c70E1661BA687e950B4a241;
    address private constant NEST_ADMIN_ADDRESS = 0xb015762405De8fD24d29A6e0799c12e0Ea81c1Ff;
    address private constant PUSD_ADDRESS = 0xe644F07B1316f28a7F134998e021eA9f7135F351;
    address private constant USDT_ADDRESS = 0x2413b8C79Ce60045882559f63d308aE3DFE0903d;
    UUPSUpgradeable private constant PLUME_PRESTAKING_PROXY =
        UUPSUpgradeable(payable(0x6d4780D9cC966B2D34180b7A27f7B677a392BfDE));
    UUPSUpgradeable private constant PLUME_PRERESERVE_FUND_PROXY =
        UUPSUpgradeable(payable(0x056CEc6F5E66bA56F66005D8Ff3Bb2bad347d707));

    function test() public { }

    function run() external {
        vm.startBroadcast(DEPLOYER_ADDRESS);

        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        proposers[0] = NEST_ADMIN_ADDRESS;
        executors[0] = NEST_ADMIN_ADDRESS;
        TimelockController timelock = new TimelockController(2 minutes, proposers, executors, address(0));

        RWAStaking newRwaStakingImpl = new RWAStaking();
        console2.log("New Pre-Staking Implementation deployed to:", address(newRwaStakingImpl));
        ReserveStaking newReserveStakingImpl = new ReserveStaking();
        console2.log("New Pre-Reserve Fund Implementation deployed to:", address(newReserveStakingImpl));

        PLUME_PRESTAKING_PROXY.upgradeToAndCall(
            address(newRwaStakingImpl),
            abi.encodeWithSelector(RWAStaking.reinitialize.selector, NEST_ADMIN_ADDRESS, timelock)
        );
        PLUME_PRERESERVE_FUND_PROXY.upgradeToAndCall(
            address(newReserveStakingImpl),
            abi.encodeWithSelector(ReserveStaking.reinitialize.selector, NEST_ADMIN_ADDRESS, timelock)
        );

        vm.stopBroadcast();
    }

}
