// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Plume } from "../src/Plume.sol";
import { pUSDStaking } from "../src/pUSDStaking.sol";

import { pUSDStakingProxy } from "../src/proxy/pUSDStakingProxy.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Test } from "forge-std/Test.sol"; // Add Math import
import { console2 } from "forge-std/console2.sol";

contract pUSDStakingTest is Test {

    // Contracts
    pUSDStaking public staking;
    IERC20 public plume;
    IERC20 public pUSD;

    // Addresses from deployment script
    address public constant ADMIN = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;
    address public constant PLUME_TOKEN = 0x17F085f1437C54498f0085102AB33e7217C067C8;
    address public constant PUSD_TOKEN = 0xdddD73F5Df1F0DC31373357beAC77545dC5A6f3F;
    address public constant PUSDSTAKING_PROXY = 0x0630e14dABDb05Ca6d9A1Be40c6F996855e9c2cb;

    // Test addresses
    address public user1 = makeAddr("bob");
    address public user2 = makeAddr("alice");
    address public admin = makeAddr("admin");

    // Constants
    uint256 public constant MIN_STAKE = 1e18;
    uint256 public constant BASE = 1e18;
    uint256 public constant INITIAL_BALANCE = 1000e18;
    uint256 public constant PUSD_REWARD_RATE = 0; // ~5% APY
    uint256 public constant PLUME_REWARD_RATE = 1_587_301_587; // ~5% APY

    function setUp() public {
        string memory PLUME_RPC = vm.envOr("PLUME_RPC_URL", string(""));
        uint256 FORK_BLOCK = 372_419;

        vm.createSelectFork(vm.rpcUrl(PLUME_RPC), FORK_BLOCK);

        vm.startPrank(ADMIN);

        staking = pUSDStaking(PUSDSTAKING_PROXY);
        plume = IERC20(PLUME_TOKEN);
        pUSD = IERC20(PUSD_TOKEN);

        // Deal tokens to users
        deal(PUSD_TOKEN, user1, INITIAL_BALANCE);
        deal(PUSD_TOKEN, user2, INITIAL_BALANCE);
        deal(PLUME_TOKEN, address(staking), INITIAL_BALANCE);

        vm.stopPrank();
    }

    function testStaking() public {
        uint256 stakeAmount = 1e6;

        // Setup initial state
        vm.startPrank(user1);

        // Debug logs

        pUSD.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount);

        vm.stopPrank();
    }

    /*


    function testStaking() public {
        uint256 stakeAmount = 1e6;
        
        // Setup initial state
        vm.startPrank(user1);
        console2.log("Approving pUSD");
        pUSD.approve(address(staking), stakeAmount);
        console2.log("Approved pUSD");
        // Initial stake from wallet
        staking.stake(stakeAmount);
        console2.log("Staked pUSD");
        // Verify stake was successful
        assertEq(staking.amountStaked(), stakeAmount, "Incorrect staked amount");
        assertEq(staking.totalAmountStaked(), stakeAmount, "Incorrect total staked");
        assertEq(pUSD.balanceOf(address(staking)), stakeAmount, "Contract balance incorrect");
        
        // Unstake
        staking.unstake();
        
        // Verify unstake moved tokens to cooling
        assertEq(staking.amountStaked(), 0, "Should have no tokens staked");
        assertEq(staking.amountCooling(), stakeAmount, "Should have tokens cooling");
        assertEq(staking.totalAmountCooling(), stakeAmount, "Incorrect total cooling");
        
        // Try to stake again with cooling tokens
        staking.stake(stakeAmount);
        
        // Verify stake from cooling was successful
        assertEq(staking.amountStaked(), stakeAmount, "Incorrect staked amount after cooling");
        assertEq(staking.amountCooling(), 0, "Should have no tokens cooling");
        assertEq(staking.totalAmountCooling(), 0, "Incorrect total cooling");
        
        // Unstake again and wait for cooldown
        staking.unstake();
        vm.warp(block.timestamp + 7 days + 1);
        
        // Update totals to reflect cooldown completion
        vm.stopPrank();

        vm.startPrank(user1);
        
        // Verify tokens are now withdrawable
        assertEq(staking.amountWithdrawable(), stakeAmount, "Should have withdrawable tokens");
        //assertEq(staking.totalAmountWithdrawable(), stakeAmount, "Incorrect total withdrawable");
        
        // Withdraw tokens
        staking.withdraw(stakeAmount);
        
        // Verify final state
        assertEq(staking.amountStaked(), 0, "Should have no tokens staked");
        assertEq(staking.amountCooling(), 0, "Should have no tokens cooling");
        assertEq(staking.amountWithdrawable(), 0, "Should have no tokens withdrawable");
        assertEq(pUSD.balanceOf(user1), INITIAL_BALANCE, "Should have original balance");
        
        vm.stopPrank();
    }
    */

}
