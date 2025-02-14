// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Script } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { Plume } from "../src/Plume.sol";
import { PlumeStaking } from "../src/PlumeStaking.sol";
import { PlumeStakingProxy } from "../src/proxy/PlumeStakingProxy.sol";

contract DeployPlumeStaking is Script, Test {

    // Configuration Constants
    address private constant ADMIN_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;
    address private constant PLUME_TOKEN_ADDRESS = 0x17F085f1437C54498f0085102AB33e7217C067C8;
    address private constant PUSD_TOKEN_ADDRESS = 0xdddD73F5Df1F0DC31373357beAC77545dC5A6f3F;

    // Initial staking parameters
    uint256 private constant MIN_STAKE_AMOUNT = 1e18; // 1 PLUME
    uint256 private constant COOLDOWN_INTERVAL = 7 days;

    // Initial reward rates (scaled by 1e18)
    // Current setting: 6e15 (this value can be updated by admin)
    // Calculated as: (BASE * 5 * 12) / (100 * 100)
    uint256 private constant PLUME_REWARD_RATE = 6e15; // ~5% APY
    uint256 private constant PUSD_REWARD_RATE = 6e15; // ~5% APY

    function test() public { }

    function run() external {
        vm.startBroadcast(ADMIN_ADDRESS);

        // 1. Deploy implementation contract
        PlumeStaking plumeStakingImplementation = new PlumeStaking();
        console2.log("PlumeStaking Implementation deployed to:", address(plumeStakingImplementation));

        // 2. Prepare initialization data
        bytes memory initData = abi.encodeCall(
            PlumeStaking.initialize,
            (
                ADMIN_ADDRESS, // owner
                PLUME_TOKEN_ADDRESS, // plume token
                PUSD_TOKEN_ADDRESS // pUSD token
            )
        );

        // 3. Deploy proxy contract pointing to implementation
        ERC1967Proxy proxy = new PlumeStakingProxy(address(plumeStakingImplementation), initData);
        console2.log("PlumeStaking Proxy deployed to:", address(proxy));

        PlumeStaking plumeStaking = PlumeStaking(address(proxy));

        plumeStaking.addRewardToken(PUSD_TOKEN_ADDRESS);
        plumeStaking.addRewardToken(PLUME_TOKEN_ADDRESS);

        plumeStaking.setRewardRate(PUSD_TOKEN_ADDRESS, PUSD_REWARD_RATE);
        plumeStaking.setRewardRate(PLUME_TOKEN_ADDRESS, PLUME_REWARD_RATE);

        // Log deployment information
        console2.log("\nDeployment Configuration:");
        console2.log("------------------------");
        console2.log("Implementation:", address(plumeStakingImplementation));
        console2.log("Proxy:", address(proxy));
        console2.log("Admin:", ADMIN_ADDRESS);
        console2.log("PLUME Token:", PLUME_TOKEN_ADDRESS);
        console2.log("pUSD Token:", PUSD_TOKEN_ADDRESS);

        vm.stopBroadcast();
    }

}
