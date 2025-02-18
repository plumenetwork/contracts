// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Plume } from "../src/Plume.sol";
import { PlumeStaking } from "../src/PlumeStaking.sol";

import { PlumeStakingProxy } from "../src/proxy/PlumeStakingProxy.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Test } from "forge-std/Test.sol";

contract PlumeStakingTest is Test {

    // Contracts
    PlumeStaking public staking;
    Plume public plume;
    IERC20 public pUSD;

    // Addresses from deployment script
    address public constant ADMIN = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;
    address public constant PLUME_TOKEN = 0x17F085f1437C54498f0085102AB33e7217C067C8;
    address public constant PUSD_TOKEN = 0xdddD73F5Df1F0DC31373357beAC77545dC5A6f3F;
    address public constant PLUMESTAKING_PROXY = 0x632c5513fb6715789efdb0d61b960cA1706d9E45;

    // Test addresses
    address public user1 = makeAddr("bob");
    address public user2 = makeAddr("alice");

    // Constants
    uint256 public constant MIN_STAKE = 1e18;
    uint256 public constant BASE = 1e18;
    uint256 public constant INITIAL_BALANCE = 1000e18;
    uint256 public constant PUSD_REWARD_RATE = 1_587_301_587; // ~5% APY
    uint256 public constant PLUME_REWARD_RATE = 0; // ~5% APY

    function setUp() public {
        //vm.skip(true);

        // Fork mainnet
        string memory PLUME_RPC = vm.envOr("PLUME_RPC_URL", string(""));
        vm.createSelectFork(vm.rpcUrl(PLUME_RPC));

        vm.startPrank(ADMIN);

        // Deploy implementation and proxy
        PlumeStaking implementation = new PlumeStaking();

        bytes memory initData = abi.encodeCall(PlumeStaking.initialize, (ADMIN, PLUME_TOKEN, PUSD_TOKEN));

        ERC1967Proxy proxy = new PlumeStakingProxy(address(implementation), initData);

        // Setup contract interfaces
        staking = PlumeStaking(address(proxy));
        plume = Plume(PLUME_TOKEN);
        pUSD = IERC20(PUSD_TOKEN);

        // Setup reward tokens
        staking.addRewardToken(PUSD_TOKEN);
        staking.addRewardToken(PLUME_TOKEN);

        address[] memory tokens = new address[](2);
        uint256[] memory rates = new uint256[](2);

        tokens[0] = PUSD_TOKEN;
        tokens[1] = PLUME_TOKEN;
        rates[0] = PUSD_REWARD_RATE;
        rates[1] = PLUME_REWARD_RATE;

        staking.setRewardRates(tokens, rates);
        // Instead of minting, transfer tokens from a whale or use deal
        deal(PLUME_TOKEN, user1, INITIAL_BALANCE);
        deal(PLUME_TOKEN, user2, INITIAL_BALANCE);
        deal(PLUME_TOKEN, address(staking), INITIAL_BALANCE);

        vm.stopPrank();
    }

    function testInitialState() public {
        //vm.skip(true);

        assertEq(address(staking.plume()), PLUME_TOKEN);
        assertEq(staking.minStakeAmount(), MIN_STAKE);
        assertEq(staking.cooldownInterval(), 7 days);
        assertTrue(staking.hasRole(staking.DEFAULT_ADMIN_ROLE(), ADMIN));
        assertTrue(staking.hasRole(staking.ADMIN_ROLE(), ADMIN));
        assertTrue(staking.hasRole(staking.UPGRADER_ROLE(), ADMIN));
    }

    function testUnstakeAndCooldown() public {
        uint256 amount = 100e18;

        vm.startPrank(user1);
        plume.approve(address(staking), amount);
        staking.stake(amount);

        vm.expectEmit(true, false, false, true);
        emit PlumeStaking.Unstaked(user1, amount);

        staking.unstake();

        PlumeStaking.StakeInfo memory info = staking.stakeInfo(user1);
        assertEq(info.staked, 0);
        assertEq(info.cooled, amount);
        assertEq(info.cooldownEnd, block.timestamp + 7 days);
        vm.stopPrank();
    }

    function testRewardAccrual() public {
        uint256 amount = 100e18;

        vm.startPrank(user1);
        plume.approve(address(staking), amount); // This will use the proxy address
        staking.stake(amount);

        // Move forward in time
        vm.warp(block.timestamp + 1 days);

        uint256 expectedReward = (amount * 1 days * PUSD_REWARD_RATE) / BASE;
        assertEq(staking.getClaimableReward(user1, PUSD_TOKEN), expectedReward);

        // Test claim
        vm.expectEmit(true, true, false, true);
        emit PlumeStaking.ClaimedRewards(user1, PUSD_TOKEN, expectedReward);

        staking.claim();
        assertEq(pUSD.balanceOf(user1), expectedReward);
        vm.stopPrank();
    }

    function testMultipleUsersStaking() public {
        uint256 amount1 = 100e18;
        uint256 amount2 = 200e18;

        // User 1 stakes
        vm.startPrank(user1);
        plume.approve(address(staking), amount1);
        staking.stake(amount1);
        vm.stopPrank();

        // User 2 stakes
        vm.startPrank(user2);
        plume.approve(address(staking), amount2);
        staking.stake(amount2);
        vm.stopPrank();

        // Move forward in time
        vm.warp(block.timestamp + 1 days);

        // Check rewards
        uint256 expectedReward1 = (amount1 * 1 days * PUSD_REWARD_RATE) / BASE;
        uint256 expectedReward2 = (amount2 * 1 days * PUSD_REWARD_RATE) / BASE;

        assertEq(staking.getClaimableReward(user1, PUSD_TOKEN), expectedReward1);
        assertEq(staking.getClaimableReward(user2, PUSD_TOKEN), expectedReward2);
    }

    function testRevertInvalidAmount() public {
        vm.startPrank(user1);
        plume.approve(address(staking), MIN_STAKE - 1);

        vm.expectRevert(abi.encodeWithSelector(PlumeStaking.InvalidAmount.selector, MIN_STAKE - 1, MIN_STAKE));
        staking.stake(MIN_STAKE - 1);
        vm.stopPrank();
    }
    /*
    function testAdminFunctions() public {
        vm.startPrank(ADMIN);

        // Test setMinStakeAmount
        uint256 newMinStake = 2e18;
        staking.setMinStakeAmount(newMinStake);
        assertEq(staking.minStakeAmount(), newMinStake);

        // Test setCooldownInterval
        uint256 newCooldown = 14 days;
        staking.setCooldownInterval(newCooldown);
        assertEq(staking.cooldownInterval(), newCooldown);

        // Test setRewardRate
        uint256 newRate = 5e17;
        staking.setRewardRate(PUSD_TOKEN, newRate);
        assertEq(staking.rewardRate(PUSD_TOKEN), newRate);

        vm.stopPrank();
    }
    */

}
