// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script, console2 } from "forge-std/Script.sol";
import { stPlumeMinter } from "../../src/lst/stPlumeMinter.sol";

/// @title SetupRolesAndParams
/// @notice Configure roles and parameters on stPlumeMinter
contract SetupRolesAndParams is Script {
    function run() external {
        address minterAddr = vm.envAddress("STPLUME_MINTER");
        stPlumeMinter minter = stPlumeMinter(minterAddr);

        address frxETH = _envOrAddress("FRXETH", address(0));
        address rebalancer = _envOrAddress("REBALANCER", address(0));
        address claimer = _envOrAddress("CLAIMER", address(0));

        uint256 withholdRatio = _envOrUint("WITHHOLD_RATIO", 20000); // 2%
        uint256 instantFee = _envOrUint("INSTANT_FEE_BPS", 5000); // 0.5%
        uint256 standardFee = _envOrUint("STANDARD_FEE_BPS", 150); // 0.015%
        uint256 minStake = _envOrUint("MIN_STAKE", 1e17);
        uint256 threshold = _envOrUint("WITHDRAWAL_THRESHOLD", 100000 ether);
        uint256 interval = _envOrUint("BATCH_INTERVAL", 21 days + 1 hours);
        bool pauseInstant = _envOrBool("INSTANT_PAUSE", false);
        uint256 utilBps = _envOrUint("INSTANT_UTIL_BPS", 900000); // 90%

        console2.log("stPlumeMinter:", minterAddr);
        console2.log("frxETH:", frxETH);
        console2.log("rebalancer:", rebalancer);
        console2.log("claimer:", claimer);

        vm.startBroadcast();
        // Roles
        if (rebalancer != address(0)) {
            minter.grantRole(minter.REBALANCER_ROLE(), rebalancer);
        }
        if (claimer != address(0)) {
            minter.grantRole(minter.CLAIMER_ROLE(), claimer);
        }
        if (frxETH != address(0)) {
            minter.grantRole(minter.HANDLER_ROLE(), frxETH);
        }

        // Params
        minter.setWithholdRatio(withholdRatio);
        minter.setFees(instantFee, standardFee);
        minter.setMinStake(minStake);
        minter.setBatchUnstakeParams(threshold, interval);
        minter.setInstantPolicy(pauseInstant, utilBps);
        vm.stopBroadcast();
    }

    function _envOrAddress(string memory key, address fallbackVal) internal view returns (address) {
        try vm.envAddress(key) returns (address v) { return v; } catch { return fallbackVal; }
    }
    function _envOrUint(string memory key, uint256 fallbackVal) internal view returns (uint256) {
        try vm.envUint(key) returns (uint256 v) { return v; } catch { return fallbackVal; }
    }
    function _envOrBool(string memory key, bool fallbackVal) internal view returns (bool) {
        try vm.envBool(key) returns (bool v) { return v; } catch { return fallbackVal; }
    }
}


