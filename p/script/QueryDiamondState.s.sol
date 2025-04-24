// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script, console2 } from "forge-std/Script.sol";

// --- Diamond Interfaces & Base Contract ---

import { PlumeStaking } from "../src/PlumeStaking.sol";
import { ISolidStateDiamond } from "@solidstate/proxy/diamond/ISolidStateDiamond.sol"; // Needed for PlumeStaking
    // specific views like isInitialized

// --- Facet Interfaces (or full contracts for easy casting) ---
import { AccessControlFacet } from "../src/facets/AccessControlFacet.sol";
import { ManagementFacet } from "../src/facets/ManagementFacet.sol";

import { RewardsFacet } from "../src/facets/RewardsFacet.sol";
import { StakingFacet } from "../src/facets/StakingFacet.sol";
import { ValidatorFacet } from "../src/facets/ValidatorFacet.sol";

// --- Libs & Structs ---

import { PlumeRoles } from "../src/lib/PlumeRoles.sol";
import { PlumeStakingStorage } from "../src/lib/PlumeStakingStorage.sol";

// --- Standard Contracts ---
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title QueryDiamondState
 * @notice A script to query read-only functions across all facets of the deployed PlumeStaking diamond.
 * @dev Run this script against a network using:
 *      forge script script/QueryDiamondState.s.sol:QueryDiamondState --rpc-url <your_rpc_url> -vvv
 */
contract QueryDiamondState is Script {

    // --- Configuration ---
    // !!! IMPORTANT: Replace with your ACTUAL deployed diamond address !!!
    address private constant DIAMOND_PROXY_ADDRESS = 0xA20bfe49969D4a0E9abfdb6a46FeD777304ba07f; // Address from
        // conversation history

    // Known addresses/IDs for querying specific data points
    address private constant KNOWN_ADMIN = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5; // Address from conversation
        // history
    address private constant SAMPLE_USER_FOR_QUERY = address(0x1); // A generic address unlikely to have state
    address private constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; // Address for native ETH/PLUME
    // address private constant PUSD_TOKEN = address(0x...); // !!! Replace with deployed MockPUSD address if checking
    // PUSD specifically !!!
    uint16 private constant DEFAULT_VALIDATOR_ID = 1;
    uint16 private constant SECOND_VALIDATOR_ID = 1;
    uint16 private constant NON_EXISTENT_VALIDATOR_ID = 999;

    // Pre-calculate the hash for comparison
    bytes32 internal constant PROXY_ERROR_HASH = keccak256(bytes("Proxy__ImplementationIsNotContract()"));

    function run() external view {
        console2.log("--- Querying Plume Staking Diamond State ---");
        console2.log("Diamond Proxy Address:", DIAMOND_PROXY_ADDRESS);
        console2.log("Querying using Admin:", KNOWN_ADMIN);
        console2.log("Querying using Sample User:", SAMPLE_USER_FOR_QUERY);

        // --- Instantiate Facet Interfaces ---
        PlumeStaking stakingBase = PlumeStaking(payable(DIAMOND_PROXY_ADDRESS));
        AccessControlFacet accessControl = AccessControlFacet(DIAMOND_PROXY_ADDRESS);
        ManagementFacet management = ManagementFacet(DIAMOND_PROXY_ADDRESS);
        StakingFacet staking = StakingFacet(DIAMOND_PROXY_ADDRESS);
        ValidatorFacet validator = ValidatorFacet(DIAMOND_PROXY_ADDRESS);
        RewardsFacet rewards = RewardsFacet(DIAMOND_PROXY_ADDRESS);

        // --- PlumeStaking (Base Proxy) Queries ---
        console2.log("\n--- Base Proxy State ---");
        try stakingBase.isInitialized() returns (bool initialized) {
            console2.log("isInitialized():", initialized);
        } catch Error(string memory reason) {
            if (keccak256(bytes(reason)) == PROXY_ERROR_HASH) {
                console2.log("isInitialized() FAILED: Proxy__ImplementationIsNotContract()");
            } else {
                console2.log("isInitialized() FAILED:", reason);
            }
        } catch Panic(uint256 code) {
            console2.log("isInitialized() PANICKED:", code);
        }

        // --- AccessControlFacet Queries ---
        console2.log("\n--- Access Control State ---");
        bytes32[] memory rolesToCheck = new bytes32[](5);
        rolesToCheck[0] = bytes32(0); // DEFAULT_ADMIN_ROLE is bytes32(0)
        rolesToCheck[1] = PlumeRoles.ADMIN_ROLE;
        rolesToCheck[2] = PlumeRoles.UPGRADER_ROLE;
        rolesToCheck[3] = PlumeRoles.VALIDATOR_ROLE;
        rolesToCheck[4] = PlumeRoles.REWARD_MANAGER_ROLE;

        for (uint256 i = 0; i < rolesToCheck.length; i++) {
            bytes32 role = rolesToCheck[i];
            try accessControl.getRoleAdmin(role) returns (bytes32 adminRole) {
                console2.log("getRoleAdmin(%s): %s", vm.toString(role), vm.toString(adminRole));
            } catch Error(string memory reason) {
                if (keccak256(bytes(reason)) == PROXY_ERROR_HASH) {
                    console2.log("getRoleAdmin(%s) FAILED: Proxy__ImplementationIsNotContract()", vm.toString(role));
                } else {
                    console2.log("getRoleAdmin(%s) FAILED: %s", vm.toString(role), reason);
                }
            } catch Panic(uint256 code) {
                console2.log("getRoleAdmin(%s) PANICKED: %s", vm.toString(role), code);
            }

            try accessControl.hasRole(role, KNOWN_ADMIN) returns (bool hasRoleAdmin) {
                console2.log("  - hasRole(%s, KNOWN_ADMIN): %s", vm.toString(role), hasRoleAdmin);
            } catch Error(string memory reason) {
                if (keccak256(bytes(reason)) == PROXY_ERROR_HASH) {
                    console2.log(
                        "hasRole(%s, KNOWN_ADMIN) FAILED: Proxy__ImplementationIsNotContract()", vm.toString(role)
                    );
                } else {
                    console2.log("hasRole(%s, KNOWN_ADMIN) FAILED: %s", vm.toString(role), reason);
                }
            } catch Panic(uint256 code) {
                console2.log("hasRole(%s, KNOWN_ADMIN) PANICKED: %s", vm.toString(role), code);
            }

            try accessControl.hasRole(role, SAMPLE_USER_FOR_QUERY) returns (bool hasRoleSample) {
                console2.log("  - hasRole(%s, SAMPLE_USER): %s", vm.toString(role), hasRoleSample);
            } catch Error(string memory reason) {
                if (keccak256(bytes(reason)) == PROXY_ERROR_HASH) {
                    console2.log(
                        "hasRole(%s, SAMPLE_USER) FAILED: Proxy__ImplementationIsNotContract()", vm.toString(role)
                    );
                } else {
                    console2.log("hasRole(%s, SAMPLE_USER) FAILED: %s", vm.toString(role), reason);
                }
            } catch Panic(uint256 code) {
                console2.log("hasRole(%s, SAMPLE_USER) PANICKED: %s", vm.toString(role), code);
            }
        }

        // --- ManagementFacet Queries ---
        console2.log("\n--- Management State ---");
        try management.getMinStakeAmount() returns (uint256 minStake) {
            console2.log("getMinStakeAmount():", minStake);
        } catch Error(string memory reason) {
            if (keccak256(bytes(reason)) == PROXY_ERROR_HASH) {
                console2.log("getMinStakeAmount() FAILED: Proxy__ImplementationIsNotContract()");
            } else {
                console2.log("getMinStakeAmount() FAILED:", reason);
            }
        } catch Panic(uint256 code) {
            console2.log("getMinStakeAmount() PANICKED:", code);
        }

        try management.getCooldownInterval() returns (uint256 cooldown) {
            console2.log("getCooldownInterval():", cooldown);
        } catch Error(string memory reason) {
            if (keccak256(bytes(reason)) == PROXY_ERROR_HASH) {
                console2.log("getCooldownInterval() FAILED: Proxy__ImplementationIsNotContract()");
            } else {
                console2.log("getCooldownInterval() FAILED:", reason);
            }
        } catch Panic(uint256 code) {
            console2.log("getCooldownInterval() PANICKED:", code);
        }

        // --- StakingFacet Queries ---
        console2.log("\n--- Staking State (for SAMPLE_USER: %s) ---", SAMPLE_USER_FOR_QUERY);
        try staking.stakeInfo(SAMPLE_USER_FOR_QUERY) returns (PlumeStakingStorage.StakeInfo memory info) {
            console2.log("stakeInfo(SAMPLE_USER):");
            console2.log("  - staked:", info.staked);
            console2.log("  - cooled:", info.cooled);
            console2.log("  - parked:", info.parked);
            console2.log("  - cooldownEnd:", info.cooldownEnd);
            console2.log("  - lastUpdateTimestamp:", info.lastUpdateTimestamp);
        } catch Error(string memory reason) {
            if (keccak256(bytes(reason)) == PROXY_ERROR_HASH) {
                console2.log("stakeInfo(SAMPLE_USER) FAILED: Proxy__ImplementationIsNotContract()");
            } else {
                console2.log("stakeInfo(SAMPLE_USER) FAILED:", reason);
            }
        } catch Panic(uint256 code) {
            console2.log("stakeInfo(SAMPLE_USER) PANICKED:", code);
        }

        try staking.amountStaked() returns (uint256 staked) {
            console2.log("amountStaked(msg.sender):", staked);
        } catch Error(string memory reason) {
            if (keccak256(bytes(reason)) == PROXY_ERROR_HASH) {
                console2.log("amountStaked(msg.sender) FAILED: Proxy__ImplementationIsNotContract()");
            } else {
                console2.log("amountStaked(msg.sender) FAILED:", reason);
            }
        } catch Panic(uint256 code) {
            console2.log("amountStaked(msg.sender) PANICKED:", code);
        }

        try staking.amountCooling() returns (uint256 cooling) {
            console2.log("amountCooling(msg.sender):", cooling);
        } catch Error(string memory reason) {
            if (keccak256(bytes(reason)) == PROXY_ERROR_HASH) {
                console2.log("amountCooling(msg.sender) FAILED: Proxy__ImplementationIsNotContract()");
            } else {
                console2.log("amountCooling(msg.sender) FAILED:", reason);
            }
        } catch Panic(uint256 code) {
            console2.log("amountCooling(msg.sender) PANICKED:", code);
        }

        try staking.amountWithdrawable() returns (uint256 withdrawable) {
            console2.log("amountWithdrawable(msg.sender):", withdrawable);
        } catch Error(string memory reason) {
            if (keccak256(bytes(reason)) == PROXY_ERROR_HASH) {
                console2.log("amountWithdrawable(msg.sender) FAILED: Proxy__ImplementationIsNotContract()");
            } else {
                console2.log("amountWithdrawable(msg.sender) FAILED:", reason);
            }
        } catch Panic(uint256 code) {
            console2.log("amountWithdrawable(msg.sender) PANICKED:", code);
        }

        try staking.cooldownEndDate() returns (uint256 endDate) {
            console2.log("cooldownEndDate(msg.sender):", endDate);
        } catch Error(string memory reason) {
            if (keccak256(bytes(reason)) == PROXY_ERROR_HASH) {
                console2.log("cooldownEndDate(msg.sender) FAILED: Proxy__ImplementationIsNotContract()");
            } else {
                console2.log("cooldownEndDate(msg.sender) FAILED:", reason);
            }
        } catch Panic(uint256 code) {
            console2.log("cooldownEndDate(msg.sender) PANICKED:", code);
        }

        try staking.getUserValidatorStake(SAMPLE_USER_FOR_QUERY, DEFAULT_VALIDATOR_ID) returns (uint256 stake) {
            console2.log("getUserValidatorStake(SAMPLE_USER, Validator %s): %s", DEFAULT_VALIDATOR_ID, stake);
        } catch Error(string memory reason) {
            if (keccak256(bytes(reason)) == PROXY_ERROR_HASH) {
                console2.log(
                    "getUserValidatorStake(SAMPLE_USER, Validator %s) FAILED: Proxy__ImplementationIsNotContract()",
                    DEFAULT_VALIDATOR_ID
                );
            } else {
                console2.log(
                    "getUserValidatorStake(SAMPLE_USER, Validator %s) FAILED: %s", DEFAULT_VALIDATOR_ID, reason
                );
            }
        } catch Panic(uint256 code) {
            console2.log("getUserValidatorStake(SAMPLE_USER, Validator %s) PANICKED: %s", DEFAULT_VALIDATOR_ID, code);
        }

        // --- Global Staking Amounts (from StakingFacet) ---
        console2.log("\n--- Global Staking Totals (from StakingFacet) ---");
        try staking.totalAmountStaked() returns (uint256 totalStaked) {
            console2.log("totalAmountStaked():", totalStaked);
        } catch Error(string memory reason) {
            if (keccak256(bytes(reason)) == PROXY_ERROR_HASH) {
                console2.log("totalAmountStaked() FAILED: Proxy__ImplementationIsNotContract()");
            } else {
                console2.log("totalAmountStaked() FAILED:", reason);
            }
        } catch Panic(uint256 code) {
            console2.log("totalAmountStaked() PANICKED:", code);
        }

        try staking.totalAmountCooling() returns (uint256 totalCooling) {
            console2.log("totalAmountCooling():", totalCooling);
        } catch Error(string memory reason) {
            if (keccak256(bytes(reason)) == PROXY_ERROR_HASH) {
                console2.log("totalAmountCooling() FAILED: Proxy__ImplementationIsNotContract()");
            } else {
                console2.log("totalAmountCooling() FAILED:", reason);
            }
        } catch Panic(uint256 code) {
            console2.log("totalAmountCooling() PANICKED:", code);
        }

        try staking.totalAmountWithdrawable() returns (uint256 totalWithdrawable) {
            console2.log("totalAmountWithdrawable():", totalWithdrawable);
        } catch Error(string memory reason) {
            if (keccak256(bytes(reason)) == PROXY_ERROR_HASH) {
                console2.log("totalAmountWithdrawable() FAILED: Proxy__ImplementationIsNotContract()");
            } else {
                console2.log("totalAmountWithdrawable() FAILED:", reason);
            }
        } catch Panic(uint256 code) {
            console2.log("totalAmountWithdrawable() PANICKED:", code);
        }

        // --- ValidatorFacet Queries ---
        console2.log("\n--- Validator State ---");
        try validator.getActiveValidatorCount() returns (uint256 count) {
            console2.log("getActiveValidatorCount():", count);
        } catch Error(string memory reason) {
            if (keccak256(bytes(reason)) == PROXY_ERROR_HASH) {
                console2.log("getActiveValidatorCount() FAILED: Proxy__ImplementationIsNotContract()");
            } else {
                console2.log("getActiveValidatorCount() FAILED:", reason);
            }
        } catch Panic(uint256 code) {
            console2.log("getActiveValidatorCount() PANICKED:", code);
        }

        try validator.getValidatorsList() returns (ValidatorFacet.ValidatorListData[] memory list) {
            console2.log("getValidatorsList() Count:", list.length);
            // Optionally loop and print details, but can be verbose
            // Note: Accessing struct fields directly might fail if called externally, depends on ABI encoder
            // for (uint i = 0; i < list.length; i++) {
            //     try validator.getValidatorsList()[i] returns (uint16 id, uint256 totalStaked, uint256 commission) {
            //         console2.log("  Validator %s: ID=%s, Staked=%s, Commission=%s", i, id, totalStaked, commission);
            //     } catch {} // Ignore if direct struct access fails
            // }
        } catch Error(string memory reason) {
            if (keccak256(bytes(reason)) == PROXY_ERROR_HASH) {
                console2.log("getValidatorsList() FAILED: Proxy__ImplementationIsNotContract()");
            } else {
                console2.log("getValidatorsList() FAILED:", reason);
            }
        } catch Panic(uint256 code) {
            console2.log("getValidatorsList() PANICKED:", code);
        }

        // Query specific validators (User limited this to 1 validator)
        uint16[] memory validatorIdsToQuery = new uint16[](1);
        validatorIdsToQuery[0] = DEFAULT_VALIDATOR_ID;

        for (uint256 i = 0; i < validatorIdsToQuery.length; i++) {
            uint16 valId = validatorIdsToQuery[i];
            console2.log("\nQuerying Validator ID:", valId);
            try validator.getValidatorInfo(valId) returns (
                PlumeStakingStorage.ValidatorInfo memory info, uint256 totalStaked, uint256 stakerCount
            ) {
                console2.log("  getValidatorInfo(%s):", valId);
                console2.log("    - validatorId:", info.validatorId);
                console2.log("    - commission:", info.commission);
                console2.log("    - l2AdminAddress:", info.l2AdminAddress);
                console2.log("    - l2WithdrawAddress:", info.l2WithdrawAddress);
                console2.log("    - l1ValidatorAddress:", info.l1ValidatorAddress);
                console2.log("    - l1AccountAddress:", info.l1AccountAddress);
                console2.log("    - l1AccountEvmAddress:", info.l1AccountEvmAddress);
                console2.log("    - maxCapacity:", info.maxCapacity);
                console2.log("    - active:", info.active);
                console2.log("    - slashed:", info.slashed);
                console2.log("    - (Returned totalStaked):", totalStaked);
                console2.log("    - (Returned stakerCount):", stakerCount);
            } catch Error(string memory reason) {
                if (keccak256(bytes(reason)) == PROXY_ERROR_HASH) {
                    console2.log("getValidatorInfo(%s) FAILED: Proxy__ImplementationIsNotContract()", valId);
                } else {
                    console2.log("getValidatorInfo(%s) FAILED: %s", valId, reason);
                }
            } catch Panic(uint256 code) {
                console2.log("getValidatorInfo(%s) PANICKED: %s", valId, code);
            }

            try validator.getValidatorStats(valId) returns (bool, uint256, uint256, uint256) {
                console2.log("  getValidatorStats(%s): OK (values logged if uncommented)", valId);
            } catch Error(string memory reason) {
                if (keccak256(bytes(reason)) == PROXY_ERROR_HASH) {
                    console2.log("getValidatorStats(%s) FAILED: Proxy__ImplementationIsNotContract()", valId);
                } else {
                    console2.log("getValidatorStats(%s) FAILED: %s", valId, reason);
                }
            } catch Panic(uint256 code) {
                console2.log("getValidatorStats(%s) PANICKED: %s", valId, code);
            }

            try validator.getAccruedCommission(valId, NATIVE_TOKEN) returns (uint256 commissionNative) {
                console2.log("  getAccruedCommission(%s, NATIVE): %s", valId, commissionNative);
            } catch Error(string memory reason) {
                if (keccak256(bytes(reason)) == PROXY_ERROR_HASH) {
                    console2.log("getAccruedCommission(%s, NATIVE) FAILED: Proxy__ImplementationIsNotContract()", valId);
                } else {
                    console2.log("getAccruedCommission(%s, NATIVE) FAILED: %s", valId, reason);
                }
            } catch Panic(uint256 code) {
                console2.log("getAccruedCommission(%s, NATIVE) PANICKED: %s", valId, code);
            }
            // Add similar try/catch for PUSD_TOKEN if address is known and you want to check it
        }

        try validator.getUserValidators(SAMPLE_USER_FOR_QUERY) returns (uint16[] memory userVals) {
            console2.log("getUserValidators(SAMPLE_USER): Count =", userVals.length);
        } catch Error(string memory reason) {
            if (keccak256(bytes(reason)) == PROXY_ERROR_HASH) {
                console2.log("getUserValidators(SAMPLE_USER) FAILED: Proxy__ImplementationIsNotContract()");
            } else {
                console2.log("getUserValidators(SAMPLE_USER) FAILED:", reason);
            }
        } catch Panic(uint256 code) {
            console2.log("getUserValidators(SAMPLE_USER) PANICKED:", code);
        }

        // --- RewardsFacet Queries ---
        console2.log("\n--- Rewards State ---");

        address treasuryAddr;
        try rewards.getTreasury() returns (address addr) {
            treasuryAddr = addr;
            console2.log("getTreasury():", treasuryAddr);
        } catch Error(string memory reason) {
            if (keccak256(bytes(reason)) == PROXY_ERROR_HASH) {
                console2.log("getTreasury() FAILED: Proxy__ImplementationIsNotContract()");
            } else {
                console2.log("getTreasury() FAILED:", reason);
            }
        } catch Panic(uint256 code) {
            console2.log("getTreasury() PANICKED:", code);
        }

        address[] memory rewardTokens;
        try rewards.getRewardTokens() returns (address[] memory tokens) {
            rewardTokens = tokens;
            console2.log("getRewardTokens(): Count =", tokens.length);
            for (uint256 i = 0; i < tokens.length; i++) {
                console2.log("  - Token %s: %s", i, tokens[i]);
            }
        } catch Error(string memory reason) {
            if (keccak256(bytes(reason)) == PROXY_ERROR_HASH) {
                console2.log("getRewardTokens() FAILED: Proxy__ImplementationIsNotContract()");
            } else {
                console2.log("getRewardTokens() FAILED:", reason);
            }
        } catch Panic(uint256 code) {
            console2.log("getRewardTokens() PANICKED:", code);
        }

        // Query details for each discovered reward token
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            console2.log("\nQuerying for Reward Token:", token);

            try rewards.getMaxRewardRate(token) returns (uint256 maxRate) {
                console2.log("  getMaxRewardRate(%s): %s", token, maxRate);
            } catch Error(string memory reason) {
                if (keccak256(bytes(reason)) == PROXY_ERROR_HASH) {
                    console2.log("getMaxRewardRate(%s) FAILED: Proxy__ImplementationIsNotContract()", token);
                } else {
                    console2.log("getMaxRewardRate(%s) FAILED: %s", token, reason);
                }
            } catch Panic(uint256 code) {
                console2.log("getMaxRewardRate(%s) PANICKED: %s", token, code);
            }

            try rewards.tokenRewardInfo(token) returns (
                uint256 rewardRate, uint256 lastUpdateTime, uint256 rewardRateCheckpointCount
            ) {
                console2.log("  tokenRewardInfo(%s):", token);
                console2.log("    - rewardRate:", rewardRate);
                console2.log("    - lastUpdateTime:", lastUpdateTime);
                console2.log("    - rewardRateCheckpointCount:", rewardRateCheckpointCount);
            } catch Error(string memory reason) {
                if (keccak256(bytes(reason)) == PROXY_ERROR_HASH) {
                    console2.log("tokenRewardInfo(%s) FAILED: Proxy__ImplementationIsNotContract()", token);
                } else {
                    console2.log("tokenRewardInfo(%s) FAILED: %s", token, reason);
                }
            } catch Panic(uint256 code) {
                console2.log("tokenRewardInfo(%s) PANICKED: %s", token, code);
            }

            try rewards.getRewardRateCheckpointCount(token) returns (uint256 count) {
                console2.log("  getRewardRateCheckpointCount(%s): %s", token, count);
                if (count > 0) {
                    // Corrected: Expect 3 return values
                    try rewards.getRewardRateCheckpoint(token, 0) returns (
                        uint256 timestamp, uint256 rate, uint256 cumulativeIndex
                    ) {
                        console2.log(
                            "    - Checkpoint 0: Timestamp=%s, Rate=%s, CumulativeIndex=%s",
                            timestamp,
                            rate,
                            cumulativeIndex
                        );
                    } catch Error(string memory reason) {
                        if (keccak256(bytes(reason)) == PROXY_ERROR_HASH) {
                            console2.log(
                                "getRewardRateCheckpoint(%s, 0) FAILED: Proxy__ImplementationIsNotContract()", token
                            );
                        } else {
                            console2.log("getRewardRateCheckpoint(%s, 0) FAILED: %s", token, reason);
                        }
                    } catch Panic(uint256 code) {
                        console2.log("getRewardRateCheckpoint(%s, 0) PANICKED: %s", token, code);
                    }
                }
            } catch Error(string memory reason) {
                if (keccak256(bytes(reason)) == PROXY_ERROR_HASH) {
                    console2.log("getRewardRateCheckpointCount(%s) FAILED: Proxy__ImplementationIsNotContract()", token);
                } else {
                    console2.log("getRewardRateCheckpointCount(%s) FAILED: %s", token, reason);
                }
            } catch Panic(uint256 code) {
                console2.log("getRewardRateCheckpointCount(%s) PANICKED: %s", token, code);
            }

            // --- Validator-Specific Reward Checks ---
            uint16[] memory validatorIdsForRewards = new uint16[](2);
            validatorIdsForRewards[0] = DEFAULT_VALIDATOR_ID;
            validatorIdsForRewards[1] = SECOND_VALIDATOR_ID;
            for (uint256 vIdx = 0; vIdx < validatorIdsForRewards.length; vIdx++) {
                uint16 vId = validatorIdsForRewards[vIdx];
                try rewards.getValidatorRewardRateCheckpointCount(vId, token) returns (uint256 count) {
                    console2.log("  getValidatorRewardRateCheckpointCount(Val %s, Token %s): %s", vId, token, count);
                    if (count > 0) {
                        // Corrected: Expect 3 return values
                        try rewards.getValidatorRewardRateCheckpoint(vId, token, 0) returns (
                            uint256 timestamp, uint256 rate, uint256 cumulativeIndex
                        ) {
                            console2.log(
                                "    - Validator Checkpoint 0: Timestamp=%s, Rate=%s, CumulativeIndex=%s",
                                timestamp,
                                rate,
                                cumulativeIndex
                            );
                        } catch Error(string memory reason) {
                            if (keccak256(bytes(reason)) == PROXY_ERROR_HASH) {
                                console2.log(
                                    "getValidatorRewardRateCheckpoint(Val %s, Token %s, 0) FAILED: Proxy__ImplementationIsNotContract()",
                                    vId,
                                    token
                                );
                            } else {
                                console2.log(
                                    "getValidatorRewardRateCheckpoint(Val %s, Token %s, 0) FAILED: %s",
                                    vId,
                                    token,
                                    reason
                                );
                            }
                        } catch Panic(uint256 code) {
                            console2.log(
                                "getValidatorRewardRateCheckpoint(Val %s, Token %s, 0) PANICKED: %s", vId, token, code
                            );
                        }
                    }
                } catch Error(string memory reason) {
                    if (keccak256(bytes(reason)) == PROXY_ERROR_HASH) {
                        console2.log(
                            "getValidatorRewardRateCheckpointCount(Val %s, Token %s) FAILED: Proxy__ImplementationIsNotContract()",
                            vId,
                            token
                        );
                    } else {
                        console2.log(
                            "getValidatorRewardRateCheckpointCount(Val %s, Token %s) FAILED: %s", vId, token, reason
                        );
                    }
                } catch Panic(uint256 code) {
                    console2.log(
                        "getValidatorRewardRateCheckpointCount(Val %s, Token %s) PANICKED: %s", vId, token, code
                    );
                }

                try rewards.getUserLastCheckpointIndex(SAMPLE_USER_FOR_QUERY, vId, token) returns (uint256 index) {
                    console2.log("  getUserLastCheckpointIndex(SAMPLE_USER, Val %s, Token %s): %s", vId, token, index);
                } catch Error(string memory reason) {
                    if (keccak256(bytes(reason)) == PROXY_ERROR_HASH) {
                        console2.log(
                            "getUserLastCheckpointIndex(SAMPLE_USER, Val %s, Token %s) FAILED: Proxy__ImplementationIsNotContract()",
                            vId,
                            token
                        );
                    } else {
                        console2.log(
                            "getUserLastCheckpointIndex(SAMPLE_USER, Val %s, Token %s) FAILED: %s", vId, token, reason
                        );
                    }
                } catch Panic(uint256 code) {
                    console2.log(
                        "getUserLastCheckpointIndex(SAMPLE_USER, Val %s, Token %s) PANICKED: %s", vId, token, code
                    );
                }

                try rewards.getPendingRewardForValidator(SAMPLE_USER_FOR_QUERY, vId, token) returns (uint256 pending) {
                    console2.log(
                        "  getPendingRewardForValidator(SAMPLE_USER, Val %s, Token %s): %s", vId, token, pending
                    );
                } catch Error(string memory reason) {
                    if (keccak256(bytes(reason)) == PROXY_ERROR_HASH) {
                        console2.log(
                            "getPendingRewardForValidator(SAMPLE_USER, Val %s, Token %s) FAILED: Proxy__ImplementationIsNotContract()",
                            vId,
                            token
                        );
                    } else {
                        console2.log(
                            "getPendingRewardForValidator(SAMPLE_USER, Val %s, Token %s) FAILED: %s", vId, token, reason
                        );
                    }
                } catch Panic(uint256 code) {
                    console2.log(
                        "getPendingRewardForValidator(SAMPLE_USER, Val %s, Token %s) PANICKED: %s", vId, token, code
                    );
                }
            }

            // User-Specific checks (not validator specific)
            try rewards.getClaimableReward(SAMPLE_USER_FOR_QUERY, token) returns (uint256 claimable) {
                console2.log("  getClaimableReward(SAMPLE_USER, Token %s): %s", token, claimable);
            } catch Error(string memory reason) {
                if (keccak256(bytes(reason)) == PROXY_ERROR_HASH) {
                    console2.log(
                        "getClaimableReward(SAMPLE_USER, Token %s) FAILED: Proxy__ImplementationIsNotContract()", token
                    );
                } else {
                    console2.log("getClaimableReward(SAMPLE_USER, Token %s) FAILED: %s", token, reason);
                }
            } catch Panic(uint256 code) {
                console2.log("getClaimableReward(SAMPLE_USER, Token %s) PANICKED: %s", token, code);
            }

            try rewards.earned(SAMPLE_USER_FOR_QUERY, token) returns (uint256 _earned) {
                console2.log("  earned(SAMPLE_USER, Token %s): %s", token, _earned);
            } catch Error(string memory reason) {
                if (keccak256(bytes(reason)) == PROXY_ERROR_HASH) {
                    console2.log("earned(SAMPLE_USER, Token %s) FAILED: Proxy__ImplementationIsNotContract()", token);
                } else {
                    console2.log("earned(SAMPLE_USER, Token %s) FAILED: %s", token, reason);
                }
            } catch Panic(uint256 code) {
                console2.log("earned(SAMPLE_USER, Token %s) PANICKED: %s", token, code);
            }
        }

        console2.log("\n--- Diamond State Query Complete ---");
    }

}
