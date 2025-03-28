// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Plume } from "../src/Plume.sol";
import { PlumeStaking } from "../src/PlumeStaking.sol";

import { PlumeStakingStorage } from "../src/lib/PlumeStakingStorage.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

/**
 * @title PlumeStakingForkTest
 * @notice Test contract that tests the PlumeStaking contract in a forked environment
 * @dev This test uses the existing deployed contract at 0x42Ffc8306c022Dd17f09daD0FF71f7313Df0A48D
 */
contract PlumeStakingForkTest is Test {

    // Contracts
    PlumeStaking public staking;

    // Addresses from deployment script
    address public constant ADMIN = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;
    address public constant PLUME_TOKEN = 0x17F085f1437C54498f0085102AB33e7217C067C8;
    address public constant PUSD_TOKEN = 0xdddD73F5Df1F0DC31373357beAC77545dC5A6f3F;
    address public constant PLUMESTAKING_PROXY = 0x42Ffc8306c022Dd17f09daD0FF71f7313Df0A48D;
    // Special address representing native PLUME token in the contract
    address public constant PLUME_NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // Test addresses
    address public user1;
    address public user2;

    // Constants
    uint256 public constant INITIAL_BALANCE = 1000e18;

    function setUp() public {
        // Debug fork connection
        console2.log("Forking network...");
        string memory rpcUrl = vm.envString("PLUME_DEVNET_RPC_URL");
        console2.log("RPC URL:", rpcUrl);

        // Create fork with explicit block number if needed
        // If revert occurs, try with a specific block number
        vm.createSelectFork(rpcUrl);
        console2.log("Fork created at block:", block.number);

        // Connect to the existing proxy contract
        staking = PlumeStaking(payable(PLUMESTAKING_PROXY));
        console2.log("Connected to PlumeStaking at:", address(staking));

        // Setup test accounts
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Give test accounts ETH and tokens
        vm.deal(user1, INITIAL_BALANCE);
        vm.deal(user2, INITIAL_BALANCE);

        // Fund users with PLUME tokens if needed
        // This depends on if your contract accepts native tokens or ERC20 PLUME
        // Uncomment if using ERC20 PLUME
        /*
        vm.startPrank(ADMIN);
        Plume plume = Plume(PLUME_TOKEN);
        uint256 mintAmount = 1000e18;
        if (plume.balanceOf(user1) < mintAmount) {
            plume.mint(user1, mintAmount);
        }
        if (plume.balanceOf(user2) < mintAmount) {
            plume.mint(user2, mintAmount);
        }
        vm.stopPrank();
        */
    }

    function testInitialState() public {
        console2.log("Starting testInitialState...");

        // Just verify that we can call view functions
        uint256 minStake = staking.getMinStakeAmount();
        uint256 cooldownInterval = staking.cooldownInterval();

        console2.log("Min stake amount:", minStake);
        console2.log("Cooldown interval:", cooldownInterval);

        // Only verify facts we're confident about
        assertGt(minStake, 0, "Min stake should be > 0");
        assertGt(cooldownInterval, 0, "Cooldown should be > 0");
    }

    function testStakeAndUnstake() public {
        // Get initial state
        (uint256 initialStaked,,,,) = staking.stakingInfo();
        uint256 initialBalance = address(user1).balance;
        uint256 stakeAmount = 100e18;

        // Stake tokens
        vm.startPrank(user1);
        staking.stake{ value: stakeAmount }();
        vm.stopPrank();

        // Check final state
        (uint256 finalStaked,,,,) = staking.stakingInfo();
        uint256 finalBalance = address(user1).balance;

        // Verify state changes
        assertEq(finalStaked, initialStaked + stakeAmount, "Total staked amount incorrect");
        assertEq(finalBalance, initialBalance - stakeAmount, "User balance not reduced correctly");

        // Get stake info
        PlumeStakingStorage.StakeInfo memory info = staking.stakeInfo(user1);
        assertEq(info.staked, stakeAmount, "User staked amount incorrect");
    }

    function testStakeAndUnstakeWithCooldown() public {
        uint256 stakeAmount = 100e18;

        // Get initial state
        (uint256 initialStaked,,,,) = staking.stakingInfo();

        // Stake tokens
        vm.startPrank(user1);
        staking.stake{ value: stakeAmount }();

        // Verify stake
        (uint256 afterStakeTotal,,,,) = staking.stakingInfo();
        assertEq(afterStakeTotal, initialStaked + stakeAmount, "Total staked amount incorrect after stake");

        // Unstake
        staking.unstake();

        // Verify unstake
        (uint256 afterUnstakeTotal, uint256 totalCooling,,,) = staking.stakingInfo();
        assertEq(afterUnstakeTotal, initialStaked, "Total staked amount incorrect after unstake");
        assertEq(totalCooling, stakeAmount, "Cooling amount incorrect");

        vm.stopPrank();
    }

    function testMultipleUsers() public {
        uint256 amount1 = 100e18;
        uint256 amount2 = 200e18;

        // Get initial state
        (uint256 initialStaked,,,,) = staking.stakingInfo();

        // User 1 stakes
        vm.startPrank(user1);
        staking.stake{ value: amount1 }();
        vm.stopPrank();

        // Verify after first stake
        (uint256 afterFirstStake,,,,) = staking.stakingInfo();
        assertEq(afterFirstStake, initialStaked + amount1, "Total staked amount incorrect after first stake");

        // User 2 stakes
        vm.startPrank(user2);
        staking.stake{ value: amount2 }();
        vm.stopPrank();

        // Verify after second stake
        (uint256 afterSecondStake,,,,) = staking.stakingInfo();
        assertEq(
            afterSecondStake, initialStaked + amount1 + amount2, "Total staked amount incorrect after second stake"
        );

        // Check individual balances
        PlumeStakingStorage.StakeInfo memory info1 = staking.stakeInfo(user1);
        PlumeStakingStorage.StakeInfo memory info2 = staking.stakeInfo(user2);
        assertEq(info1.staked, amount1, "User 1 staked amount incorrect");
        assertEq(info2.staked, amount2, "User 2 staked amount incorrect");
    }

    function testViewFunctions() public {
        console2.log("Starting testViewFunctions...");

        // Just test basic view functions
        (address[] memory tokens, uint256[] memory rates) = staking.getRewardTokens();

        console2.log("Number of reward tokens:", tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            console2.log("Token:", tokens[i], "Rate:", rates[i]);
        }

        assertGt(tokens.length, 0, "Should have at least one reward token");
    }

}
