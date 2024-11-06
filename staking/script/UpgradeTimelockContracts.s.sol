// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { Script } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { RWAStaking } from "../src/RWAStaking.sol";
import { ReserveStaking } from "../src/ReserveStaking.sol";

contract DeployStakingContracts is Script, Test {

    address private constant DEPLOYER_ADDRESS = 0xDE1509CC56D740997c70E1661BA687e950B4a241;
    address private constant MULTISIG_ADDRESS = 0xa472f6bDf1E676C7B773591d5D820aDC27a2D51c;
    UUPSUpgradeable private constant PLUME_PRESTAKING_PROXY =
        UUPSUpgradeable(payable(0xdbd03D676e1cf3c3b656972F88eD21784372AcAB));
    UUPSUpgradeable private constant PLUME_PRERESERVE_FUND_PROXY =
        UUPSUpgradeable(payable(0xBa0Ae7069f94643853Fce3B8Af7f55AcBC11e397));

    function test() public { }

    function run() external {
        vm.startBroadcast(DEPLOYER_ADDRESS);

        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        proposers[0] = MULTISIG_ADDRESS;
        executors[0] = MULTISIG_ADDRESS;
        TimelockController timelock = new TimelockController(2 days, proposers, executors, address(0));

        RWAStaking newRwaStakingImpl = new RWAStaking();
        assertGt(address(newRwaStakingImpl).code.length, 0, "RWAStaking should be deployed");
        console2.log("New Pre-Staking Implementation deployed to:", address(newRwaStakingImpl));
        ReserveStaking newReserveStakingImpl = new ReserveStaking();
        assertGt(address(newReserveStakingImpl).code.length, 0, "ReserveStaking should be deployed");
        console2.log("New Pre-Reserve Fund Implementation deployed to:", address(newReserveStakingImpl));

        PLUME_PRESTAKING_PROXY.upgradeToAndCall(
            address(newRwaStakingImpl),
            abi.encodeWithSelector(RWAStaking.reinitialize.selector, MULTISIG_ADDRESS, timelock)
        );
        PLUME_PRERESERVE_FUND_PROXY.upgradeToAndCall(
            address(newReserveStakingImpl),
            abi.encodeWithSelector(ReserveStaking.reinitialize.selector, MULTISIG_ADDRESS, timelock)
        );

        vm.stopBroadcast();
    }

}
