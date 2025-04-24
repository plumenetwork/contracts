// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script, console2 } from "forge-std/Script.sol";

// --- Diamond Interfaces & Base Contract ---

import { IERC2535DiamondLoupe } from "@solidstate/interfaces/IERC2535DiamondLoupe.sol";
import { ISolidStateDiamond } from "@solidstate/proxy/diamond/ISolidStateDiamond.sol";

// --- Facet Interfaces (or full contracts for easy casting) ---
// Adjust import paths if necessary
import { AccessControlFacet } from "../../src/facets/AccessControlFacet.sol";
import { ManagementFacet } from "../../src/facets/ManagementFacet.sol";

import { RewardsFacet } from "../../src/facets/RewardsFacet.sol";
import { StakingFacet } from "../../src/facets/StakingFacet.sol";
import { ValidatorFacet } from "../../src/facets/ValidatorFacet.sol";

// --- Libs & Structs ---

import { PlumeRoles } from "../../src/lib/PlumeRoles.sol";
import { PlumeStakingStorage } from "../../src/lib/PlumeStakingStorage.sol";

// --- Standard Contracts ---
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ForkTestPlumeStaking
 * @notice A script to debug the deployed PlumeStaking diamond by forking mainnet.
 * @dev Run this script against a mainnet fork using:
 *      forge script p/script/debug/ForkTestPlumeStaking.s.sol:ForkTestPlumeStaking --fork-url <your_mainnet_rpc_url>
 * -vvv
 *      (You might need to add --sender <your_address> --private-key <your_pk> if needed for setup, but often not
 * required for read calls)
 */
contract ForkTestPlumeStaking is Script {

    // --- Mainnet Configuration ---
    // !!! IMPORTANT: Replace with your ACTUAL mainnet RPC URL !!!
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL"); // Or hardcode if preferred

    address constant DIAMOND_PROXY_ADDRESS = 0xA20bfe49969D4a0E9abfdb6a46FeD777304ba07f;
    address constant KNOWN_ADMIN = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5; // If needed for pranking write calls

    // Add addresses for any relevant mainnet tokens you want to interact with
    address constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    // address constant MAINNET_PUSD_ADDRESS = 0x...; // Replace with actual mainnet PUSD if applicable

    // --- Facet Instances ---
    RewardsFacet rewardsFacet;
    StakingFacet stakingFacet;
    ValidatorFacet validatorFacet;
    ManagementFacet managementFacet;
    AccessControlFacet accessControlFacet;
    IERC2535DiamondLoupe loupe;

    // Pre-calculate error hashes if needed
    bytes32 constant PROXY_ERROR_HASH = keccak256(bytes("Proxy__ImplementationIsNotContract()"));

    function setUp() public {
        console2.log("Setting up mainnet fork...");
        uint256 forkBlock = block.number; // Fork from the latest block by default
        // Alternatively, specify a block number for consistency:
        // uint256 forkBlock = vm.envUint("FORK_BLOCK_NUMBER"); // Example: set FORK_BLOCK_NUMBER in .env
        vm.createSelectFork(MAINNET_RPC_URL, forkBlock);
        console2.log("Fork created at block:", block.number);

        // Get instances by casting the deployed diamond address
        rewardsFacet = RewardsFacet(DIAMOND_PROXY_ADDRESS);
        stakingFacet = StakingFacet(DIAMOND_PROXY_ADDRESS);
        validatorFacet = ValidatorFacet(DIAMOND_PROXY_ADDRESS);
        managementFacet = ManagementFacet(DIAMOND_PROXY_ADDRESS);
        accessControlFacet = AccessControlFacet(DIAMOND_PROXY_ADDRESS);
        loupe = IERC2535DiamondLoupe(DIAMOND_PROXY_ADDRESS);

        console2.log("Diamond Proxy Address:", DIAMOND_PROXY_ADDRESS);
    }

    function run() external {
        console2.log("\n--- Running Fork Tests ---");

        // --- Test Case 1: Check getRewardRate ---
        test_getRewardRate();

        // --- Test Case 2: Check earned ---
        test_earned();

        // --- Test Case 3: Check other potentially problematic selectors ---
        test_otherSelectors();

        // --- Test Case 4: Check Loupe information ---
        test_diamondLoupe();

        console2.log("\n--- Fork Tests Complete ---");
    }

    // --- Individual Test Functions ---

    function test_getRewardRate() public {
        console2.log("\nTesting getRewardRate(address)... (Expected Selector: 0x24c60e50)");
        // Use a known reward token address on mainnet (e.g., NATIVE_TOKEN or PUSD if registered)
        address tokenToCheck = NATIVE_TOKEN;
        console2.log("  Token: %s", tokenToCheck);

        try rewardsFacet.getRewardRate(tokenToCheck) returns (uint256 rate) {
            console2.log("  SUCCESS: getRewardRate(%s) returned: %d", tokenToCheck, rate);
        } catch Error(string memory reason) {
            bytes32 reasonHash = keccak256(bytes(reason));
            if (reasonHash == PROXY_ERROR_HASH) {
                console2.log(
                    "  FAILURE: getRewardRate(%s) FAILED with Proxy__ImplementationIsNotContract()", tokenToCheck
                );
            } else {
                console2.log("  FAILURE: getRewardRate(%s) FAILED with reason: %s", tokenToCheck, reason);
            }
        } catch Panic(uint256 code) {
            console2.log("  FAILURE: getRewardRate(%s) PANICKED with code: %d", tokenToCheck, code);
        }
    }

    function test_earned() public {
        console2.log("\nTesting earned(address,address)... (Expected Selector: 0x87c9fc34)");
        // Use a sample user address and a known reward token
        address userToCheck = address(0x1); // Or a known staker address on mainnet
        address tokenToCheck = NATIVE_TOKEN;
        console2.log("  User: %s", userToCheck);
        console2.log("  Token: %s", tokenToCheck);

        try rewardsFacet.earned(userToCheck, tokenToCheck) returns (uint256 amount) {
            console2.log("  SUCCESS: earned(%s, %s) returned: %d", userToCheck, tokenToCheck, amount);
        } catch Error(string memory reason) {
            bytes32 reasonHash = keccak256(bytes(reason));
            if (reasonHash == PROXY_ERROR_HASH) {
                console2.log(
                    "  FAILURE: earned(%s, %s) FAILED with Proxy__ImplementationIsNotContract()",
                    userToCheck,
                    tokenToCheck
                );
            } else {
                console2.log("  FAILURE: earned(%s, %s) FAILED with reason: %s", userToCheck, tokenToCheck, reason);
            }
        } catch Panic(uint256 code) {
            console2.log("  FAILURE: earned(%s, %s) PANICKED with code: %d", userToCheck, tokenToCheck, code);
        }
    }

    function test_otherSelectors() public {
        console2.log("\nTesting other potentially problematic selectors...");
        // Add try/catch blocks for other functions identified from QueryDiamondState logs
        // Example:
        address userToCheck = address(0x1);
        uint16 validatorIdToCheck = 1; // Use a known validator ID

        try stakingFacet.stakeInfo(userToCheck) returns (PlumeStakingStorage.StakeInfo memory info) {
            console2.log("  SUCCESS: stakeInfo(%s) returned.", userToCheck);
            // Optionally log fields: console2.log("    - staked: %d", info.staked);
        } catch Error(string memory reason) {
            if (keccak256(bytes(reason)) == PROXY_ERROR_HASH) {
                console2.log("  FAILURE: stakeInfo(%s) FAILED with Proxy__ImplementationIsNotContract()", userToCheck);
            } else {
                console2.log("  FAILURE: stakeInfo(%s) FAILED with reason: %s", userToCheck, reason);
            }
        } catch Panic(uint256 code) {
            console2.log("  FAILURE: stakeInfo(%s) PANICKED with code: %d", userToCheck, code);
        }

        try validatorFacet.getValidatorInfo(validatorIdToCheck) returns (
            PlumeStakingStorage.ValidatorInfo memory info, uint256 totalStaked, uint256 stakerCount
        ) {
            console2.log("  SUCCESS: getValidatorInfo(%d) returned.", validatorIdToCheck);
        } catch Error(string memory reason) {
            if (keccak256(bytes(reason)) == PROXY_ERROR_HASH) {
                console2.log(
                    "  FAILURE: getValidatorInfo(%d) FAILED with Proxy__ImplementationIsNotContract()",
                    validatorIdToCheck
                );
            } else {
                console2.log("  FAILURE: getValidatorInfo(%d) FAILED with reason: %s", validatorIdToCheck, reason);
            }
        } catch Panic(uint256 code) {
            console2.log("  FAILURE: getValidatorInfo(%d) PANICKED with code: %d", validatorIdToCheck, code);
        }

        // Add more calls here for functions like totalAmountStaked, getActiveValidatorCount, etc.
    }

    function test_diamondLoupe() public {
        console2.log("\nTesting Diamond Loupe functions...");

        bytes4 selectorToCheck = bytes4(keccak256("getRewardRate(address)")); // 0x24c60e50
        bytes4 selectorToCheck2 = bytes4(keccak256("earned(address,address)")); // 0x87c9fc34
        bytes4 selectorToCheck3 = 0xea7cbff1; // The one you mentioned

        address facetAddr;
        try loupe.facetAddress(selectorToCheck) returns (address addr) {
            facetAddr = addr;
            console2.log(
                "  SUCCESS: facetAddress(%s - getRewardRate) returned: %s", vm.toString(selectorToCheck), facetAddr
            );
        } catch Error(string memory reason) {
            console2.log(
                "  FAILURE: facetAddress(%s - getRewardRate) FAILED with reason: %s",
                vm.toString(selectorToCheck),
                reason
            );
        } catch Panic(uint256 code) {
            console2.log(
                "  FAILURE: facetAddress(%s - getRewardRate) PANICKED with code: %d", vm.toString(selectorToCheck), code
            );
        }

        try loupe.facetAddress(selectorToCheck2) returns (address addr) {
            facetAddr = addr;
            console2.log("  SUCCESS: facetAddress(%s - earned) returned: %s", vm.toString(selectorToCheck2), facetAddr);
        } catch Error(string memory reason) {
            console2.log(
                "  FAILURE: facetAddress(%s - earned) FAILED with reason: %s", vm.toString(selectorToCheck2), reason
            );
        } catch Panic(uint256 code) {
            console2.log(
                "  FAILURE: facetAddress(%s - earned) PANICKED with code: %d", vm.toString(selectorToCheck2), code
            );
        }

        try loupe.facetAddress(selectorToCheck3) returns (address addr) {
            facetAddr = addr;
            console2.log(
                "  SUCCESS: facetAddress(%s - 0xea7cbff1) returned: %s", vm.toString(selectorToCheck3), facetAddr
            );
        } catch Error(string memory reason) {
            console2.log(
                "  FAILURE: facetAddress(%s - 0xea7cbff1) FAILED with reason: %s", vm.toString(selectorToCheck3), reason
            );
        } catch Panic(uint256 code) {
            console2.log(
                "  FAILURE: facetAddress(%s - 0xea7cbff1) PANICKED with code: %d", vm.toString(selectorToCheck3), code
            );
        }

        // Optionally, get all facets and their selectors
        try loupe.facets() returns (IERC2535DiamondLoupe.Facet[] memory _facets) {
            console2.log("  Facets (%d):", _facets.length);
            for (uint256 i = 0; i < _facets.length; i++) {
                console2.log("    - Facet Address: %s", _facets[i].target);
                console2.log("      Selectors (%d):", _facets[i].selectors.length);
                // Optionally log selectors, but can be very verbose
                // for(uint j=0; j < _facets[i].selectors.length; j++) {
                //      console2.log("        %s", vm.toString(_facets[i].selectors[j]));
                // }
            }
        } catch Error(string memory reason) {
            console2.log("  FAILURE: facets() FAILED with reason: %s", reason);
        } catch Panic(uint256 code) {
            console2.log("  FAILURE: facets() PANICKED with code: %d", code);
        }
    }

}
