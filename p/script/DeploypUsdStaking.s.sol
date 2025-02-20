// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Script } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { Plume } from "../src/Plume.sol";
import { pUSDStaking } from "../src/pUSDStaking.sol";
import { pUSDStakingProxy } from "../src/proxy/pUSDStakingProxy.sol";

contract DeploypUSDStaking is Script {

    // Configuration Constants
    address private constant ADMIN_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;
    address private constant PLUME_TOKEN_ADDRESS = 0x17F085f1437C54498f0085102AB33e7217C067C8;
    address private constant PUSD_TOKEN_ADDRESS = 0xdddD73F5Df1F0DC31373357beAC77545dC5A6f3F;

    // Initial staking parameters
    uint256 private constant MIN_STAKE_AMOUNT = 1e18; // 1 PLUME
    uint256 private constant COOLDOWN_INTERVAL = 7 days;

    // Initial reward rates (scaled by 1e18)
    // Current setting: 6e15 (this value can be updated by admin)
    // Calculated as: (BASE * 0.05 ) / (31536000)
    uint256 private constant PLUME_REWARD_RATE = 0; // ~0% APY
    uint256 private constant PUSD_REWARD_RATE = 1_587_301_587; // ~5% APY

    function run() external {
        vm.startBroadcast(ADMIN_ADDRESS);

        // 1. Deploy implementation contract
        pUSDStaking pUSDStakingImplementation = new pUSDStaking();
        console2.log("pUSDStaking Implementation deployed to:", address(pUSDStakingImplementation));

        // 2. Prepare initialization data
        bytes memory initData = abi.encodeCall(
            pUSDStaking.initialize,
            (
                ADMIN_ADDRESS, // owner
                PLUME_TOKEN_ADDRESS, // plume token
                PUSD_TOKEN_ADDRESS // pUSD token
            )
        );

        // 3. Deploy proxy contract pointing to implementation
        ERC1967Proxy proxy = new pUSDStakingProxy(address(pUSDStakingImplementation), initData);
        console2.log("pUSDStaking Proxy deployed to:", address(proxy));

        pUSDStaking pusdstaking = pUSDStaking(address(proxy));

        // Log deployment information
        console2.log("\nDeployment Configuration:");
        console2.log("------------------------");
        console2.log("Implementation:", address(pUSDStakingImplementation));
        console2.log("Proxy:", address(proxy));
        console2.log("Admin:", ADMIN_ADDRESS);
        console2.log("PLUME Token:", PLUME_TOKEN_ADDRESS);
        console2.log("pUSD Token:", PUSD_TOKEN_ADDRESS);

        vm.stopBroadcast();
    }

}
