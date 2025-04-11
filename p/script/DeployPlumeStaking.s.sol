// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Script } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { Plume } from "../src/Plume.sol";
import { PlumeStaking_Monolithic } from "../src/PlumeStaking_Monolithic.sol";

import { IPlumeStaking } from "../src/interfaces/IPlumeStaking.sol";
import { PlumeStakingProxy } from "../src/proxy/PlumeStakingProxy.sol";

contract DeployPlumeStaking is Script {

    // Configuration Constants
    address private constant ADMIN_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;
    address private constant PLUME_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address private constant PUSD_TOKEN_ADDRESS = 0xdddD73F5Df1F0DC31373357beAC77545dC5A6f3F;
    address private constant PLUME_NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // Initial staking parameters
    uint256 private constant MIN_STAKE_AMOUNT = 1e18; // 1 PLUME
    uint256 private constant COOLDOWN_INTERVAL = 7 days;
    uint256 private constant REWARD_PRECISION = 1e18;

    // Initial reward rates (scaled by REWARD_PRECISION)
    // Current setting: ~5% APY
    // Calculated as: (REWARD_PRECISION * 0.05) / (365 * 24 * 60 * 60)
    uint256 private constant PLUME_REWARD_RATE = 1_587_301_587;
    uint256 private constant PUSD_REWARD_RATE = 1_587_301_587;

    function run() external {
        vm.startBroadcast(ADMIN_ADDRESS);

        // 1. Deploy implementation contract
        PlumeStaking_Monolithic plumeStakingImplementation = new PlumeStaking_Monolithic();
        console2.log("PlumeStaking Implementation deployed to:", address(plumeStakingImplementation));

        // 2. Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            IPlumeStaking.initialize.selector,
            ADMIN_ADDRESS // owner
        );

        // 3. Deploy proxy contract pointing to implementation
        ERC1967Proxy proxy = new PlumeStakingProxy(address(plumeStakingImplementation), initData);
        console2.log("PlumeStaking Proxy deployed to:", address(proxy));

        PlumeStaking_Monolithic plumeStaking = PlumeStaking_Monolithic(payable(address(proxy)));

        // 4. Add reward tokens
        plumeStaking.addRewardToken(PUSD_TOKEN_ADDRESS);
        plumeStaking.addRewardToken(PLUME_NATIVE); // Use PLUME_NATIVE constant for native token

        // 5. Set reward rates using arrays
        address[] memory tokens = new address[](2);
        uint256[] memory rates = new uint256[](2);

        tokens[0] = PUSD_TOKEN_ADDRESS;
        tokens[1] = PLUME_NATIVE;
        rates[0] = PUSD_REWARD_RATE;
        rates[1] = PLUME_REWARD_RATE;

        plumeStaking.setRewardRates(tokens, rates);

        // 6. Set initial parameters
        plumeStaking.setMinStakeAmount(MIN_STAKE_AMOUNT);
        plumeStaking.setCooldownInterval(COOLDOWN_INTERVAL);

        // Log deployment information
        console2.log("\nDeployment Configuration:");
        console2.log("------------------------");
        console2.log("Implementation:", address(plumeStakingImplementation));
        console2.log("Proxy:", address(proxy));
        console2.log("Admin:", ADMIN_ADDRESS);
        console2.log("PLUME Token:", PLUME_TOKEN_ADDRESS);
        console2.log("PLUME Native:", PLUME_NATIVE);
        console2.log("pUSD Token:", PUSD_TOKEN_ADDRESS);
        console2.log("Min Stake Amount:", MIN_STAKE_AMOUNT);
        console2.log("Cooldown Interval:", COOLDOWN_INTERVAL);
        console2.log("PLUME Reward Rate:", PLUME_REWARD_RATE);
        console2.log("pUSD Reward Rate:", PUSD_REWARD_RATE);

        vm.stopBroadcast();
    }

}
