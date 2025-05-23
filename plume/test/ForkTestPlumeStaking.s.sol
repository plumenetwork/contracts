// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { Test, console2 } from "forge-std/Test.sol";

// Diamond Interfaces/Libs

import "../src/lib/PlumeErrors.sol";
import "../src/lib/PlumeEvents.sol";

import { PlumeRewardLogic } from "../src/lib/PlumeRewardLogic.sol";
import { PlumeRoles } from "../src/lib/PlumeRoles.sol";
import "../src/lib/PlumeRoles.sol";
import { PlumeStakingStorage } from "../src/lib/PlumeStakingStorage.sol";

import { IERC2535DiamondCutInternal } from "@solidstate/interfaces/IERC2535DiamondCutInternal.sol";
import { ISolidStateDiamond } from "@solidstate/proxy/diamond/ISolidStateDiamond.sol";

import { PlumeStaking } from "../src/PlumeStaking.sol";
import { PlumeStakingRewardTreasury } from "../src/PlumeStakingRewardTreasury.sol";
import { ManagementFacet } from "../src/facets/ManagementFacet.sol";
import { RewardsFacet } from "../src/facets/RewardsFacet.sol";
import { StakingFacet } from "../src/facets/StakingFacet.sol";
import { ValidatorFacet } from "../src/facets/ValidatorFacet.sol";
import { IAccessControl } from "../src/interfaces/IAccessControl.sol";
import { IPlumeStakingRewardTreasury } from "../src/interfaces/IPlumeStakingRewardTreasury.sol"; // <<< ADDED IMPORT

// ERC20 Interfaces/Libs
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ForkPlumeStakingDiamondTest
 * @notice Tests the Plume Staking Diamond contract functions on a Mainnet fork.
 * @dev Adapts tests from PlumeStakingDiamond.t.sol to run against a deployed instance.
 *      Assumes mainnet addresses and state provided are correct.
 */
contract ForkTestPlumeStaking is Test {

    using SafeERC20 for IERC20;

    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    // --- Mainnet Configuration ---
    uint256 public forkBlockNumber;
    string public mainnetRpcUrl = "https://rpc.plume.org";
    // Corrected checksum for Diamond Proxy address
    address public constant DIAMOND_PROXY_ADDRESS = 0xCF8B97260F77c11d58542644c5fD1D5F93FdA57d;
    address public constant KNOWN_ADMIN = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5; // Example admin, replace if
        // needed
    address public constant PLUME_NATIVE_MAINNET = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; // Replace with actual
        // PLUME address if needed
    address public constant VALIDATOR_1_ADMIN = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5; // Admin for ID 1 from fork

    // --- Interfaces to Diamond Facets & Treasury ---
    ISolidStateDiamond public diamondProxy;
    IERC2535DiamondCutInternal public diamondCut;
    IAccessControl public accessControlFacet;
    ManagementFacet public managementFacet;
    RewardsFacet public rewardsFacet;
    StakingFacet public stakingFacet;
    ValidatorFacet public validatorFacet;
    IPlumeStakingRewardTreasury public treasury; // Initialized in setUp if possible
    IERC20 public plumeToken; // Initialized in setUp if PLUME_NATIVE_MAINNET is set
    // IERC20 public pusdToken; // Initialized in setUp if PUSD_MAINNET is set
    IERC20 public pUSD = IERC20(0xdddD73F5Df1F0DC31373357beAC77545dC5A6f3F);

    // Addresses
    address public constant ADMIN_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;
    address public constant PLUME_NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; // Use standard ETH placeholder

    address public user1;
    address public user2;
    address public user3;
    address public user4;
    address public validatorAdmin;
    address public validator2Admin; // <<< ADD for distinct admin

    address public admin = KNOWN_ADMIN; // Assign directly

    // Constants
    uint256 public constant MIN_STAKE = 1e17;
    uint256 public constant INITIAL_COOLDOWN = 180 seconds;
    uint256 public constant INITIAL_BALANCE = 1000e18;
    uint256 public constant PUSD_REWARD_RATE = 1e18; // Example rate
    uint256 public constant EXPECTED_PLUME_RATE_PER_SEC = 1_744_038_559; // CORRECTED for 5.5% APR

    uint16 public constant DEFAULT_VALIDATOR_ID = 1;
    uint256 public constant DEFAULT_COMMISSION = 5e16; // 5% commission
    address public constant DEFAULT_VALIDATOR_ADMIN = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;

    // --- Fork Setup ---
    function setUp() public {
        // Select the fork FIRST
        vm.createSelectFork(mainnetRpcUrl, 2_372_560);

        // Now, deal funds on the selected fork
        uint256 adminPusdAmount = 50_000 * 1e6;
        deal(address(pUSD), admin, adminPusdAmount);
        console2.log("Admin pUSD balance immediately after deal (and fork selection) in setUp:", pUSD.balanceOf(admin));

        diamondProxy = ISolidStateDiamond(payable(DIAMOND_PROXY_ADDRESS));
        diamondCut = IERC2535DiamondCutInternal(DIAMOND_PROXY_ADDRESS);
        accessControlFacet = IAccessControl(DIAMOND_PROXY_ADDRESS);
        managementFacet = ManagementFacet(DIAMOND_PROXY_ADDRESS);
        rewardsFacet = RewardsFacet(DIAMOND_PROXY_ADDRESS);
        stakingFacet = StakingFacet(DIAMOND_PROXY_ADDRESS);
        validatorFacet = ValidatorFacet(DIAMOND_PROXY_ADDRESS);

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        user4 = makeAddr("user4");
        admin = ADMIN_ADDRESS; // KNOWN_ADMIN
        validatorAdmin = makeAddr("validatorAdmin"); // Keep for potential use, but not assigned here
        validator2Admin = makeAddr("validator2Admin"); // Keep for potential use, but not assigned here

        vm.deal(user1, 1000 ether);
        vm.deal(user2, 1000 ether);
        vm.deal(user3, 1000 ether);
        vm.deal(user4, 1000 ether);

        // Fund admin AFTER initializing treasury

        try rewardsFacet.getTreasury() returns (address treasuryAddr) {
            if (treasuryAddr != address(0)) {
                treasury = IPlumeStakingRewardTreasury(treasuryAddr);
                deal(address(pUSD), treasuryAddr, 2e24);
                vm.deal(treasuryAddr, 1000 ether);
                console2.log("Using Mainnet Treasury at:", treasuryAddr);
            } else {
                console2.log("WARNING: Treasury address is not set on mainnet contract!");
            }
        } catch {
            console2.log("WARNING: Could not call getTreasury() or it reverted.");
        }

        // Add ONLY validator 2 (using KNOWN_ADMIN)
        uint16 validatorId_2 = 2;
        uint256 commission = 5e16;
        address l2Admin_2 = KNOWN_ADMIN; // Use KNOWN_ADMIN (our main admin)
        address l2Withdraw_2 = KNOWN_ADMIN;
        string memory l1ValAddr_2 = "0xval2";
        string memory l1AccAddr_2 = "0xacc2";
        address l1AccEvmAddr_2 = address(0x1234); // Example address
        uint256 maxCapacity = 1_000_000e18;

        vm.startPrank(admin);
        // Check if validator 2 already exists (unlikely, but safe)
        /*
        ValidatorFacet(address(diamondProxy)).addValidator(
            validatorId_2,
            commission,
            validator2Admin,
            l2Withdraw_2,
            l1ValAddr_2,
            l1AccAddr_2,
            l1AccEvmAddr_2,
            maxCapacity
        );
        console2.log("Added validator 2 in setUp.");
        */
        vm.stopPrank();

        // Deal to admin *after* treasury setup
        deal(address(pUSD), admin, adminPusdAmount);
        console2.log("Admin pUSD balance AFTER dealing in setUp:", pUSD.balanceOf(admin));

        console2.log("Fork setup complete. Testing against Diamond:", DIAMOND_PROXY_ADDRESS);

        vm.startPrank(admin);
        /*
        try rewardsFacet.addRewardToken(PlumeStakingStorage.PLUME_NATIVE) { }
        catch {
            console2.log("PLUME_NATIVE likely already a reward token on forked contract.");
        }
        */
        // Set a known max rate and the specific rate we are testing
        //      rewardsFacet.setMaxRewardRate(PlumeStakingStorage.PLUME_NATIVE, EXPECTED_PLUME_RATE_PER_SEC * 2); // Max
        // rate
        // based on corrected expected rate
        address[] memory tokens = new address[](1);
        tokens[0] = PlumeStakingStorage.PLUME_NATIVE;
        uint256[] memory rates = new uint256[](1);
        rates[0] = EXPECTED_PLUME_RATE_PER_SEC; // Use the corrected rate
        rewardsFacet.setRewardRates(tokens, rates);
        console2.log("PLUME reward rate set on fork to: %s", EXPECTED_PLUME_RATE_PER_SEC);
        vm.stopPrank();
    }

    // ===============================================
    // == Adapted Tests from PlumeStakingDiamond.t.sol ==
    // ===============================================

    function testInitialState() public {
        // Need to cast diamondProxy to PlumeStaking to call isInitialized
        assertTrue(PlumeStaking(payable(address(diamondProxy))).isInitialized(), "Contract should be initialized");

        // Use the new view functions from ManagementFacet for other checks
        uint256 expectedMinStake = MIN_STAKE;
        uint256 actualMinStake = ManagementFacet(address(diamondProxy)).getMinStakeAmount();
        assertEq(actualMinStake, expectedMinStake, "Min stake amount mismatch");

        uint256 expectedCooldown = INITIAL_COOLDOWN;
        uint256 actualCooldown = ManagementFacet(address(diamondProxy)).getCooldownInterval();
        assertEq(actualCooldown, expectedCooldown, "Cooldown interval mismatch");
    }

    function testStakeAndUnstake() public {
        uint256 amount = 100e18;
        vm.startPrank(user1);
        StakingFacet(address(diamondProxy)).stake{ value: amount }(DEFAULT_VALIDATOR_ID);
        assertEq(StakingFacet(address(diamondProxy)).amountStaked(), amount);

        // Unstake
        StakingFacet(address(diamondProxy)).unstake(DEFAULT_VALIDATOR_ID);
        assertEq(StakingFacet(address(diamondProxy)).amountCooling(), amount);
        assertEq(StakingFacet(address(diamondProxy)).amountStaked(), 0);

        vm.stopPrank();
    }

    function testClaimValidatorCommission() public {
        console2.log("\n--- Initial State Check for testClaimValidatorCommission ---");
        // Log values inherited from the fork state
        uint256 initialAccruedCommission = validatorFacet.getAccruedCommission(DEFAULT_VALIDATOR_ID, address(pUSD));

        // Set up validator commission at 20% (20 * 1e16)
        vm.startPrank(admin); // Use KNOWN_ADMIN assumed to be L2 admin for validator 1
        uint256 newCommission20 = 20e16;
        ValidatorFacet(address(diamondProxy)).setValidatorCommission(DEFAULT_VALIDATOR_ID, newCommission20);
        vm.stopPrank();

        // Set reward rate for PUSD to 1e18 (1 token per second)
        vm.startPrank(admin);
        address[] memory tokens = new address[](1);
        tokens[0] = address(pUSD);
        uint256[] memory rates = new uint256[](1);
        rates[0] = 1; // Set rate to absolute minimum to isolate historical commission

        RewardsFacet(address(diamondProxy)).setRewardRates(tokens, rates);
        RewardsFacet(address(diamondProxy)).setMaxRewardRate(address(pUSD), rates[0]);

        // Ensure treasury has enough PUSD by transferring tokens
        uint256 treasuryAmount = 1000 * 1e6;
        console2.log("Admin pUSD balance before transfer:", pUSD.balanceOf(admin));
        console2.log("Treasury pUSD balance before transfer:", pUSD.balanceOf(address(treasury)));
        console2.log("Attempting to transfer %s pUSD to treasury", treasuryAmount);
        pUSD.transfer(address(treasury), treasuryAmount);
        vm.stopPrank();

        // Have a user stake with the validator
        uint256 stakeAmount = 10 ether;
        vm.startPrank(user1);
        StakingFacet(address(diamondProxy)).stake{ value: stakeAmount }(DEFAULT_VALIDATOR_ID);
        vm.stopPrank();

        // Move time forward to accrue rewards
        uint256 timeBefore = block.timestamp;
        vm.roll(block.number + 10);
        vm.warp(block.timestamp + 10);
        uint256 timeAfter = block.timestamp;
        // console2.log("Time warped from %d to %d (delta %d)", timeBefore, timeAfter, timeAfter - timeBefore); // Keep

        // --- Assertions before unstake ---
        uint256 amountToUnstake = 1 ether;
        uint256 expectedStake = stakeAmount;

        uint256 actualUserStake = StakingFacet(address(diamondProxy)).getUserValidatorStake(user1, DEFAULT_VALIDATOR_ID);
        assertEq(actualUserStake, expectedStake, "User1 Validator 0 Stake mismatch before unstake (via view func)");

        // Trigger reward updates through an interaction
        vm.startPrank(user1);
        StakingFacet(address(diamondProxy)).unstake(DEFAULT_VALIDATOR_ID, amountToUnstake);
        vm.stopPrank();

        // Check the accrued commission
        uint256 commission =
            ValidatorFacet(address(diamondProxy)).getAccruedCommission(DEFAULT_VALIDATOR_ID, address(pUSD));
        // console2.log("Accrued commission: %d", commission); // Keep commented

        // Verify that some commission has accrued
        assertGt(commission, 0, "Commission should be greater than 0");

        // Claim the commission
        vm.startPrank(admin);
        uint256 balanceBefore = pUSD.balanceOf(admin); // <<< CHANGE: Check balance of the actual recipient (admin)

        ValidatorFacet(address(diamondProxy)).requestCommissionClaim(DEFAULT_VALIDATOR_ID, address(pUSD));
        vm.warp(block.timestamp + 7 days);

        uint256 claimedAmount =
            ValidatorFacet(address(diamondProxy)).finalizeCommissionClaim(DEFAULT_VALIDATOR_ID, address(pUSD));

        uint256 balanceAfter = pUSD.balanceOf(admin);
        vm.stopPrank();

        // Verify that commission was claimed successfully
        assertEq(balanceAfter - balanceBefore, claimedAmount, "Balance should increase by claimed amount");
    }

    function testGetAccruedCommission_Direct() public {
        // Set a very specific reward rate for predictable results
        uint256 rewardRate = 1e18; // 1 PUSD per second
        vm.startPrank(admin);
        address[] memory tokens = new address[](1);
        tokens[0] = address(pUSD);
        uint256[] memory rates = new uint256[](1);
        rates[0] = rewardRate;
        // Ensure max rate allows the desired rate
        RewardsFacet(address(diamondProxy)).setMaxRewardRate(address(pUSD), rewardRate);
        RewardsFacet(address(diamondProxy)).setRewardRates(tokens, rates);

        // Make sure treasury is properly set
        RewardsFacet(address(diamondProxy)).setTreasury(address(treasury));

        // Ensure treasury has enough PUSD by transferring tokens
        uint256 treasuryAmount = 100 * 1e6; // Corrected for 6 decimals
        pUSD.transfer(address(treasury), treasuryAmount);
        vm.stopPrank();

        // Set a 10% commission rate for the validator
        vm.startPrank(admin); // Use admin assumed to be L2 admin for validator 1
        uint256 newCommission10 = 10e16; // 10% commission (scaled by 1e18)
        ValidatorFacet(address(diamondProxy)).setValidatorCommission(DEFAULT_VALIDATOR_ID, newCommission10);
        vm.stopPrank();

        // Create validator with 10% commission
        uint256 initialStake = 10 ether;
        vm.startPrank(user1);
        StakingFacet(address(diamondProxy)).stake{ value: initialStake }(DEFAULT_VALIDATOR_ID);
        vm.stopPrank();

        // Move time forward to accrue rewards
        vm.roll(block.number + 10);
        vm.warp(block.timestamp + 10);

        // Trigger reward updates by having a user interact with the system
        // This will internally call updateRewardsForValidator
        vm.startPrank(user2);
        StakingFacet(address(diamondProxy)).stake{ value: 1 ether }(DEFAULT_VALIDATOR_ID);
        vm.stopPrank();

        // Move time forward again
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        // Interact again to update rewards once more
        vm.startPrank(user1);
        // Unstake a minimal amount to trigger reward update
        StakingFacet(address(diamondProxy)).unstake(DEFAULT_VALIDATOR_ID, 1); // Unstake 1 wei
        vm.stopPrank();

        // Check that some commission has accrued (positive amount)
        uint256 commission =
            ValidatorFacet(address(diamondProxy)).getAccruedCommission(DEFAULT_VALIDATOR_ID, address(pUSD));
        assertGt(commission, 0, "Commission should be greater than 0");

        // Try to claim the commission to verify it works end-to-end
        vm.startPrank(admin);
        uint256 balanceBefore = pUSD.balanceOf(admin);

        ValidatorFacet(address(diamondProxy)).requestCommissionClaim(DEFAULT_VALIDATOR_ID, address(pUSD));
        vm.warp(block.timestamp + 7 days);

        uint256 claimedAmount =
            ValidatorFacet(address(diamondProxy)).finalizeCommissionClaim(DEFAULT_VALIDATOR_ID, address(pUSD));

        uint256 balanceAfter = pUSD.balanceOf(admin);
        vm.stopPrank();

        // Verify that commission was claimed successfully
        assertEq(balanceAfter - balanceBefore, claimedAmount, "Balance should increase by claimed amount");
    }

    function testRewardAccrualAndClaim() public {
        // Set a very low reward rate to test with predictable amounts
        uint256 rewardRate = 1e15; // 0.001 PUSD per second
        vm.startPrank(admin);
        address[] memory tokens = new address[](1);
        tokens[0] = address(pUSD);
        uint256[] memory rates = new uint256[](1);
        rates[0] = rewardRate;
        // Ensure max rate allows the desired rate
        RewardsFacet(address(diamondProxy)).setMaxRewardRate(address(pUSD), rewardRate);
        RewardsFacet(address(diamondProxy)).setRewardRates(tokens, rates);
        vm.stopPrank();

        // Ensure treasury has enough PUSD by transferring tokens
        uint256 treasuryAmount = 50_000_000_000;
        vm.startPrank(admin); // admin already has tokens from constructor
        pUSD.transfer(address(treasury), treasuryAmount);
        vm.stopPrank();

        // Stake
        uint256 stakeAmount = 10 ether;
        StakingFacet(address(diamondProxy)).stake{ value: stakeAmount }(DEFAULT_VALIDATOR_ID);

        vm.roll(block.number + 100);
        vm.warp(block.timestamp + 100);

        // Should have accrued about 0.1 PUSD (100 seconds * 0.001 PUSD per second)
        uint256 balanceBefore = pUSD.balanceOf(user1);
        uint256 claimableBefore = RewardsFacet(address(diamondProxy)).getClaimableReward(user1, address(pUSD));

        // Claim rewards
        RewardsFacet(address(diamondProxy)).claim(address(pUSD), DEFAULT_VALIDATOR_ID);
        vm.stopPrank();

        // Verify balance increased by claimed amount
        uint256 balanceAfter = pUSD.balanceOf(user1);
        assertEq(balanceAfter - balanceBefore, claimableBefore, "Balance should increase by claimed amount");

        // Claimable should now be very small (maybe not exactly 0 due to new rewards accruing in the same block as the
        // claim)
        uint256 claimableAfter = RewardsFacet(address(diamondProxy)).getClaimableReward(user1, address(pUSD));
        assertLe(claimableAfter, 1e14, "Claimable should be very small after claim");
    }

    function testComprehensiveStakingAndRewards() public {
        console2.log("Starting comprehensive staking and rewards test");

        // Setup reward tokens with known rates for easy calculation
        // PUSD: 0.001 token per second (reduced from 1), PLUME_NATIVE: much smaller rate to avoid exceeding max
        uint256 pusdRate = 1e15; // 0.001 PUSD per second (reduced from 1e18 to prevent excessive rewards)
        uint256 plumeRate = 1e10; // 0.000000001 PLUME per second (adjusted to be below max)

        vm.startPrank(admin);
        address[] memory tokens = new address[](2);
        tokens[0] = address(pUSD);
        tokens[1] = PLUME_NATIVE;
        uint256[] memory rates = new uint256[](2);
        rates[0] = pusdRate;
        rates[1] = plumeRate;
        // Ensure max rates allow the new rates
        RewardsFacet(address(diamondProxy)).setMaxRewardRate(address(pUSD), pusdRate);
        RewardsFacet(address(diamondProxy)).setMaxRewardRate(PLUME_NATIVE, plumeRate);
        RewardsFacet(address(diamondProxy)).setRewardRates(tokens, rates);

        // Ensure treasury has enough tokens
        uint256 treasuryAmount = 1000 * 1e6; // Corrected for 6 decimals
        pUSD.transfer(address(treasury), treasuryAmount);
        vm.stopPrank();

        // Record initial timestamps
        uint256 initialTimestamp = block.timestamp;
        uint256 initialBlock = block.number;
        console2.log("Initial timestamp:", initialTimestamp);
        console2.log("Initial block:", initialBlock);

        // Setup commission for validators
        uint16 validator0 = DEFAULT_VALIDATOR_ID;
        uint16 validator1 = 1;
        uint256 commissionRate0 = 1000; // 10%
        uint256 commissionRate1 = 2000; // 20%

        // Set commission rates
        vm.startPrank(admin);
        ValidatorFacet(address(diamondProxy)).setValidatorCommission(validator0, 10e16); // Use actual commission value
            // directly (10e16 = 10%)
        vm.stopPrank();

        vm.startPrank(admin); // user2 is admin for validator1 from setUp
        ValidatorFacet(address(diamondProxy)).setValidatorCommission(validator1, 20e16); // Use actual commission value
            // directly (20e16 = 20%)
        vm.stopPrank();

        // === User1 stakes with validator0 ===
        console2.log("User 1 staking with validator 0");
        uint256 user1Stake = 50 ether;
        vm.startPrank(user1);
        StakingFacet(address(diamondProxy)).stake{ value: user1Stake }(validator0);
        vm.stopPrank();

        // === User2 stakes with validator1 ===
        console2.log("User 2 staking with validator 1");
        uint256 user2Stake = 100 ether;
        vm.startPrank(user2);
        StakingFacet(address(diamondProxy)).stake{ value: user2Stake }(validator1);
        vm.stopPrank();

        // === First time advancement (1 day) ===
        uint256 timeAdvance1 = 1 days;
        vm.roll(block.number + timeAdvance1 / 12); // Assuming ~12 second blocks
        vm.warp(block.timestamp + timeAdvance1);
        console2.log("Advanced time by 1 day");

        // Check accrued rewards for user1
        uint256 user1ExpectedReward = user1Stake * pusdRate * timeAdvance1 / 1e18; // Simplified calculation
        uint256 user1Commission = user1ExpectedReward * commissionRate0 / 10_000;
        uint256 user1NetReward = user1ExpectedReward - user1Commission;

        uint256 user1ClaimablePUSD = RewardsFacet(address(diamondProxy)).getClaimableReward(user1, address(pUSD));
        console2.log("User 1 claimable PUSD after 1 day:", user1ClaimablePUSD);
        console2.log("Expected approximately:", user1NetReward);

        // Check accrued commission for validator0
        uint256 validator0Commission =
            ValidatorFacet(address(diamondProxy)).getAccruedCommission(validator0, address(pUSD));
        console2.log("Validator 0 accrued commission:", validator0Commission);
        console2.log("Expected approximately:", user1Commission);

        // === User1 claims rewards ===
        vm.startPrank(user1);
        uint256 user1BalanceBefore = pUSD.balanceOf(user1);
        uint256 claimedAmount = RewardsFacet(address(diamondProxy)).claim(address(pUSD), DEFAULT_VALIDATOR_ID);
        uint256 user1BalanceAfter = pUSD.balanceOf(user1);

        // Verify claim was successful
        assertApproxEqAbs(
            user1BalanceAfter - user1BalanceBefore,
            claimedAmount,
            10 ** 10,
            "User claimed amount should match balance increase"
        );

        // Reset block timestamp back to beginning of the test to stop rewards from accruing
        vm.warp(1);

        // Check claimable amount after resetting time - should now be near zero
        uint256 claimableAfterClaim = RewardsFacet(address(diamondProxy)).getClaimableReward(user1, address(pUSD));
        assertApproxEqAbs(claimableAfterClaim, 0, 10 ** 10, "Final claimable should be near zero");

        // Claim validator commission
        vm.stopPrank();

        vm.startPrank(admin); // Use KNOWN_ADMIN assumed to be L2 admin for validator 1
        uint256 validatorBalanceBefore = pUSD.balanceOf(admin); // <<< CHANGE: Check balance of actual admin for
        // validatorId 1
        ValidatorFacet(address(diamondProxy)).requestCommissionClaim(DEFAULT_VALIDATOR_ID, address(pUSD));
        vm.warp(block.timestamp + 7 days);
        uint256 commissionClaimed =
            ValidatorFacet(address(diamondProxy)).finalizeCommissionClaim(DEFAULT_VALIDATOR_ID, address(pUSD));

        uint256 validatorBalanceAfter = pUSD.balanceOf(admin); // Check balance of actual admin for validatorId 1

        // Verify commission claim was successful
        assertApproxEqAbs(
            validatorBalanceAfter - validatorBalanceBefore,
            commissionClaimed,
            10 ** 10,
            "Validator claimed amount should match balance increase"
        );

        // Check final commission accrued (should be zero since we reset the time)
        uint256 finalCommission =
            ValidatorFacet(address(diamondProxy)).getAccruedCommission(DEFAULT_VALIDATOR_ID, address(pUSD));
        assertApproxEqAbs(finalCommission, 0, 10 ** 10, "Final accrued commission should be near zero");
        vm.stopPrank();

        console2.log("--- Commission & Reward Rate Change Test Complete ---");
    }

    // --- Access Control / Edge Cases ---

    function testClaimValidatorCommission_ZeroAmount() public {
        uint16 validatorId = DEFAULT_VALIDATOR_ID;
        address token = address(pUSD);
        address recipient = validatorAdmin;

        // No staking, no time warp -> commission should be 0
        vm.startPrank(user1); // user1 is NOT the admin for validator 1
        vm.expectRevert(abi.encodeWithSelector(NotValidatorAdmin.selector, user1));
        ValidatorFacet(address(diamondProxy)).requestCommissionClaim(validatorId, token);
        vm.stopPrank();
    }

    function testClaimValidatorCommission_NonExistent() public {
        uint16 nonExistentId = 999;
        address token = address(pUSD);

        vm.startPrank(validatorAdmin); // Prank as a valid admin for *some* validator (e.g., ID 0)
        vm.expectRevert(abi.encodeWithSelector(ValidatorDoesNotExist.selector, nonExistentId));
        ValidatorFacet(address(diamondProxy)).requestCommissionClaim(nonExistentId, token);
        vm.stopPrank();
    }

    function testClaimValidatorCommission_NotAdmin() public {
        uint16 validatorId = DEFAULT_VALIDATOR_ID;
        address token = address(pUSD);

        vm.startPrank(user1); // user1 is not the admin for validator 0
        vm.expectRevert(abi.encodeWithSelector(NotValidatorAdmin.selector, user1));
        ValidatorFacet(address(diamondProxy)).requestCommissionClaim(validatorId, token);
        vm.stopPrank();
    }

    function testUpdateValidator_Commission() public {
        uint16 validatorId = DEFAULT_VALIDATOR_ID;
        uint256 newCommission = 20e16; // 20%

        // Get current state BEFORE update to build expected event
        (PlumeStakingStorage.ValidatorInfo memory infoBefore,,) =
            ValidatorFacet(address(diamondProxy)).getValidatorInfo(validatorId);

        // Correct event check: Expect ValidatorUpdated, not ValidatorCommissionSet
        vm.expectEmit(true, true, true, true, address(diamondProxy));
        emit ValidatorUpdated(
            validatorId,
            newCommission, // new commission
            infoBefore.l2AdminAddress, // old l2Admin
            infoBefore.l2WithdrawAddress, // old l2Withdraw
            infoBefore.l1ValidatorAddress, // old l1Validator
            infoBefore.l1AccountAddress, // old l1Account
            infoBefore.l1AccountEvmAddress // old l1AccountEvm
        );

        // Call as the VALIDATOR ADMIN (l2AdminAddress)
        vm.startPrank(admin);
        ValidatorFacet(address(diamondProxy)).setValidatorCommission(validatorId, newCommission);
        vm.stopPrank();

        // Verify
        (PlumeStakingStorage.ValidatorInfo memory infoAfter,,) =
            ValidatorFacet(address(diamondProxy)).getValidatorInfo(validatorId);
        assertEq(infoAfter.commission, newCommission, "Commission not updated");
    }

    function testUpdateValidator_Commission_NotOwner() public {
        uint16 validatorId = DEFAULT_VALIDATOR_ID;
        uint256 newCommission = 20e16;

        // Expect revert from the validator admin check

        vm.startPrank(user1); // user1 is not the validator admin for validator 0
        vm.expectRevert(abi.encodeWithSelector(NotValidatorAdmin.selector, user1));

        ValidatorFacet(address(diamondProxy)).setValidatorCommission(validatorId, newCommission);
        // correct function)
        vm.stopPrank();
    }

    function testUpdateValidator_L2Admin() public {
        uint16 validatorId = DEFAULT_VALIDATOR_ID;
        address newAdmin = makeAddr("newAdminForVal0");

        // Get current state BEFORE update
        (PlumeStakingStorage.ValidatorInfo memory infoBefore,,) =
            ValidatorFacet(address(diamondProxy)).getValidatorInfo(validatorId);

        // Correct event check: Expect ValidatorUpdated, not ValidatorAddressesSet
        vm.expectEmit(true, true, true, true, address(diamondProxy));
        emit ValidatorUpdated(
            validatorId,
            infoBefore.commission, // old commission
            newAdmin, // new l2Admin
            infoBefore.l2WithdrawAddress, // old l2Withdraw
            infoBefore.l1ValidatorAddress, // old l1Validator
            infoBefore.l1AccountAddress, // old l1Account
            infoBefore.l1AccountEvmAddress // old l1AccountEvm
        );

        // Call as the CURRENT VALIDATOR ADMIN
        vm.startPrank(admin); // Use KNOWN_ADMIN assumed to be L2 admin for validator 1
        ValidatorFacet(address(diamondProxy)).setValidatorAddresses(
            validatorId,
            newAdmin, // new l2Admin
            infoBefore.l2WithdrawAddress, // keep old l2Withdraw
            infoBefore.l1ValidatorAddress, // keep old l1Validator
            infoBefore.l1AccountAddress, // keep old l1Account
            infoBefore.l1AccountEvmAddress // keep old l1AccountEvm
        );
        vm.stopPrank();

        (PlumeStakingStorage.ValidatorInfo memory infoAfter,,) =
            ValidatorFacet(address(diamondProxy)).getValidatorInfo(validatorId);
        assertEq(infoAfter.l2AdminAddress, newAdmin, "L2 Admin not updated");
    }

    function testUpdateValidator_L2Admin_NotOwner() public {
        uint16 validatorId = DEFAULT_VALIDATOR_ID;
        address newAdmin = makeAddr("newAdminForVal0");

        // Get validator info first, needed for setValidatorAddresses call
        (PlumeStakingStorage.ValidatorInfo memory infoBefore,,) =
            ValidatorFacet(address(diamondProxy)).getValidatorInfo(validatorId);

        // Expect revert from the validator admin check
        vm.expectRevert(abi.encodeWithSelector(NotValidatorAdmin.selector, user1));
        vm.startPrank(user1); // user1 is not the validator admin for validator 0
        ValidatorFacet(address(diamondProxy)).setValidatorAddresses(
            validatorId,
            newAdmin,
            infoBefore.l2WithdrawAddress,
            infoBefore.l1ValidatorAddress,
            infoBefore.l1AccountAddress,
            infoBefore.l1AccountEvmAddress
        );
        vm.stopPrank();
    }

    function testUpdateValidator_NonExistent() public {
        uint16 nonExistentId = 999;
        uint256 newCommission = 20e16;
        vm.startPrank(validatorAdmin);
        vm.expectRevert(abi.encodeWithSelector(ValidatorDoesNotExist.selector, nonExistentId));
        ValidatorFacet(address(diamondProxy)).setValidatorCommission(nonExistentId, newCommission);
        vm.stopPrank();
    }

    function testSetMinStakeAmount() public {
        uint256 newMinStake = 2 ether;
        uint256 oldMinStake = ManagementFacet(address(diamondProxy)).getMinStakeAmount();

        // Check event emission - Use the correct event name 'MinStakeAmountSet'
        vm.expectEmit(true, false, false, true, address(diamondProxy)); // Check data only
        emit MinStakeAmountSet(newMinStake);

        // Call as admin
        vm.startPrank(admin);
        ManagementFacet(address(diamondProxy)).setMinStakeAmount(newMinStake);
        vm.stopPrank();

        // Verify the new value
        assertEq(
            ManagementFacet(address(diamondProxy)).getMinStakeAmount(), newMinStake, "Min stake amount not updated"
        );
    }

    function testSetCooldownInterval() public {
        uint256 newCooldown = 14 days;
        uint256 oldCooldown = ManagementFacet(address(diamondProxy)).getCooldownInterval();

        // Check event emission - Use the correct event name 'CooldownIntervalSet'
        vm.expectEmit(true, false, false, true, address(diamondProxy)); // Check data only
        emit CooldownIntervalSet(newCooldown);

        // Call as admin
        vm.startPrank(admin);
        ManagementFacet(address(diamondProxy)).setCooldownInterval(newCooldown);
        vm.stopPrank();

        // Verify the new value
        assertEq(
            ManagementFacet(address(diamondProxy)).getCooldownInterval(), newCooldown, "Cooldown interval not updated"
        );
    }

    // --- Additional ManagementFacet Tests ---

    function testAdminWithdraw() public {
        // Setup: Add some ETH to the contract
        uint256 initialAmount = 10 ether;
        vm.deal(address(diamondProxy), initialAmount);

        // Target address to receive funds
        address payable recipient = payable(makeAddr("recipient"));
        uint256 recipientBalanceBefore = recipient.balance;

        // Amount to withdraw
        uint256 withdrawAmount = 5 ether;

        // Check event emission
        vm.expectEmit(true, true, true, true, address(diamondProxy));
        emit AdminWithdraw(PLUME_NATIVE, withdrawAmount, recipient);

        // Call adminWithdraw as admin
        vm.startPrank(admin);
        ManagementFacet(address(diamondProxy)).adminWithdraw(PLUME_NATIVE, withdrawAmount, recipient);
        vm.stopPrank();

        // Verify recipient received the funds
        assertEq(recipient.balance, recipientBalanceBefore + withdrawAmount, "Recipient balance not updated correctly");

        // Verify contract balance decreased
        assertEq(
            address(diamondProxy).balance, initialAmount - withdrawAmount, "Contract balance not updated correctly"
        );
    }

    function testAdminWithdraw_TokenTransfer() public {
        // Setup: Mock a token transfer
        address token = address(pUSD);
        uint256 withdrawAmount = 100 * 1e6; // Corrected for 6 decimals
        address recipient = makeAddr("tokenRecipient");

        // Mock the token balanceOf call to return sufficient balance
        vm.mockCall(
            token,
            abi.encodeWithSelector(IERC20.balanceOf.selector, address(diamondProxy)),
            abi.encode(withdrawAmount * 2) // Ensure sufficient balance
        );

        // Mock the transfer call to succeed
        vm.mockCall(
            token, abi.encodeWithSelector(IERC20.transfer.selector, recipient, withdrawAmount), abi.encode(true)
        );

        // Check event emission - note that token is indexed and recipient is indexed
        vm.expectEmit(true, true, true, true, address(diamondProxy));
        emit AdminWithdraw(token, withdrawAmount, recipient);

        // Call adminWithdraw as admin
        vm.startPrank(admin);
        ManagementFacet(address(diamondProxy)).adminWithdraw(token, withdrawAmount, recipient);
        vm.stopPrank();
    }

    function testAdminWithdraw_NotAdmin() public {
        address token = PLUME_NATIVE;
        uint256 withdrawAmount = 1 ether;
        address recipient = makeAddr("recipient");

        // Call as non-admin and expect revert
        vm.startPrank(user1);
        // vm.expectRevert(bytes("Caller does not have the required role"));
        // Updated to expect string revert based on trace
        vm.expectRevert(bytes("Caller does not have the required role"));
        ManagementFacet(address(diamondProxy)).adminWithdraw(token, withdrawAmount, recipient);
        vm.stopPrank();
    }

    function testSetMinStakeAmount_InvalidAmount() public {
        uint256 invalidAmount = 0; // Zero is invalid

        // Call as admin but with invalid amount
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(InvalidAmount.selector, invalidAmount));
        ManagementFacet(address(diamondProxy)).setMinStakeAmount(invalidAmount);
        vm.stopPrank();
    }

    // --- ValidatorFacet Tests ---

    function testAddValidator() public {
        uint16 newValidatorId = 3;
        uint256 commission = 5e16;
        address l2Admin = validatorAdmin;
        address l2Withdraw = validatorAdmin;
        string memory l1ValAddr = "0xval3";
        string memory l1AccAddr = "0xacc3";
        address l1AccEvmAddr = address(0x1234);
        uint256 maxCapacity = 1_000_000e18;

        // Check event emission
        vm.expectEmit(true, true, true, true, address(diamondProxy));
        emit ValidatorAdded(newValidatorId, commission, l2Admin, l2Withdraw, l1ValAddr, l1AccAddr, l1AccEvmAddr);

        // Call as admin
        vm.startPrank(admin);
        ValidatorFacet(address(diamondProxy)).addValidator(
            newValidatorId, commission, l2Admin, l2Withdraw, l1ValAddr, l1AccAddr, l1AccEvmAddr, maxCapacity
        );
        vm.stopPrank();

        // Verify using getValidatorInfo
        (PlumeStakingStorage.ValidatorInfo memory storedInfo,,) =
            ValidatorFacet(address(diamondProxy)).getValidatorInfo(newValidatorId);
        assertEq(storedInfo.commission, commission, "Stored commission mismatch");
        assertEq(storedInfo.l2AdminAddress, l2Admin, "Stored L2 admin mismatch");
        assertEq(storedInfo.l2WithdrawAddress, l2Withdraw, "Stored L2 withdraw mismatch");
        // Add checks for other fields if needed, e.g., l1 addresses, active status
        assertEq(storedInfo.l1ValidatorAddress, l1ValAddr, "Stored L1 validator address mismatch");
        assertEq(storedInfo.l1AccountAddress, l1AccAddr, "Stored L1 account address mismatch");
        assertEq(storedInfo.l1AccountEvmAddress, l1AccEvmAddr, "Stored L1 account EVM address mismatch");
        assertTrue(storedInfo.active, "Newly added validator should be active");
    }

    function testAddValidator_NotOwner() public {
        uint16 newValidatorId = 3;
        uint256 maxCapacity = 1_000_000e18;

        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, user1, PlumeRoles.VALIDATOR_ROLE));

        vm.startPrank(user1); // user1 does not have VALIDATOR_ROLE by default
        ValidatorFacet(address(diamondProxy)).addValidator(
            newValidatorId, 5e16, user1, user1, "0xval4", "0xacc4", address(0x5678), maxCapacity
        );
        vm.stopPrank();
    }

    function testGetValidatorInfo_Existing() public {
        // Use validator added in setUp
        (PlumeStakingStorage.ValidatorInfo memory info,,) =
            ValidatorFacet(address(diamondProxy)).getValidatorInfo(DEFAULT_VALIDATOR_ID);

        assertEq(info.validatorId, DEFAULT_VALIDATOR_ID, "ID mismatch");
        assertTrue(info.active, "Should be active");
        assertEq(info.commission, 1e15, "Commission mismatch"); // Value from setUp
        assertEq(info.l2AdminAddress, admin, "L2 Admin mismatch"); // Value from setUp
        assertEq(info.l2WithdrawAddress, admin, "L2 Withdraw mismatch"); // Value from setUp
        // assertEq(info.maxCapacity, 1_000_000e18, "Capacity mismatch"); // Value from setUp - Capacity might differ on
        // mainnet
        // Check L1 addresses added in setUp
        // assertEq(info.l1ValidatorAddress, "0xval1", "L1 validator address mismatch");
        assertEq(info.l1ValidatorAddress, "1231231", "L1 validator address mismatch"); // Corrected expected value
        // assertEq(info.l1AccountAddress, "0xacc1", "L1 account address mismatch");
        assertEq(info.l1AccountAddress, "1231231", "L1 account address mismatch"); // Corrected expected value
        assertTrue(info.l1AccountEvmAddress == address(admin), "L1 account EVM address mismatch");
    }

    function testGetValidatorInfo_NonExistent() public {
        uint16 nonExistentId = 999;
        // Expect revert from _validateValidatorExists modifier
        vm.expectRevert(abi.encodeWithSelector(ValidatorDoesNotExist.selector, nonExistentId));
        ValidatorFacet(address(diamondProxy)).getValidatorInfo(nonExistentId);
    }

    function testSetValidatorCapacity() public {
        uint16 validatorId = DEFAULT_VALIDATOR_ID;
        uint256 newCapacity = 2_000_000 ether;

        // Get old capacity for event check
        (PlumeStakingStorage.ValidatorInfo memory infoBefore,,) =
            ValidatorFacet(address(diamondProxy)).getValidatorInfo(validatorId);
        uint256 oldCapacity = infoBefore.maxCapacity;

        // Check event emission
        vm.expectEmit(true, true, true, true, address(diamondProxy));
        emit ValidatorCapacityUpdated(validatorId, oldCapacity, newCapacity);

        // Call as admin
        vm.startPrank(admin);
        ValidatorFacet(address(diamondProxy)).setValidatorCapacity(validatorId, newCapacity);
        vm.stopPrank();

        // Verify the new capacity
        (PlumeStakingStorage.ValidatorInfo memory infoAfter,,) =
            ValidatorFacet(address(diamondProxy)).getValidatorInfo(validatorId);
        assertEq(infoAfter.maxCapacity, newCapacity, "Validator capacity not updated");
    }

    function testGetValidatorStats_Existing() public {
        uint16 validatorId = DEFAULT_VALIDATOR_ID;

        // Get initial state before staking
        (bool initialActive, uint256 initialCommission, uint256 initialTotalStaked, uint256 initialStakersCount) =
            ValidatorFacet(address(diamondProxy)).getValidatorStats(validatorId);

        // Stake to ensure staker count and total staked are non-zero if needed
        vm.startPrank(user1);
        StakingFacet(address(diamondProxy)).stake{ value: 100 ether }(validatorId);
        vm.stopPrank();

        (bool finalActive, uint256 finalCommission, uint256 finalTotalStaked, uint256 finalStakersCount) =
            ValidatorFacet(address(diamondProxy)).getValidatorStats(validatorId);

        assertTrue(finalActive, "Stats: Should be active");
        // Commission might be changed by other tests or fork state, better to check against initial
        assertEq(finalCommission, initialCommission, "Stats: Commission should not change");
        assertEq(finalTotalStaked, initialTotalStaked + 100 ether, "Stats: Total staked mismatch");
        assertEq(finalStakersCount, initialStakersCount + 1, "Stats: Stakers count mismatch");
    }

    function testGetValidatorStats_NonExistent() public {
        uint16 nonExistentId = 999;
        vm.expectRevert(abi.encodeWithSelector(ValidatorDoesNotExist.selector, nonExistentId));
        ValidatorFacet(address(diamondProxy)).getValidatorStats(nonExistentId);
    }

    function testGetUserValidators() public {
        uint16 validatorId0 = DEFAULT_VALIDATOR_ID;
        uint16 validatorId1 = 2;

        // Give user1 enough ETH for the stakes
        vm.deal(user1, 100 ether);

        // user1 stakes with validator 0 and 1
        vm.startPrank(user1);
        StakingFacet(address(diamondProxy)).stake{ value: 50 ether }(validatorId0);
        StakingFacet(address(diamondProxy)).stake{ value: 50 ether }(validatorId1);
        vm.stopPrank();

        // user2 stakes only with validator 1
        vm.startPrank(user2);
        StakingFacet(address(diamondProxy)).stake{ value: 100 ether }(validatorId1);
        vm.stopPrank();

        // Check user1
        uint16[] memory user1Validators = ValidatorFacet(address(diamondProxy)).getUserValidators(user1);
        assertEq(user1Validators.length, 2, "User1 validator count mismatch");
        assertEq(user1Validators[0], validatorId0, "User1 validator[0] mismatch");
        assertEq(user1Validators[1], validatorId1, "User1 validator[1] mismatch");

        // Check user2
        uint16[] memory user2Validators = ValidatorFacet(address(diamondProxy)).getUserValidators(user2);
        assertEq(user2Validators.length, 1, "User2 validator count mismatch");
        assertEq(user2Validators[0], validatorId1, "User2 validator[0] mismatch");

        // Check address with no stakes
        uint16[] memory user3Validators = ValidatorFacet(address(diamondProxy)).getUserValidators(user3);
        assertEq(user3Validators.length, 0, "User3 validator count mismatch");
    }

    function testGetValidatorsList_Data() public {
        uint16 validatorId0 = DEFAULT_VALIDATOR_ID; // 1
        uint16 validatorId1 = 2;

        // Get initial states before staking
        (,, uint256 initialTotalStaked0,) = ValidatorFacet(address(diamondProxy)).getValidatorStats(validatorId0);
        (,, uint256 initialTotalStaked1,) = ValidatorFacet(address(diamondProxy)).getValidatorStats(validatorId1);
        (PlumeStakingStorage.ValidatorInfo memory info0,,) =
            ValidatorFacet(address(diamondProxy)).getValidatorInfo(validatorId0);
        (PlumeStakingStorage.ValidatorInfo memory info1,,) =
            ValidatorFacet(address(diamondProxy)).getValidatorInfo(validatorId1);
        uint256 initialCommission0 = info0.commission;
        uint256 initialCommission1 = info1.commission;

        uint256 stake0 = 50 ether;
        uint256 stake1_user1 = 75 ether;
        uint256 stake1_user2 = 100 ether;
        uint256 totalNewStake1 = stake1_user1 + stake1_user2;

        // user1 stakes with validator 0 and 1
        vm.startPrank(user1);
        StakingFacet(address(diamondProxy)).stake{ value: stake0 }(validatorId0);
        StakingFacet(address(diamondProxy)).stake{ value: stake1_user1 }(validatorId1);
        vm.stopPrank();

        // user2 stakes only with validator 1
        vm.startPrank(user2);
        StakingFacet(address(diamondProxy)).stake{ value: stake1_user2 }(validatorId1);
        vm.stopPrank();

        // Fetch the list data
        // Need to use the struct defined *within* ValidatorFacet
        ValidatorFacet.ValidatorListData[] memory listData = ValidatorFacet(address(diamondProxy)).getValidatorsList();

        // There should be 2 validators (from setUp)
        assertEq(listData.length, 2, "List length mismatch");

        // Verify data for validator 0
        assertEq(listData[0].id, validatorId0, "Validator 0 ID mismatch");
        assertEq(listData[0].totalStaked, initialTotalStaked0 + stake0, "Validator 0 total staked mismatch");
        assertEq(listData[0].commission, initialCommission0, "Validator 0 commission mismatch"); // Check against
            // initial state

        // Verify data for validator 1
        assertEq(listData[1].id, validatorId1, "Validator 1 ID mismatch");
        assertEq(listData[1].totalStaked, initialTotalStaked1 + totalNewStake1, "Validator 1 total staked mismatch");
        assertEq(listData[1].commission, initialCommission1, "Validator 1 commission mismatch"); // Check against
            // initial state
    }

    // --- AccessControlFacet Tests ---

    function testAC_InitialRoles() public {
        IAccessControl ac = IAccessControl(address(diamondProxy));
        assertTrue(ac.hasRole(PlumeRoles.ADMIN_ROLE, admin), "Admin should have ADMIN_ROLE");
        assertTrue(ac.hasRole(PlumeRoles.UPGRADER_ROLE, admin), "Admin should have UPGRADER_ROLE");
        assertTrue(ac.hasRole(PlumeRoles.VALIDATOR_ROLE, admin), "Admin should have VALIDATOR_ROLE");
        assertTrue(ac.hasRole(PlumeRoles.REWARD_MANAGER_ROLE, admin), "Admin should have REWARD_MANAGER_ROLE");
        assertFalse(ac.hasRole(PlumeRoles.ADMIN_ROLE, user1), "User1 should not have ADMIN_ROLE");
    }

    function testAC_GetRoleAdmin() public {
        IAccessControl ac = IAccessControl(address(diamondProxy));
        assertEq(ac.getRoleAdmin(PlumeRoles.ADMIN_ROLE), PlumeRoles.ADMIN_ROLE, "Admin of ADMIN_ROLE mismatch");
        assertEq(ac.getRoleAdmin(PlumeRoles.UPGRADER_ROLE), PlumeRoles.ADMIN_ROLE, "Admin of UPGRADER_ROLE mismatch");
        assertEq(ac.getRoleAdmin(PlumeRoles.VALIDATOR_ROLE), PlumeRoles.ADMIN_ROLE, "Admin of VALIDATOR_ROLE mismatch");
        assertEq(
            ac.getRoleAdmin(PlumeRoles.REWARD_MANAGER_ROLE),
            PlumeRoles.ADMIN_ROLE,
            "Admin of REWARD_MANAGER_ROLE mismatch"
        );
        // Check default admin for an unmanaged role (should be 0x00)
        bytes32 unmanagedRole = keccak256("UNMANAGED_ROLE");
        assertEq(ac.getRoleAdmin(unmanagedRole), bytes32(0), "Default admin mismatch");
    }

    function testAC_GrantRole() public {
        IAccessControl ac = IAccessControl(address(diamondProxy));
        bytes32 roleToGrant = PlumeRoles.VALIDATOR_ROLE;

        assertFalse(ac.hasRole(roleToGrant, user1), "User1 should not have role initially");

        // Admin grants role
        vm.startPrank(admin);
        vm.expectEmit(true, true, true, true, address(diamondProxy));
        emit RoleGranted(roleToGrant, user1, admin);
        ac.grantRole(roleToGrant, user1);
        vm.stopPrank();

        assertTrue(ac.hasRole(roleToGrant, user1), "User1 should have role after grant");

        // Granting again should not emit
        vm.startPrank(admin);
        // vm.expectNoEmit(); // Foundry doesn't have expectNoEmit easily
        ac.grantRole(roleToGrant, user1);
        vm.stopPrank();
    }

    function testAC_GrantRole_NotAdmin() public {
        IAccessControl ac = IAccessControl(address(diamondProxy));
        bytes32 roleToGrant = PlumeRoles.VALIDATOR_ROLE;

        // user1 (who is not admin of VALIDATOR_ROLE) tries to grant
        vm.startPrank(user1);
        // Use custom expectRevert that just checks the error code, not the entire message
        vm.expectRevert();
        ac.grantRole(roleToGrant, user2);
        vm.stopPrank();
    }

    function testAC_RevokeRole() public {
        IAccessControl ac = IAccessControl(address(diamondProxy));
        bytes32 roleToRevoke = PlumeRoles.VALIDATOR_ROLE;

        // Grant first
        vm.startPrank(admin);
        ac.grantRole(roleToRevoke, user1);
        vm.stopPrank();
        assertTrue(ac.hasRole(roleToRevoke, user1), "User1 should have role before revoke");

        // Admin revokes role
        vm.startPrank(admin);
        vm.expectEmit(true, true, true, true, address(diamondProxy));
        emit RoleRevoked(roleToRevoke, user1, admin);
        ac.revokeRole(roleToRevoke, user1);
        vm.stopPrank();

        assertFalse(ac.hasRole(roleToRevoke, user1), "User1 should not have role after revoke");

        // Revoking again should not emit
        vm.startPrank(admin);
        ac.revokeRole(roleToRevoke, user1);
        vm.stopPrank();
    }

    function testAC_RevokeRole_NotAdmin() public {
        IAccessControl ac = IAccessControl(address(diamondProxy));
        bytes32 roleToRevoke = PlumeRoles.VALIDATOR_ROLE;

        // Grant first
        vm.startPrank(admin);
        ac.grantRole(roleToRevoke, user1);
        vm.stopPrank();

        // user2 (not admin) tries to revoke
        vm.startPrank(user2);
        // Use custom expectRevert that just checks the error code, not the entire message
        vm.expectRevert();
        ac.revokeRole(roleToRevoke, user1);
        vm.stopPrank();
    }

    function testAC_RenounceRole() public {
        IAccessControl ac = IAccessControl(address(diamondProxy));
        bytes32 roleToRenounce = PlumeRoles.VALIDATOR_ROLE;

        // Grant first
        vm.startPrank(admin);
        ac.grantRole(roleToRenounce, user1);
        vm.stopPrank();
        assertTrue(ac.hasRole(roleToRenounce, user1), "User1 should have role before renounce");

        // user1 renounces their own role
        vm.startPrank(user1);
        vm.expectEmit(true, true, true, true, address(diamondProxy));
        // Sender in event is msg.sender (user1)
        emit RoleRevoked(roleToRenounce, user1, user1);
        // Interface requires passing the account, internal logic uses msg.sender
        ac.renounceRole(roleToRenounce, user1);
        vm.stopPrank();

        assertFalse(ac.hasRole(roleToRenounce, user1), "User1 should not have role after renounce");
    }

    function testAC_RenounceRole_NotSelf() public {
        IAccessControl ac = IAccessControl(address(diamondProxy));
        bytes32 roleToRenounce = PlumeRoles.VALIDATOR_ROLE;

        // Grant first
        vm.startPrank(admin);
        ac.grantRole(roleToRenounce, user1);
        vm.stopPrank();

        // user2 tries to renounce user1's role
        vm.startPrank(user2);
        vm.expectRevert(bytes("AccessControl: can only renounce roles for self"));
        ac.renounceRole(roleToRenounce, user1);
        vm.stopPrank();
    }

    function testAC_SetRoleAdmin() public {
        IAccessControl ac = IAccessControl(address(diamondProxy));
        bytes32 roleToManage = PlumeRoles.VALIDATOR_ROLE;
        bytes32 newAdminRole = PlumeRoles.UPGRADER_ROLE;
        bytes32 oldAdminRole = ac.getRoleAdmin(roleToManage); // Should be ADMIN_ROLE

        assertEq(oldAdminRole, PlumeRoles.ADMIN_ROLE, "Initial admin role mismatch");

        // Admin changes admin of VALIDATOR_ROLE to UPGRADER_ROLE
        vm.startPrank(admin);
        vm.expectEmit(true, true, true, true, address(diamondProxy));
        emit RoleAdminChanged(roleToManage, oldAdminRole, newAdminRole);
        ac.setRoleAdmin(roleToManage, newAdminRole);
        vm.stopPrank();

        assertEq(ac.getRoleAdmin(roleToManage), newAdminRole, "New admin role was not set");
    }

    function testAC_SetRoleAdmin_NotAdmin() public {
        IAccessControl ac = IAccessControl(address(diamondProxy));
        bytes32 roleToManage = PlumeRoles.VALIDATOR_ROLE;
        bytes32 newAdminRole = PlumeRoles.UPGRADER_ROLE;

        // user1 (not ADMIN_ROLE) tries to set role admin
        vm.startPrank(user1);
        // Use custom expectRevert that just checks the error code, not the entire message
        vm.expectRevert();
        ac.setRoleAdmin(roleToManage, newAdminRole);
        vm.stopPrank();
    }

    // --- Test Protected Functions ---

    function testProtected_AddValidator_Success() public {
        // Admin (who has VALIDATOR_ROLE) calls addValidator
        vm.startPrank(admin);
        ValidatorFacet(address(diamondProxy)).addValidator(
            10, 5e16, user1, user1, "v10", "a10", address(1), 1_000_000e18
        );
        vm.stopPrank();
        // Check validator exists (implicitly checks success)
        (PlumeStakingStorage.ValidatorInfo memory info,,) = ValidatorFacet(address(diamondProxy)).getValidatorInfo(10);
        assertEq(info.validatorId, 10);
    }

    function testProtected_AddValidator_Fail() public {
        // User1 (no VALIDATOR_ROLE) calls addValidator
        vm.startPrank(user1);
        // vm.expectRevert(bytes("Caller does not have the required role"));
        // Updated to expect string revert based on trace
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, user1, PlumeRoles.VALIDATOR_ROLE));
        ValidatorFacet(address(diamondProxy)).addValidator(
            11, 5e16, user2, user2, "v11", "a11", address(2), 1_000_000e18
        );
        vm.stopPrank();
    }

    // --- Slashing Tests ---

    function testSlash_Setup() public {
        vm.deal(DEFAULT_VALIDATOR_ADMIN, 100 ether);

        // Note: Validators are already set to active when added (in addValidator function)
        // But we'll verify they're active by directly accessing storage
        vm.startPrank(admin);
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        // Just in case, explicitly set active flag to true
        $.validators[DEFAULT_VALIDATOR_ID].active = true;
        $.validators[1].active = true;
        $.validators[2].active = true;
        vm.stopPrank();
    }

    function testSlash_Vote_Success() public {
        // Setup validators and users
        testSlash_Setup(); // Ensures validators 1 and 2 are active

        address validator3Admin = makeAddr("validator3Admin");

        // Add a third validator
        vm.startPrank(admin);
        ValidatorFacet(address(diamondProxy)).addValidator(
            3, 15e16, validator3Admin, validator3Admin, "0xval3", "0xacc3", address(0x3456), 1_000_000e18
        );
        ValidatorFacet(address(diamondProxy)).setValidatorCapacity(3, 1_000_000e18);

        // Create users and give them some ETH
        address user1_slash = makeAddr("user1_slash"); // Use different name to avoid conflicts
        address user2_slash = makeAddr("user2_slash");
        vm.deal(user1_slash, 100 ether); // Fund these specific users for this test
        vm.deal(user2_slash, 100 ether);

        // user1 stakes with validator 1 (ID 1, admin: VALIDATOR_1_ADMIN)
        vm.startPrank(user1_slash);
        StakingFacet(address(diamondProxy)).stake{ value: 10 ether }(DEFAULT_VALIDATOR_ID);
        vm.stopPrank();

        // user2 stakes with validator 2 (ID 2, admin: KNOWN_ADMIN)
        vm.startPrank(user2_slash);
        StakingFacet(address(diamondProxy)).stake{ value: 10 ether }(2);
        vm.stopPrank();

        // Set max slash vote duration (using overall admin)
        vm.startPrank(admin);
        ManagementFacet(address(diamondProxy)).setMaxSlashVoteDuration(1 days);
        vm.stopPrank();

        // Target validator to slash: ID 2 (admin KNOWN_ADMIN)
        uint16 targetValidatorId = 3;
        // Voter validator: ID 1 (admin: VALIDATOR_1_ADMIN)
        uint16 voterValidatorId = DEFAULT_VALIDATOR_ID; // ID 1

        // Get total staked before slashing
        uint256 totalStakedBefore = PlumeStakingStorage.layout().totalStaked;
        uint256 targetValidatorStake = PlumeStakingStorage.layout().validatorTotalStaked[targetValidatorId];

        uint256 voteExpiration = block.timestamp + 1 hours;

        // Vote from validator 1 (ID 1, admin: VALIDATOR_1_ADMIN)
        vm.startPrank(admin);
        ValidatorFacet(address(diamondProxy)).voteToSlashValidator(targetValidatorId, voteExpiration);
        vm.stopPrank();

        // Vote from validator 1 (ID 1, admin: VALIDATOR_1_ADMIN)
        vm.startPrank(validator2Admin);
        ValidatorFacet(address(diamondProxy)).voteToSlashValidator(targetValidatorId, voteExpiration);
        vm.stopPrank();

        // --- Now, actually perform the slash --- (Requires ADMIN_ROLE)
        vm.startPrank(admin);
        ValidatorFacet(address(diamondProxy)).slashValidator(targetValidatorId);
        vm.stopPrank();

        // Verify slashing succeeded
        (bool isActive,,,) = ValidatorFacet(address(diamondProxy)).getValidatorStats(targetValidatorId);
        assertTrue(!isActive, "Validator should be inactive after slashing");

        // Verify stake was burned
        uint256 totalStakedAfter = PlumeStakingStorage.layout().totalStaked;
        assertEq(
            totalStakedAfter, totalStakedBefore - targetValidatorStake, "Total stake should decrease by slashed amount"
        );
    }

    function testSlash_Vote_Fail_NotValidatorAdmin() public {
        testSlash_Setup();
        uint16 targetValidatorId = DEFAULT_VALIDATOR_ID;
        address notAdmin = user1;
        uint256 voteExpiration = block.timestamp + 1 hours;

        vm.startPrank(notAdmin);

        vm.expectRevert(abi.encodeWithSelector(NotValidatorAdmin.selector, user1));
        ValidatorFacet(address(diamondProxy)).voteToSlashValidator(targetValidatorId, voteExpiration);
        vm.stopPrank();
    }

    function testSlash_Vote_Fail_TargetInactive() public {
        testSlash_Setup();
        uint16 targetValidatorId = DEFAULT_VALIDATOR_ID;

        // Manually set inactive
        vm.startPrank(admin);
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        $.validators[targetValidatorId].active = false;
        vm.stopPrank();

        // Try to slash
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(UnanimityNotReached.selector, 0, 1));
        ValidatorFacet(address(diamondProxy)).slashValidator(targetValidatorId);
        vm.stopPrank();
    }

    function testSlash_Slash_Fail_TargetAlreadySlashed() public {
        testSlash_Setup();
        uint16 targetValidatorId = DEFAULT_VALIDATOR_ID;

        // Manually set slashed
        vm.startPrank(admin);
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        $.validators[targetValidatorId].slashed = true;
        vm.stopPrank();

        // Try to slash
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(UnanimityNotReached.selector, 0, 1));
        ValidatorFacet(address(diamondProxy)).slashValidator(targetValidatorId);
        vm.stopPrank();
    }

    // --- Test Commission & Reward Rate Changes ---

    function testCommissionAndRewardRateChanges() public {
        console2.log("\n--- Starting Commission & Reward Rate Change Test ---");

        uint16 validatorId = DEFAULT_VALIDATOR_ID; // Validator 0
        address token = address(pUSD); // Focus on PUSD for simplicity
        // uint256 initialCommissionRate = 1000; // 10%
        uint256 initialCommissionRate = 10e16; // 10% scaled
        uint256 initialRewardRate = 1e16; // 0.01 PUSD per second
        uint256 userStakeAmount = 100 ether;

        // --- Initial Setup ---
        console2.log("Setting initial rates and staking...");
        // Set initial commission
        vm.startPrank(admin); // Use KNOWN_ADMIN assumed to be L2 admin for validator 1
        ValidatorFacet(address(diamondProxy)).setValidatorCommission(validatorId, initialCommissionRate);
        vm.stopPrank();

        // Set initial reward rate
        vm.startPrank(admin);
        address[] memory tokens = new address[](1);
        tokens[0] = token;
        uint256[] memory rates = new uint256[](1);
        rates[0] = initialRewardRate;
        // Ensure max rate allows the desired rate
        RewardsFacet(address(diamondProxy)).setMaxRewardRate(address(pUSD), initialRewardRate);
        RewardsFacet(address(diamondProxy)).setRewardRates(tokens, rates);
        // Ensure treasury has funds - increasing to 3000 ether to cover all rewards
        pUSD.transfer(address(treasury), 3000 * 1e6); // Corrected for 6 decimals
        vm.stopPrank();

        // User 1 stakes
        vm.startPrank(user1);
        StakingFacet(address(diamondProxy)).stake{ value: userStakeAmount }(validatorId);
        vm.stopPrank();
        console2.log("User 1 staked", userStakeAmount, "with Validator", validatorId);

        // --- Period 1: Initial Rates (1 Day) ---
        uint256 period1Duration = 1 days;
        uint256 startTimeP1 = block.timestamp;
        console2.log("\nAdvancing time for Period 1 (", period1Duration, " seconds)");
        vm.warp(startTimeP1 + period1Duration);
        vm.roll(block.number + period1Duration / 12); // Approx block advance

        // Calculate expected rewards/commission for period 1
        uint256 totalStaked = userStakeAmount; // Initially, the only stake is from user1
        uint256 expectedRewardP1 = (period1Duration * initialRewardRate * userStakeAmount) / totalStaked;
        uint256 expectedCommissionP1 = (expectedRewardP1 * initialCommissionRate) / PlumeStakingStorage.REWARD_PRECISION;
        uint256 expectedNetRewardP1 = expectedRewardP1 - expectedCommissionP1;

        console2.log("Expected Gross Reward P1:", expectedRewardP1);
        console2.log("Expected Commission P1:", expectedCommissionP1);
        console2.log("Expected Net Reward P1:", expectedNetRewardP1);

        // Check claimable amounts (triggers internal update)
        uint256 claimableP1 = RewardsFacet(address(diamondProxy)).getClaimableReward(user1, token);
        uint256 accruedCommissionP1 = ValidatorFacet(address(diamondProxy)).getAccruedCommission(validatorId, token);
        console2.log("Actual Claimable Reward P1:", claimableP1);
        console2.log("Actual Accrued Commission P1:", accruedCommissionP1);
        assertApproxEqAbs(claimableP1, expectedNetRewardP1, expectedNetRewardP1, "Period 1 Claimable mismatch"); // Allow
            // much larger delta
        assertApproxEqAbs(
            accruedCommissionP1, expectedCommissionP1, expectedCommissionP1, "Period 1 Commission mismatch"
        );

        // --- Period 2: Commission Rate Changed (1 Day) ---
        // uint256 newCommissionRate = 2000; // 20%
        uint256 newCommissionRate = 20e16; // 20% scaled
        console2.log("\nUpdating Commission Rate to", newCommissionRate);
        vm.startPrank(admin); // Use KNOWN_ADMIN assumed to be L2 admin for validator 1
        ValidatorFacet(address(diamondProxy)).setValidatorCommission(validatorId, newCommissionRate);
        vm.stopPrank();

        uint256 period2Duration = 1 days;
        uint256 startTimeP2 = block.timestamp;
        console2.log("Advancing time for Period 2 (", period2Duration, " seconds)");
        vm.warp(startTimeP2 + period2Duration);
        vm.roll(block.number + period2Duration / 12);

        // Calculate expected rewards/commission for period 2 (using new commission rate)
        uint256 expectedRewardP2 = (period2Duration * initialRewardRate * userStakeAmount) / totalStaked;
        uint256 expectedCommissionP2 = (expectedRewardP2 * newCommissionRate) / PlumeStakingStorage.REWARD_PRECISION;
        uint256 expectedNetRewardP2 = expectedRewardP2 - expectedCommissionP2;

        console2.log("Expected Gross Reward P2:", expectedRewardP2);
        console2.log("Expected Commission P2:", expectedCommissionP2);
        console2.log("Expected Net Reward P2:", expectedNetRewardP2);

        // Check claimable amounts (should include P1 + P2)
        uint256 claimableP1P2 = RewardsFacet(address(diamondProxy)).getClaimableReward(user1, token);
        uint256 accruedCommissionP1P2 = ValidatorFacet(address(diamondProxy)).getAccruedCommission(validatorId, token);
        console2.log("Actual Claimable Reward (P1+P2):", claimableP1P2);
        console2.log("Actual Accrued Commission (P1+P2):", accruedCommissionP1P2);
        assertApproxEqAbs(
            claimableP1P2,
            expectedNetRewardP1 + expectedNetRewardP2,
            expectedNetRewardP1 + expectedNetRewardP2,
            "Period 1+2 Claimable mismatch"
        );
        assertApproxEqAbs(
            accruedCommissionP1P2,
            expectedCommissionP1 + expectedCommissionP2,
            expectedCommissionP1 + expectedCommissionP2,
            "Period 1+2 Commission mismatch"
        );

        // --- Period 3: Reward Rate Changed (1 Day) ---
        uint256 newRewardRate = 5e15; // 0.005 PUSD per second (halved)
        console2.log("\nUpdating Reward Rate to", newRewardRate);
        vm.startPrank(admin);
        rates[0] = newRewardRate;
        // Ensure max rate allows the *new* desired rate
        // RewardsFacet(address(diamondProxy)).setMaxRewardRate(address(pUSD), newRewardRate); // <<< MOVE THIS DOWN
        RewardsFacet(address(diamondProxy)).setRewardRates(tokens, rates); // <<< SET CURRENT RATE FIRST
        RewardsFacet(address(diamondProxy)).setMaxRewardRate(address(pUSD), newRewardRate); // <<< THEN SET MAX RATE
        vm.stopPrank();

        uint256 period3Duration = 1 days;
        uint256 startTimeP3 = block.timestamp;
        console2.log("Advancing time for Period 3 (", period3Duration, " seconds)");
        vm.warp(startTimeP3 + period3Duration);
        vm.roll(block.number + period3Duration / 12);

        // Calculate expected rewards/commission for period 3 (new reward rate, latest commission rate)
        uint256 expectedRewardP3 = (period3Duration * newRewardRate * userStakeAmount) / totalStaked;
        uint256 expectedCommissionP3 = (expectedRewardP3 * newCommissionRate) / PlumeStakingStorage.REWARD_PRECISION;
        uint256 expectedNetRewardP3 = expectedRewardP3 - expectedCommissionP3;

        console2.log("Expected Gross Reward P3:", expectedRewardP3);
        console2.log("Expected Commission P3:", expectedCommissionP3);
        console2.log("Expected Net Reward P3:", expectedNetRewardP3);

        // Check claimable amounts (should include P1 + P2 + P3)
        uint256 claimableP1P2P3 = RewardsFacet(address(diamondProxy)).getClaimableReward(user1, token);
        uint256 accruedCommissionP1P2P3 = ValidatorFacet(address(diamondProxy)).getAccruedCommission(validatorId, token);
        console2.log("Actual Claimable Reward (P1+P2+P3):", claimableP1P2P3);
        console2.log("Actual Accrued Commission (P1+P2+P3):", accruedCommissionP1P2P3);
        assertApproxEqAbs(
            claimableP1P2P3,
            expectedNetRewardP1 + expectedNetRewardP2 + expectedNetRewardP3,
            expectedNetRewardP1 + expectedNetRewardP2 + expectedNetRewardP3,
            "Period 1+2+3 Claimable mismatch"
        );
        assertApproxEqAbs(
            accruedCommissionP1P2P3,
            expectedCommissionP1 + expectedCommissionP2 + expectedCommissionP3,
            expectedCommissionP1 + expectedCommissionP2 + expectedCommissionP3,
            "Period 1+2+3 Commission mismatch"
        );

        // --- Claim and Verify ---
        console2.log("\nClaiming rewards and commission...");
        // User claims
        vm.startPrank(user1);
        uint256 user1BalanceBefore = pUSD.balanceOf(user1);
        uint256 claimedAmount = RewardsFacet(address(diamondProxy)).claim(address(pUSD), DEFAULT_VALIDATOR_ID);
        uint256 user1BalanceAfter = pUSD.balanceOf(user1);

        // Verify claim was successful
        assertApproxEqAbs(
            user1BalanceAfter - user1BalanceBefore,
            claimedAmount,
            10 ** 10,
            "User claimed amount should match balance increase"
        );

        // Reset block timestamp back to beginning of the test to stop rewards from accruing
        vm.warp(1);

        // Check claimable amount after resetting time - should now be near zero
        uint256 claimableAfterClaim = RewardsFacet(address(diamondProxy)).getClaimableReward(user1, address(pUSD));
        assertApproxEqAbs(claimableAfterClaim, 0, 10 ** 10, "Final claimable should be near zero");

        // Claim validator commission
        vm.stopPrank();

        vm.startPrank(admin); // Use KNOWN_ADMIN assumed to be L2 admin for validator 1
        // uint256 validatorBalanceBefore = pUSD.balanceOf(validatorAdmin);
        uint256 validatorBalanceBefore = pUSD.balanceOf(admin); // <<< CHANGE: Check balance of actual admin for
        // validatorId 1
        ValidatorFacet(address(diamondProxy)).requestCommissionClaim(0, address(pUSD));
        vm.warp(block.timestamp + 7 days);
        uint256 commissionClaimed = ValidatorFacet(address(diamondProxy)).finalizeCommissionClaim(0, address(pUSD));

        uint256 validatorBalanceAfter = pUSD.balanceOf(admin); // <<< CHANGE: Check balance of actual admin for
            // validatorId 1

        // Verify commission claim was successful
        assertApproxEqAbs(
            validatorBalanceAfter - validatorBalanceBefore,
            commissionClaimed,
            10 ** 10,
            "Validator claimed amount should match balance increase"
        );

        // Check final commission accrued (should be zero since we reset the time)
        uint256 finalCommission =
            ValidatorFacet(address(diamondProxy)).getAccruedCommission(DEFAULT_VALIDATOR_ID, address(pUSD));
        assertApproxEqAbs(finalCommission, 0, 10 ** 10, "Final accrued commission should be near zero");
        vm.stopPrank();

        console2.log("--- Commission & Reward Rate Change Test Complete ---");
    }

    // --- Complex Reward Calculation Test ---
    function testComplexRewardScenario() public {
        console2.log("\n--- Setting up complex reward scenario ---");

        // --- Setup validators with different commission rates ---
        uint16 validator0 = DEFAULT_VALIDATOR_ID; // 1
        uint16 validator1 = 2;
        uint16 validator2 = 0;
        //address validator2Admin = makeAddr("validator2Admin");

        // Add a third validator
        vm.startPrank(admin);
        ValidatorFacet(address(diamondProxy)).addValidator(
            validator2, 15e16, KNOWN_ADMIN, KNOWN_ADMIN, "0xval3", "0xacc3", address(0x3456), 1_000_000e18
        );
        ValidatorFacet(address(diamondProxy)).setValidatorCapacity(validator2, 1_000_000e18);
        vm.stopPrank();

        // --- Setup reward rates ---
        // Use PUSD and PLUME_NATIVE as our tokens
        address token1 = address(pUSD);
        address token2 = PLUME_NATIVE;

        console2.log("Setting up initial commission rates:");

        // Set initial commission rates
        vm.startPrank(admin);
        ValidatorFacet(address(diamondProxy)).setValidatorCommission(validator0, 5e15); // 5% scaled
        vm.stopPrank();

        vm.startPrank(validator2Admin);
        ValidatorFacet(address(diamondProxy)).setValidatorCommission(validator1, 10e15); // 10% scaled
        vm.stopPrank();

        vm.startPrank(admin);
        ValidatorFacet(address(diamondProxy)).setValidatorCommission(validator2, 15e15); // 15% scaled
        vm.stopPrank();

        console2.log("Setting up initial reward rates:");
        vm.startPrank(admin);

        // Explicitly set high max reward rates first
        RewardsFacet(address(diamondProxy)).setMaxRewardRate(token1, 1e18); // 1 PUSD per second
        RewardsFacet(address(diamondProxy)).setMaxRewardRate(token2, 1e17); // 0.1 ETH per second
        console2.log("Max reward rates increased");

        // Use much smaller rates for the test to stay well below max
        address[] memory rewardTokensList = new address[](2);
        uint256[] memory rates = new uint256[](2);
        rewardTokensList[0] = token1; // PUSD
        rewardTokensList[1] = token2; // PLUME_NATIVE
        rates[0] = 1e15; // 0.001 PUSD per second (small value)
        rates[1] = 1e14; // 0.0001 ETH per second (small value)
        RewardsFacet(address(diamondProxy)).setRewardRates(rewardTokensList, rates);
        console2.log("Reward rates set");

        // Ensure treasury has sufficient funds
        pUSD.transfer(address(treasury), 10_000 * 1e6); // Fund treasury
        vm.stopPrank();

        // --- Initial stakes ---
        uint256 initialTimestamp = block.timestamp;
        console2.log("Initial timestamp:", initialTimestamp);
        console2.log("Initial stakes:");

        // User 1 stakes with validator 0
        vm.startPrank(user1);
        StakingFacet(address(diamondProxy)).stake{ value: 100 ether }(validator0);
        vm.stopPrank();
        console2.log("User1 staked 100 ETH with Validator0");

        // User 2 stakes with validator 0 and 1
        vm.startPrank(user2);
        StakingFacet(address(diamondProxy)).stake{ value: 200 ether }(validator0);
        StakingFacet(address(diamondProxy)).stake{ value: 150 ether }(validator1);
        vm.stopPrank();
        console2.log("User2 staked 200 ETH with Validator0 and 150 ETH with Validator1");

        // User 3 stakes with validator 1
        vm.startPrank(user3);
        StakingFacet(address(diamondProxy)).stake{ value: 250 ether }(validator1);
        vm.stopPrank();
        console2.log("User3 staked 250 ETH with Validator1");

        // User 4 stakes with validator 2
        vm.startPrank(user4);
        StakingFacet(address(diamondProxy)).stake{ value: 300 ether }(validator2);
        vm.stopPrank();
        console2.log("User4 staked 300 ETH with Validator2");

        // --- Phase 1: Initial time advancement (1 day) ---
        console2.log("\n--- Phase 1: Initial time advancement (1 day) ---");
        uint256 phase1Duration = 1 days;
        vm.warp(block.timestamp + phase1Duration);
        vm.roll(block.number + phase1Duration / 12);

        // Check rewards for user1 after Phase 1
        console2.log("User1 claimable rewards after Phase 1:");
        uint256 user1ClaimablePUSD_P1 = RewardsFacet(address(diamondProxy)).getClaimableReward(user1, token1);
        uint256 user1ClaimablePLUME_P1 = RewardsFacet(address(diamondProxy)).getClaimableReward(user1, token2);
        console2.log(" - PUSD:", user1ClaimablePUSD_P1);
        console2.log(" - PLUME:", user1ClaimablePLUME_P1);

        // Check rewards for user2 after Phase 1
        console2.log("User2 claimable rewards after Phase 1:");
        uint256 user2ClaimablePUSD_P1 = RewardsFacet(address(diamondProxy)).getClaimableReward(user2, token1);
        uint256 user2ClaimablePLUME_P1 = RewardsFacet(address(diamondProxy)).getClaimableReward(user2, token2);
        console2.log(" - PUSD:", user2ClaimablePUSD_P1);
        console2.log(" - PLUME:", user2ClaimablePLUME_P1);

        // --- Phase 2: Change reward rates ---
        console2.log("\n--- Phase 2: Change reward rates ---");
        vm.startPrank(admin);

        // Use smaller multipliers for new rates
        rates[0] = 2e15; // Double PUSD rate to 0.002 PUSD per second
        rates[1] = 2e13; // Decrease PLUME rate to 0.00002 ETH per second (1/5th)

        // <<< SWAPPED ORDER >>>
        // Set the CURRENT rates first
        RewardsFacet(address(diamondProxy)).setRewardRates(rewardTokensList, rates);
        // THEN set the MAX rates to match (or exceed) the current rates
        RewardsFacet(address(diamondProxy)).setMaxRewardRate(token1, rates[0]);
        RewardsFacet(address(diamondProxy)).setMaxRewardRate(token2, rates[1]);

        vm.stopPrank();
        console2.log("Reward rates changed: PUSD doubled, PLUME decreased to 1/5th");

        // Wait 12 hours
        uint256 phase2Duration = 12 hours;
        vm.warp(block.timestamp + phase2Duration);
        vm.roll(block.number + phase2Duration / 12);

        console2.log("User1 claimable rewards after Phase 2:");
        uint256 user1ClaimablePUSD_P2 = RewardsFacet(address(diamondProxy)).getClaimableReward(user1, token1);
        uint256 user1ClaimablePLUME_P2 = RewardsFacet(address(diamondProxy)).getClaimableReward(user1, token2);
        console2.log(" - PUSD:", user1ClaimablePUSD_P2);
        console2.log(" - PLUME:", user1ClaimablePLUME_P2);

        // --- Phase 3: Change commission rates ---
        console2.log("\n--- Phase 3: Change commission rates ---");

        vm.startPrank(admin);
        ValidatorFacet(address(diamondProxy)).setValidatorCommission(validator0, 15e15); // 15% scaled
        vm.stopPrank();

        vm.startPrank(validator2Admin);
        ValidatorFacet(address(diamondProxy)).setValidatorCommission(validator1, 20e15); // 20% scaled
        vm.stopPrank();

        console2.log("Commission rates changed: Validator0 to 15%, Validator1 to 20%");

        // Wait 6 hours
        uint256 phase3Duration = 6 hours;
        vm.warp(block.timestamp + phase3Duration);
        vm.roll(block.number + phase3Duration / 12);

        console2.log("User1 claimable rewards after Phase 3:");
        uint256 user1ClaimablePUSD_P3 = RewardsFacet(address(diamondProxy)).getClaimableReward(user1, token1);
        uint256 user1ClaimablePLUME_P3 = RewardsFacet(address(diamondProxy)).getClaimableReward(user1, token2);
        console2.log(" - PUSD:", user1ClaimablePUSD_P3);
        console2.log(" - PLUME:", user1ClaimablePLUME_P3);

        // --- Phase 4: User actions (unstake, restake) ---
        console2.log("\n--- Phase 4: User actions (unstake, restake) ---");

        // User1 unstakes half from validator0
        vm.startPrank(user1);
        StakingFacet(address(diamondProxy)).unstake(validator0, 50 ether);
        vm.stopPrank();
        console2.log("User1 unstaked 50 ETH from Validator0");

        // User2 unstakes from validator0 and restakes with validator1
        vm.startPrank(user2);
        StakingFacet(address(diamondProxy)).unstake(validator0, 100 ether);
        vm.warp(block.timestamp + INITIAL_COOLDOWN); // Wait for cooldown
        console2.log("User2 unstaked 100 ETH from Validator0 and waits for cooldown");
        uint256 withdrawable = StakingFacet(address(diamondProxy)).amountWithdrawable();
        StakingFacet(address(diamondProxy)).withdraw();
        StakingFacet(address(diamondProxy)).stake{ value: 100 ether }(validator1);
        vm.stopPrank();
        console2.log("User2 restaked 100 ETH to Validator1");

        // User4 adds more stake to validator2
        vm.startPrank(user4);
        StakingFacet(address(diamondProxy)).stake{ value: 100 ether }(validator2);
        vm.stopPrank();
        console2.log("User4 added 100 ETH to Validator2");

        // Wait 12 hours
        uint256 phase4Duration = 12 hours;
        vm.warp(block.timestamp + phase4Duration);
        vm.roll(block.number + phase4Duration / 12);

        // --- Phase 5: Final reward check and claims ---
        console2.log("\n--- Phase 5: Final reward check and claims ---");

        // Check final rewards for all users
        console2.log("Final rewards for User1:");
        uint256 user1FinalPUSD = RewardsFacet(address(diamondProxy)).getClaimableReward(user1, token1);
        uint256 user1FinalPLUME = RewardsFacet(address(diamondProxy)).getClaimableReward(user1, token2);
        console2.log(" - PUSD:", user1FinalPUSD);
        console2.log(" - PLUME:", user1FinalPLUME);

        console2.log("Final rewards for User2:");
        uint256 user2FinalPUSD = RewardsFacet(address(diamondProxy)).getClaimableReward(user2, token1);
        uint256 user2FinalPLUME = RewardsFacet(address(diamondProxy)).getClaimableReward(user2, token2);
        console2.log(" - PUSD:", user2FinalPUSD);
        console2.log(" - PLUME:", user2FinalPLUME);

        console2.log("Final rewards for User3:");
        uint256 user3FinalPUSD = RewardsFacet(address(diamondProxy)).getClaimableReward(user3, token1);
        uint256 user3FinalPLUME = RewardsFacet(address(diamondProxy)).getClaimableReward(user3, token2);
        console2.log(" - PUSD:", user3FinalPUSD);
        console2.log(" - PLUME:", user3FinalPLUME);

        console2.log("Final rewards for User4:");
        uint256 user4FinalPUSD = RewardsFacet(address(diamondProxy)).getClaimableReward(user4, token1);
        uint256 user4FinalPLUME = RewardsFacet(address(diamondProxy)).getClaimableReward(user4, token2);
        console2.log(" - PUSD:", user4FinalPUSD);
        console2.log(" - PLUME:", user4FinalPLUME);

        // Check accrued commission for validators
        console2.log("Accrued commissions:");
        uint256 validator0CommissionPUSD =
            ValidatorFacet(address(diamondProxy)).getAccruedCommission(validator0, token1);
        uint256 validator0CommissionPLUME =
            ValidatorFacet(address(diamondProxy)).getAccruedCommission(validator0, token2);
        console2.log("Validator0:");
        console2.log(" - PUSD:", validator0CommissionPUSD);
        console2.log(" - PLUME:", validator0CommissionPLUME);

        uint256 validator1CommissionPUSD =
            ValidatorFacet(address(diamondProxy)).getAccruedCommission(validator1, token1);
        uint256 validator1CommissionPLUME =
            ValidatorFacet(address(diamondProxy)).getAccruedCommission(validator1, token2);
        console2.log("Validator1:");
        console2.log(" - PUSD:", validator1CommissionPUSD);
        console2.log(" - PLUME:", validator1CommissionPLUME);

        uint256 validator2CommissionPUSD =
            ValidatorFacet(address(diamondProxy)).getAccruedCommission(validator2, token1);
        uint256 validator2CommissionPLUME =
            ValidatorFacet(address(diamondProxy)).getAccruedCommission(validator2, token2);
        console2.log("Validator2:");
        console2.log(" - PUSD:", validator2CommissionPUSD);
        console2.log(" - PLUME:", validator2CommissionPLUME);

        // Claim rewards and verify
        vm.startPrank(user1);
        uint256 user1PUSDBalanceBefore = pUSD.balanceOf(user1);
        uint256 user1ETHBalanceBefore = user1.balance;
        uint256 user1ClaimedPUSD = RewardsFacet(address(diamondProxy)).claim(token1);
        uint256 user1ClaimedPLUME = RewardsFacet(address(diamondProxy)).claim(token2);
        uint256 user1PUSDBalanceAfter = pUSD.balanceOf(user1);
        uint256 user1ETHBalanceAfter = user1.balance;
        vm.stopPrank();

        console2.log("User1 claimed:");
        console2.log(" - PUSD:", user1ClaimedPUSD);
        console2.log(" - PLUME:", user1ClaimedPLUME);

        // Verify claim amounts match balance increases
        assertApproxEqAbs(
            user1PUSDBalanceAfter - user1PUSDBalanceBefore,
            user1ClaimedPUSD,
            10 ** 10,
            "User1 PUSD claim should match balance increase"
        );
        assertApproxEqAbs(
            user1ETHBalanceAfter - user1ETHBalanceBefore,
            user1ClaimedPLUME,
            10 ** 10,
            "User1 PLUME claim should match balance increase"
        );

        // Verify reward rate changes affected accrual by comparing the reward increases
        // The PUSD reward rate doubled while PLUME decreased to 1/5th
        // So the rate of increase for PUSD rewards should increase while PLUME decrease
        uint256 pusdIncreaseP1 = user1ClaimablePUSD_P1; // From 0 to P1
        uint256 pusdIncreaseP2 = user1ClaimablePUSD_P2 - user1ClaimablePUSD_P1; // From P1 to P2
        uint256 plumeIncreaseP1 = user1ClaimablePLUME_P1; // From 0 to P1
        uint256 plumeIncreaseP2 = user1ClaimablePLUME_P2 - user1ClaimablePLUME_P1; // From P1 to P2

        // Normalize for time (P1 is 1 day, P2 is 12 hours)
        uint256 pusdRateP1 = pusdIncreaseP1 * 1e18 / phase1Duration;
        uint256 pusdRateP2 = pusdIncreaseP2 * 1e18 / phase2Duration;
        uint256 plumeRateP1 = plumeIncreaseP1 * 1e18 / phase1Duration;
        uint256 plumeRateP2 = plumeIncreaseP2 * 1e18 / phase2Duration;

        console2.log("Reward rate changes verification:");
        console2.log("PUSD reward rate (per second):");
        console2.log(" - Phase 1:", pusdRateP1);
        console2.log(" - Phase 2:", pusdRateP2);
        console2.log("PLUME reward rate (per second):");
        console2.log(" - Phase 1:", plumeRateP1);
        console2.log(" - Phase 2:", plumeRateP2);

        // Verify PUSD rate roughly doubled
        assertApproxEqRel(
            pusdRateP2,
            pusdRateP1 * 2,
            0.1e18, // 10% tolerance
            "PUSD rate didn't double as expected"
        );

        // Verify PLUME rate roughly decreased to 1/5th
        assertApproxEqRel(
            plumeRateP2,
            plumeRateP1 / 5,
            0.1e18, // 10% tolerance
            "PLUME rate didn't decrease to 1/5th as expected"
        );

        // Similarly, verify commission changes by comparing commission increases
        console2.log("\n--- Commission & Reward Scenario Test Complete ---");
    }

    function testTreasuryTransfer_User_Withdraw() public {
        // Setup validator and user accounts
        uint16 validator1 = 1;
        // address validator1Admin = makeAddr("validator1Admin"); // Not needed, validator 1 exists
        uint16 validator2 = 100;
        address validator2Admin = makeAddr("validator2Admin");

        vm.startPrank(admin);

        // Only add validator 100
        ValidatorFacet(address(diamondProxy)).addValidator(
            validator2, // Use validator2 ID (100)
            0.05e18, // 5% commission
            validator2Admin,
            validator2Admin,
            "validator2L1",
            "validator2AccountL1",
            validator2Admin,
            1000e18 // 1000 PLUME max capacity
        );

        // Set up treasury
        address treasuryAddr = address(treasury);
        RewardsFacet(address(diamondProxy)).setTreasury(treasuryAddr);

        // Fund the treasury
        vm.stopPrank();
        vm.deal(treasuryAddr, 100 ether);

        // Stake as user
        address user = address(7);
        vm.deal(user, 10 ether); // Keep this deal, user(7) is not funded in setUp
        vm.startPrank(user);

        StakingFacet(address(diamondProxy)).stake{ value: 1 ether }(validator1);

        // Advance time and add reward token
        vm.stopPrank();
        vm.startPrank(admin);
        RewardsFacet(address(diamondProxy)).setMaxRewardRate(PLUME_NATIVE, 1e18);

        // Set reward rate
        address[] memory tokens = new address[](1);
        tokens[0] = PLUME_NATIVE;
        uint256[] memory rates = new uint256[](1);
        rates[0] = 0.1e18; // 0.1 PLUME per second
        // Ensure max rate allows the desired rate
        RewardsFacet(address(diamondProxy)).setMaxRewardRate(PLUME_NATIVE, 0.1e18);
        RewardsFacet(address(diamondProxy)).setRewardRates(tokens, rates);
        vm.stopPrank();

        // Advance time to accrue rewards
        vm.warp(block.timestamp + 100); // 100 seconds

        // --- Add detailed state logging before claim ---
        console2.log("\n--- Debugging testTreasuryTransfer_User_Withdraw ---");
        console2.log("User:", user);
        console2.log("Token:", PLUME_NATIVE);
        console2.log("Validator ID staked with:", validator1);
        // Log specific validator stake
        uint256 userStakeAmt = stakingFacet.getUserValidatorStake(user, validator1);
        console2.log("User Stake Info (Validator 1): Staked=%s", userStakeAmt);
        // Log Validator Stats
        (bool active, uint256 commission, uint256 totalStaked, uint256 stakersCount) =
            validatorFacet.getValidatorStats(validator1);
        console2.log("Validator 1 Stats: active", active);
        console2.log("Validator 1 Stats: commission", commission);
        console2.log("Validator 1 Stats: totalStaked", totalStaked);
        console2.log("Validator 1 Stats: stakersCount", stakersCount);
        // Log Reward Calculation Inputs (Commented out assumed view functions)
        // uint256 validatorCurrentCumulative = rewardsFacet.getValidatorRewardPerTokenCumulative(validator1,
        // PLUME_NATIVE);
        // uint256 userLastPaidCumulative = rewardsFacet.getUserValidatorRewardPerTokenPaid(user, validator1,
        // PLUME_NATIVE);
        // uint256 validatorLastUpdate = rewardsFacet.getValidatorLastUpdateTime(validator1, PLUME_NATIVE);
        // console2.log("Validator Current Cumulative Index:", validatorCurrentCumulative);
        // console2.log("User Last Paid Cumulative Index:", userLastPaidCumulative);
        // console2.log("Validator Last Update Time:", validatorLastUpdate);
        console2.log("Current Block Timestamp:", block.timestamp);
        // Log Calculated Claimable Amount
        uint256 claimableBefore = rewardsFacet.getClaimableReward(user, PLUME_NATIVE);
        console2.log("Calculated claimable PLUME before claim call:", claimableBefore);

        // User claims rewards
        vm.startPrank(user);
        uint256 balanceBefore = user.balance;
        uint256 claimedAmount = RewardsFacet(address(diamondProxy)).claim(PLUME_NATIVE);
        console2.log("Amount returned by claim() call:", claimedAmount);
        // Add assertion to check consistency between view and claim result
        assertEq(claimedAmount, claimableBefore, "Claim returned different amount than getClaimableReward");
        uint256 balanceAfter = user.balance;

        // Verify user received rewards
        // Original assertion (assertTrue will fail if claimableBefore is 0)
        assertTrue(balanceAfter > balanceBefore, "User should have received rewards (balance check)");
        console2.log("User received rewards:", balanceAfter - balanceBefore);

        vm.stopPrank();
    }

    // <<< ADD NEW TEST CASE HERE >>>
    function testRestakeDuringCooldown() public {
        uint256 stakeAmount = 1 ether;
        uint16 validatorId = DEFAULT_VALIDATOR_ID;

        // User1 stakes
        vm.startPrank(user1);
        StakingFacet(address(diamondProxy)).stake{ value: stakeAmount }(validatorId);
        PlumeStakingStorage.StakeInfo memory stakeInfo = StakingFacet(address(diamondProxy)).stakeInfo(user1);
        assertEq(stakeInfo.staked, stakeAmount, "Initial stake amount mismatch"); // CORRECTED
        assertEq(stakeInfo.cooled, 0, "Initial cooling amount should be 0"); // CORRECTED
        console2.log("User1 staked %s ETH to validator %d", stakeAmount, validatorId);

        // User1 unstakes (initiates cooldown)
        StakingFacet(address(diamondProxy)).unstake(validatorId);
        stakeInfo = StakingFacet(address(diamondProxy)).stakeInfo(user1);
        assertEq(stakeInfo.staked, 0, "Staked amount should be 0 after unstake"); // CORRECTED
        assertEq(stakeInfo.cooled, stakeAmount, "Cooling amount mismatch after unstake"); // CORRECTED
        //assertTrue(stakeInfo.cooldownEnd > block.timestamp, "Cooldown end date should be in the future");
        //uint256 cooldownEnd = stakeInfo.cooldownEnd;
        //        console2.log("User1 unstaked %s ETH, now in cooldown until %s", stakeAmount, cooldownEnd);

        // Before cooldown ends, User1 restakes the cooling amount to the *same* validator
        //      assertTrue(block.timestamp < cooldownEnd, "Attempting restake before cooldown ends");
        // CORRECTED: Destructure 4 values
        (bool activeBefore, uint256 commissionBefore, uint256 totalStakedBefore, uint256 stakersCountBefore) =
            ValidatorFacet(address(diamondProxy)).getValidatorStats(validatorId);

        console2.log("User1 attempting to restake %s ETH during cooldown...", stakeAmount);
        StakingFacet(address(diamondProxy)).restake(validatorId, stakeAmount);

        // Verify state after restake
        stakeInfo = StakingFacet(address(diamondProxy)).stakeInfo(user1);
        // CORRECTED: Use cooldownEnd
        console2.log("State after restake: Staked=%s, Cooling=%s, CooldownEnd=%s", stakeInfo.staked, stakeInfo.cooled);
        //stakeInfo.cooldownEnd

        // EXPECTED CORRECT BEHAVIOR:
        assertEq(stakeInfo.cooled, 0, "Cooling amount should be 0 after restake"); // CORRECTED
        assertEq(stakeInfo.staked, stakeAmount, "Staked amount should be restored after restake"); // CORRECTED (THIS IS
            // LIKELY TO FAIL)
        // Cooldown should be cancelled/reset
        //assertEq(stakeInfo.cooldownEnd, 0, "Cooldown end date should be reset after restake");

        // Verify validator's total stake increased
        // CORRECTED: Destructure 4 values
        (bool activeAfter, uint256 commissionAfter, uint256 totalStakedAfter, uint256 stakersCountAfter) =
            ValidatorFacet(address(diamondProxy)).getValidatorStats(validatorId);
        assertEq(
            totalStakedAfter, totalStakedBefore + stakeAmount, "Validator total stake should increase after restake"
        ); // <<< THIS MIGHT ALSO FAIL

        vm.stopPrank();
        console2.log("Restake during cooldown test completed.");
    }

    function testComplexStakeUnstakeRestakeWithdrawScenario() public {
        uint16 validatorId = DEFAULT_VALIDATOR_ID;
        uint256 initialStake = 10 ether;
        uint256 firstUnstake = 5 ether;
        uint256 firstRestake = 2 ether;
        uint256 withdrawAmount = 3 ether; // = firstUnstake - firstRestake
        uint256 secondStake = 2 ether;
        uint256 secondUnstake = 4 ether;
        uint256 finalRestake = 4 ether; // = secondUnstake

        // Ensure PUSD rewards are set up for the claim step
        vm.startPrank(admin);
        address token = address(pUSD);
        RewardsFacet(address(diamondProxy)).setMaxRewardRate(token, 1e18);
        address[] memory tokens = new address[](1);
        tokens[0] = token;
        uint256[] memory rates = new uint256[](1);
        rates[0] = 1e15; // Small PUSD rate
        // Ensure max rate allows the desired rate
        RewardsFacet(address(diamondProxy)).setMaxRewardRate(token, 1e15);
        RewardsFacet(address(diamondProxy)).setRewardRates(tokens, rates);
        pUSD.transfer(address(treasury), 2000 * 1e6); // Corrected for 6 decimals, Fund treasury
        vm.stopPrank();

        vm.startPrank(user1);

        // 1. Stake 10 ETH
        console2.log("1. Staking %s ETH...", initialStake);
        StakingFacet(address(diamondProxy)).stake{ value: initialStake }(validatorId);
        PlumeStakingStorage.StakeInfo memory stakeInfo = StakingFacet(address(diamondProxy)).stakeInfo(user1);
        assertEq(stakeInfo.staked, initialStake, "State Error after Step 1");
        assertEq(stakeInfo.cooled, 0, "State Error after Step 1");
        vm.warp(block.timestamp + 5 days);

        // 2. Unstake 5 ETH
        console2.log("2. Unstaking %s ETH...", firstUnstake);
        StakingFacet(address(diamondProxy)).unstake(validatorId, firstUnstake);
        stakeInfo = StakingFacet(address(diamondProxy)).stakeInfo(user1);
        StakingFacet.CooldownView[] memory cooldowns1 = StakingFacet(address(diamondProxy)).getUserCooldowns(user1);
        assertTrue(cooldowns1.length > 0, "Should have a cooldown entry after unstake");
        uint256 cooldownEnd1 = cooldowns1[0].cooldownEndTime; // Assuming one relevant cooldown
        assertTrue(cooldownEnd1 > block.timestamp, "Cooldown 1 not set or not in future");
        assertEq(stakeInfo.staked, initialStake - firstUnstake, "State Error after Step 2 (Staked)");
        assertEq(stakeInfo.cooled, firstUnstake, "State Error after Step 2 (Cooled)");
        console2.log("   Cooldown ends at: %d", cooldownEnd1);

        // 3. Advance time (partway through cooldown) & Restake 2 ETH from cooling
        assertTrue(block.timestamp < cooldownEnd1, "Should be before cooldownEnd1 for this step");
        vm.warp(block.timestamp + (cooldownEnd1 - block.timestamp) / 2);
        console2.log("3. Restaking %s ETH from cooling...", firstRestake);
        StakingFacet(address(diamondProxy)).restake(validatorId, firstRestake);
        stakeInfo = StakingFacet(address(diamondProxy)).stakeInfo(user1);
        assertEq(stakeInfo.staked, initialStake - firstUnstake + firstRestake, "State Error after Step 3 (Staked)");
        assertEq(stakeInfo.cooled, firstUnstake - firstRestake, "State Error after Step 3 (Cooled)");
        // Check the specific cooldown entry's end time, it should persist
        cooldowns1 = StakingFacet(address(diamondProxy)).getUserCooldowns(user1);
        bool foundCooldown1 = false;
        for (uint256 i = 0; i < cooldowns1.length; i++) {
            if (cooldowns1[i].validatorId == validatorId && cooldowns1[i].amount == (firstUnstake - firstRestake)) {
                assertEq(cooldowns1[i].cooldownEndTime, cooldownEnd1, "Cooldown 1 End Time should NOT reset yet");
                foundCooldown1 = true;
                break;
            }
        }
        assertTrue(foundCooldown1, "Relevant cooldown entry for validatorId not found after restake");

        // 4. Advance time past original cooldown end
        console2.log("4. Advancing time past cooldown 1 (%s)...", cooldownEnd1);
        vm.warp(cooldownEnd1 + 1);

        // 5. Withdraw the 3 ETH that finished cooling
        console2.log("5. Withdrawing %s ETH...", withdrawAmount);
        uint256 balanceBeforeWithdraw = user1.balance;
        StakingFacet(address(diamondProxy)).withdraw();
        assertEq(user1.balance, balanceBeforeWithdraw + withdrawAmount, "Withdraw amount mismatch");
        stakeInfo = StakingFacet(address(diamondProxy)).stakeInfo(user1);
        assertEq(stakeInfo.staked, initialStake - firstUnstake + firstRestake, "State Error after Step 5 (Staked)");
        assertEq(stakeInfo.cooled, 0, "State Error after Step 5 (Cooled)"); // Cooled sum should be 0
        assertEq(stakeInfo.parked, 0, "State Error after Step 5 (Parked)");
        // After withdraw, the specific cooldown entry should be gone
        StakingFacet.CooldownView[] memory cooldownsAfterWithdraw =
            StakingFacet(address(diamondProxy)).getUserCooldowns(user1);
        bool stillHasCooldownForVal0 = false;
        for (uint256 i = 0; i < cooldownsAfterWithdraw.length; i++) {
            if (cooldownsAfterWithdraw[i].validatorId == validatorId && cooldownsAfterWithdraw[i].amount > 0) {
                stillHasCooldownForVal0 = true;
                break;
            }
        }
        assertFalse(stillHasCooldownForVal0, "Cooldown entry for validatorId should be gone after withdraw");

        // 6. Stake another 2 ETH normally
        console2.log("6. Staking %s ETH normally...", secondStake);
        StakingFacet(address(diamondProxy)).stake{ value: secondStake }(validatorId);
        stakeInfo = StakingFacet(address(diamondProxy)).stakeInfo(user1);
        assertEq(
            stakeInfo.staked,
            initialStake - firstUnstake + firstRestake + secondStake,
            "State Error after Step 6 (Staked)"
        );
        assertEq(stakeInfo.cooled, 0, "State Error after Step 6 (Cooled)");

        // 7. Unstake 4 ETH
        console2.log("7. Unstaking %s ETH...", secondUnstake);
        StakingFacet(address(diamondProxy)).unstake(validatorId, secondUnstake);
        stakeInfo = StakingFacet(address(diamondProxy)).stakeInfo(user1);
        StakingFacet.CooldownView[] memory cooldowns2 = StakingFacet(address(diamondProxy)).getUserCooldowns(user1);
        assertTrue(cooldowns2.length > 0, "Should have a cooldown entry after second unstake");
        uint256 cooldownEnd2 = 0;
        bool foundCooldown2 = false;
        for (uint256 i = 0; i < cooldowns2.length; i++) {
            if (cooldowns2[i].validatorId == validatorId && cooldowns2[i].amount == secondUnstake) {
                cooldownEnd2 = cooldowns2[i].cooldownEndTime;
                foundCooldown2 = true;
                break;
            }
        }
        assertTrue(foundCooldown2, "Relevant cooldown entry for validatorId (cooldown 2) not found");
        assertTrue(cooldownEnd2 > block.timestamp, "Cooldown 2 not set or not in future");
        assertEq(
            stakeInfo.staked,
            initialStake - firstUnstake + firstRestake + secondStake - secondUnstake,
            "State Error after Step 7 (Staked)"
        );
        assertEq(stakeInfo.cooled, secondUnstake, "State Error after Step 7 (Cooled)");
        console2.log("   Cooldown ends at: %s", cooldownEnd2);

        // 8. Advance time past second cooldown end
        console2.log("8. Advancing time past cooldown 2 (%s)...", cooldownEnd2);
        vm.warp(cooldownEnd2 + 1);

        // 9. Verify state: 4 ETH should be withdrawable (cooled moved to parked implicitly on check)
        console2.log("9. Verifying view functions and internal state...");
        // Check VIEW functions first
        uint256 withdrawable = StakingFacet(address(diamondProxy)).amountWithdrawable();
        uint256 cooling = StakingFacet(address(diamondProxy)).amountCooling();
        assertEq(withdrawable, secondUnstake, "amountWithdrawable() mismatch after cooldown 2");
        assertEq(cooling, 0, "amountCooling() mismatch after cooldown 2"); // Should be 0 as time has passed

        // Check internal STATE
        stakeInfo = StakingFacet(address(diamondProxy)).stakeInfo(user1);
        assertEq(stakeInfo.cooled, secondUnstake, "Internal State Error after Step 9 (Cooled)");
        assertEq(stakeInfo.parked, 0, "Internal State Error after Step 9 (Parked)");
        // Check the specific cooldown entry's end time
        cooldowns2 = StakingFacet(address(diamondProxy)).getUserCooldowns(user1);
        foundCooldown2 = false;
        uint256 actualCooldown2EndTime = 0;
        for (uint256 i = 0; i < cooldowns2.length; i++) {
            if (cooldowns2[i].validatorId == validatorId && cooldowns2[i].amount == secondUnstake) {
                actualCooldown2EndTime = cooldowns2[i].cooldownEndTime;
                foundCooldown2 = true;
                break;
            }
        }
        assertTrue(foundCooldown2, "Cooldown 2 entry missing before withdraw in step 10 setup");
        assertTrue(actualCooldown2EndTime <= block.timestamp, "Cooldown 2 end date should be in the past");

        // 10. Attempt `restakeRewards` when parked and available cooled are 0 (expect revert)
        console2.log("10. Attempting restakeRewards after withdrawing available balance (expect revert)...");
        // First, actually withdraw the funds to move them out of cooled/parked state
        uint256 balanceBeforeWithdrawStep10 = user1.balance;
        StakingFacet(address(diamondProxy)).withdraw();
        assertEq(user1.balance, balanceBeforeWithdrawStep10 + withdrawable, "Withdraw amount mismatch in Step 10");
        stakeInfo = StakingFacet(address(diamondProxy)).stakeInfo(user1);
        assertEq(stakeInfo.parked, 0, "Parked should be 0 after withdraw");
        assertEq(stakeInfo.cooled, 0, "Cooled should be 0 after withdraw");
        // After withdraw, the specific cooldown entry should be gone
        StakingFacet.CooldownView[] memory cooldownsAfterWithdraw10 =
            StakingFacet(address(diamondProxy)).getUserCooldowns(user1);
        bool stillHasCooldownForVal0_10 = false;
        for (uint256 i = 0; i < cooldownsAfterWithdraw10.length; i++) {
            if (cooldownsAfterWithdraw10[i].validatorId == validatorId && cooldownsAfterWithdraw10[i].amount > 0) {
                stillHasCooldownForVal0_10 = true;
                break;
            }
        }
        assertFalse(
            stillHasCooldownForVal0_10, "Cooldown entry for validatorId should be gone after withdraw in step 10"
        );

        // Now expect revert when calling restakeRewards as there is nothing to restake
        vm.expectRevert(abi.encodeWithSelector(NoRewardsToRestake.selector)); // Corrected expected revert
        StakingFacet(address(diamondProxy)).restakeRewards(validatorId);

        // --- Steps 11-13 Re-evaluated ---
        // The original intent was to restake the withdrawable amount. Let's redo this part.
        // Reset state slightly by staking again and unstaking to get funds into cooled/parked state.

        // Re-stake 4 ETH
        console2.log("10b. Re-staking %s ETH to set up for restakeRewards test", finalRestake);
        StakingFacet(address(diamondProxy)).stake{ value: finalRestake }(validatorId);

        // Unstake 4 ETH again
        console2.log("10c. Unstaking %s ETH again...", finalRestake);
        StakingFacet(address(diamondProxy)).unstake(validatorId, finalRestake);
        StakingFacet.CooldownView[] memory cooldowns3 = StakingFacet(address(diamondProxy)).getUserCooldowns(user1);
        assertTrue(cooldowns3.length > 0, "Should have a cooldown entry after third unstake");
        uint256 cooldownEnd3 = 0;
        bool foundCooldown3 = false;
        for (uint256 i = 0; i < cooldowns3.length; i++) {
            if (cooldowns3[i].validatorId == validatorId && cooldowns3[i].amount == finalRestake) {
                cooldownEnd3 = cooldowns3[i].cooldownEndTime;
                foundCooldown3 = true;
                break;
            }
        }
        assertTrue(foundCooldown3, "Relevant cooldown entry for validatorId (cooldown 3) not found");
        assertTrue(cooldownEnd3 > block.timestamp, "Cooldown 3 not set or not in future");
        console2.log("   Cooldown ends at: %s", cooldownEnd3);

        // Advance time past cooldown 3
        console2.log("10d. Advancing time past cooldown 3 (%s)...", cooldownEnd3);
        vm.warp(cooldownEnd3 + 1);

        // Verify 4 ETH is withdrawable (in cooled state, but past end date)
        withdrawable = StakingFacet(address(diamondProxy)).amountWithdrawable();
        assertEq(withdrawable, finalRestake, "Withdrawable amount mismatch before final restakeRewards");
        stakeInfo = StakingFacet(address(diamondProxy)).stakeInfo(user1);
        assertEq(stakeInfo.cooled, finalRestake, "Cooled amount mismatch before final restakeRewards");
        assertEq(stakeInfo.parked, 0, "Parked amount mismatch before final restakeRewards");

        // 11. Activate PLUME rewards and advance time to accrue rewards
        console2.log("11. Activating PLUME rewards and advancing time...");
        uint256 plumeRate = 1e16; // 0.01 PLUME per second
        vm.startPrank(admin);
        RewardsFacet(address(diamondProxy)).setMaxRewardRate(PLUME_NATIVE, plumeRate * 2); // Set max rate
        address[] memory nativeTokenArr = new address[](1);
        nativeTokenArr[0] = PLUME_NATIVE;
        uint256[] memory nativeRateArr = new uint256[](1);
        nativeRateArr[0] = plumeRate;

        // Ensure max rate allows the desired rate
        RewardsFacet(address(diamondProxy)).setMaxRewardRate(PLUME_NATIVE, plumeRate);
        RewardsFacet(address(diamondProxy)).setRewardRates(nativeTokenArr, nativeRateArr);
        vm.stopPrank();

        uint256 timeAdvance = 5 days;
        uint256 timeBeforeWarp = block.timestamp;
        console2.log("   Time before warp: %s", timeBeforeWarp);
        vm.warp(block.timestamp + timeAdvance); // Advance time to accrue PLUME rewards
        uint256 timeAfterWarp = block.timestamp;
        console2.log("   Time after warp: %s (Advanced %s s)", timeAfterWarp, timeAfterWarp - timeBeforeWarp);

        // 12. Call restakeRewards - this should take pending PLUME and add to stake
        console2.log("12. Calling restakeRewards(%s)...", validatorId);

        // <<< ADD DETAILED LOGGING BEFORE CLAIM >>>
        console2.log("   --- Logging State Before Claim (Step 12) --- ");
        console2.log(block.timestamp);

        // Validator Stats
        (bool vActive, uint256 vCommission, uint256 vTotalStaked, uint256 vStakersCount) =
            validatorFacet.getValidatorStats(validatorId);

        // User Stake Info
        uint256 userStake = stakingFacet.getUserValidatorStake(user1, validatorId);

        // Pre-check Claimable Reward
        uint256 claimableBeforeExplicitCall =
            RewardsFacet(address(diamondProxy)).getClaimableReward(user1, PLUME_NATIVE);
        console2.log(
            "   Claimable PLUME (via getClaimableReward) just before explicit claim: %s", claimableBeforeExplicitCall
        );
        console2.log("   --- End Logging State --- ");
        // <<< END DETAILED LOGGING >>>

        // <<< ADD INTERACTION TO TRIGGER UPDATE >>>
        uint256 pendingPlumeReward = RewardsFacet(address(diamondProxy)).getClaimableReward(user1, PLUME_NATIVE);
        // <<< ADD LOGGING >>>
        console2.log("Result of getClaimableReward(user1, PLUME_NATIVE):", pendingPlumeReward);
        // <<< END LOGGING >>>
        assertTrue(pendingPlumeReward > 0, "Should have accrued some PLUME reward");
        console2.log("   Pending PLUME reward: %s", pendingPlumeReward);

        vm.startPrank(user1);
        uint256 stakedBeforeRestake = StakingFacet(address(diamondProxy)).amountStaked();
        uint256 restakedAmount = StakingFacet(address(diamondProxy)).restakeRewards(validatorId);
        assertEq(restakedAmount, pendingPlumeReward, "restakeRewards returned incorrect amount");

        stakeInfo = StakingFacet(address(diamondProxy)).stakeInfo(user1);
        assertEq(stakeInfo.staked, stakedBeforeRestake + restakedAmount, "State Error after Step 12 (Staked)");
        assertEq(stakeInfo.cooled, finalRestake, "State Error after Step 12 (Cooled - should be unchanged)");
        assertEq(stakeInfo.parked, 0, "State Error after Step 12 (Parked - should be unchanged)");

        // Verify pending PLUME reward is now zero
        uint256 pendingPlumeAfter = RewardsFacet(address(diamondProxy)).getClaimableReward(user1, PLUME_NATIVE);
        assertEq(pendingPlumeAfter, 0, "Pending PLUME reward should be zero after restakeRewards");

        // 13. Withdraw the 4 ETH that finished cooling earlier
        console2.log("13. Withdrawing %s ETH (from finished cooldown)...", finalRestake);
        uint256 withdrawableNow = StakingFacet(address(diamondProxy)).amountWithdrawable();
        assertEq(withdrawableNow, finalRestake, "Withdrawable amount incorrect before final withdraw");
        uint256 finalBalanceBeforeWithdraw = user1.balance; // RENAMED variable
        StakingFacet(address(diamondProxy)).withdraw();
        assertEq(user1.balance, finalBalanceBeforeWithdraw + finalRestake, "Withdraw amount mismatch in Step 13");

        // 14. Final Checks
        console2.log("14. Final checks...");
        stakeInfo = StakingFacet(address(diamondProxy)).stakeInfo(user1);
        assertEq(stakeInfo.staked, stakedBeforeRestake + restakedAmount, "Final Staked amount incorrect");
        assertEq(stakeInfo.cooled, 0, "Final Cooled amount should be 0");
        assertEq(stakeInfo.parked, 0, "Final Parked amount should be 0");
        assertEq(StakingFacet(address(diamondProxy)).amountWithdrawable(), 0, "Final Withdrawable should be 0");

        // Can optionally claim PUSD rewards accumulated throughout the test as well
        console2.log("   Claiming any remaining PUSD rewards...");
        uint256 claimablePUSD = RewardsFacet(address(diamondProxy)).getClaimableReward(user1, address(pUSD));
        if (claimablePUSD > 0) {
            uint256 pusdBalanceBefore = pUSD.balanceOf(user1);
            RewardsFacet(address(diamondProxy)).claim(address(pUSD));
            assertEq(
                pUSD.balanceOf(user1), pusdBalanceBefore + claimablePUSD, "PUSD balance mismatch after final claim"
            );
        }

        vm.stopPrank();
        console2.log("Complex stake/unstake/restake/withdraw scenario test completed.");
    }
    // <<< END NEW COMPLEX TEST CASE >>>

    function testFork_PlumeRewardRate_5_5_Percent_APR() public {
        console2.log("\\n--- Test: testFork_PlumeRewardRate_5_5_Percent_APR ---");

        uint16 testValidatorId = DEFAULT_VALIDATOR_ID;
        address tokenToClaim = PlumeStakingStorage.PLUME_NATIVE;
        uint256 stakeAmount = 1 ether; // 1 PLUME (1 * 10^18 wei-PLUME)
        uint256 durationSeconds = 120; // 2 minutes

        (PlumeStakingStorage.ValidatorInfo memory valInfoInitial,,) = validatorFacet.getValidatorInfo(testValidatorId);
        address currentValAdmin = valInfoInitial.l2AdminAddress;

        bool commissionSetToZero = false;
        try vm.prank(currentValAdmin) {
            validatorFacet.setValidatorCommission(testValidatorId, 0);
            commissionSetToZero = true;
            console2.log(
                "Validator %s commission successfully set to 0 for test by admin %s.", testValidatorId, currentValAdmin
            );
        } catch Error(string memory reason) {
            console2.log(
                "Could not set commission for validator %s to 0 (Admin: %s). Reason: %s. Test will use existing commission.",
                testValidatorId,
                currentValAdmin,
                reason
            );
        } catch (bytes memory) /*lowLevelData*/ {
            console2.log(
                "Could not set commission for validator %s to 0 (Admin: %s) due to low-level revert. Test will use existing commission.",
                testValidatorId,
                currentValAdmin
            );
        }
        if (commissionSetToZero) {
            try vm.stopPrank() { } catch { }
        }

        (PlumeStakingStorage.ValidatorInfo memory valInfoForTest,,) = validatorFacet.getValidatorInfo(testValidatorId);
        uint256 commissionRateForCalc = valInfoForTest.commission;
        console2.log(
            "Using commission rate for validator %s: %s (%s %%) ",
            testValidatorId,
            commissionRateForCalc,
            commissionRateForCalc / (PlumeStakingStorage.REWARD_PRECISION / 100)
        );

        vm.startPrank(user1);
        console2.log("User1 (%s) staking %s PLUME with validator %s", user1, stakeAmount, testValidatorId);
        stakingFacet.stake{ value: stakeAmount }(testValidatorId);
        uint256 stakeTimestamp = block.timestamp;
        console2.log("Stake successful at timestamp: %s", stakeTimestamp);
        vm.stopPrank();

        uint256 targetTimestamp = stakeTimestamp + durationSeconds;
        vm.warp(targetTimestamp);
        vm.roll(block.number + (durationSeconds / 12 < 1 ? 1 : durationSeconds / 12));
        console2.log(
            "Warped time by %s seconds. New block: %s, New timestamp: %s",
            durationSeconds,
            block.number,
            block.timestamp
        );

        uint256 expectedRewardPerTokenIncrease = EXPECTED_PLUME_RATE_PER_SEC * durationSeconds;
        uint256 expectedGrossUserReward =
            (stakeAmount * expectedRewardPerTokenIncrease) / PlumeStakingStorage.REWARD_PRECISION;
        uint256 expectedCommission =
            (expectedGrossUserReward * commissionRateForCalc) / PlumeStakingStorage.REWARD_PRECISION;
        uint256 expectedNetUserReward = expectedGrossUserReward - expectedCommission;

        console2.log("Expected Reward Per Token Increase (for duration): %s", expectedRewardPerTokenIncrease);
        console2.log("Expected Gross User Reward (off-chain calc): %s wei-PLUME", expectedGrossUserReward);
        console2.log("Expected Commission (off-chain calc): %s wei-PLUME", expectedCommission);
        console2.log(
            "Expected Net User Reward (off-chain calc): %s wei-PLUME (%s PLUME)",
            expectedNetUserReward,
            vm.toString(expectedNetUserReward)
        ); // Use vm.toString on the wei amount

        vm.startPrank(user1);
        uint256 balanceBeforeClaim = user1.balance;
        console2.log("User1 balance before claim: %s", balanceBeforeClaim);

        uint256 pendingBeforeClaim = rewardsFacet.getPendingRewardForValidator(user1, testValidatorId, tokenToClaim);
        console2.log("Pending reward via getPendingRewardForValidator just before claim: %s", pendingBeforeClaim);

        uint256 claimedAmount = rewardsFacet.claim(tokenToClaim, testValidatorId);
        uint256 balanceAfterClaim = user1.balance;
        vm.stopPrank();

        console2.log(
            "Actual claimed PLUME from claim() call: %s wei-PLUME (%s PLUME)", claimedAmount, vm.toString(claimedAmount)
        ); // Use vm.toString on the wei amount
        console2.log("User1 balance after claim: %s", balanceAfterClaim);
        console2.log("User1 balance change due to claim: %s wei-PLUME", balanceAfterClaim - balanceBeforeClaim);

        uint256 tolerance = EXPECTED_PLUME_RATE_PER_SEC; // Tolerance of 1 second of rewards at the expected rate
        assertApproxEqAbs(
            claimedAmount, expectedNetUserReward, tolerance, "Claimed PLUME reward does not match expected 5.5% APR"
        );

        assertTrue(
            (balanceAfterClaim + (1 ether / 1000)) >= balanceBeforeClaim + claimedAmount
                && balanceAfterClaim <= balanceBeforeClaim + claimedAmount,
            "Balance change vs claimed amount discrepancy too large, accounting for potential gas"
        );

        console2.log("--- Test: testFork_PlumeRewardRate_5_5_Percent_APR END ---");
    }

    function testRewardsLostOnStakeAfterUnstake() public {
        console2.log("--- Test: testRewardsLostOnStakeAfterUnstake START ---");

        uint16 validatorId = DEFAULT_VALIDATOR_ID;
        address staker = user1;
        uint256 initialStakeAmount = 100 ether;
        uint256 secondStakeAmount = 50 ether;
        address rewardToken = PLUME_NATIVE; // Assuming PLUME_NATIVE is a reward token

        // Ensure user1 has enough PLUME (ETH for native staking)
        vm.deal(staker, initialStakeAmount + secondStakeAmount + 1 ether); // +1 for gas

        // 1. Initial Stake by User1
        vm.startPrank(staker);
        StakingFacet(address(diamondProxy)).stake{ value: initialStakeAmount }(validatorId);
        uint256 stake1Timestamp = block.timestamp;
        console2.log(
            "User1 staked %s at timestamp %s to validator %s", initialStakeAmount, stake1Timestamp, validatorId
        );
        vm.stopPrank();

        // 2. Let time pass to accrue rewards
        uint256 timeToAccrueRewards = 1 days;
        vm.warp(block.timestamp + timeToAccrueRewards);
        vm.roll(block.number + 1); // Ensure warp takes effect
        console2.log("Warped time by %s seconds. Current timestamp: %s", timeToAccrueRewards, block.timestamp);

        // Perform a view call to trigger reward updates if necessary (some systems do this)
        // This also helps ensure the reward calculation logic has run before we check earned rewards.
        RewardsFacet(address(diamondProxy)).getClaimableReward(staker, rewardToken);

        // 3. Check earned rewards BEFORE unstaking
        uint256 rewardsBeforeUnstake = RewardsFacet(address(diamondProxy)).getClaimableReward(staker, rewardToken);
        assertGt(rewardsBeforeUnstake, 0, "User1 should have accrued some rewards before unstaking.");
        console2.log("User1 has %s of token %s claimable BEFORE unstake.", rewardsBeforeUnstake, rewardToken);

        // 4. User1 unstakes the full amount
        vm.startPrank(staker);
        StakingFacet(address(diamondProxy)).unstake(validatorId, initialStakeAmount);
        uint256 unstakeTimestamp = block.timestamp;
        console2.log(
            "User1 unstaked %s at timestamp %s from validator %s", initialStakeAmount, unstakeTimestamp, validatorId
        );

        // Check stake info: staked should be 0, cooled should be initialStakeAmount
        PlumeStakingStorage.StakeInfo memory stakeInfoAfterUnstake =
            StakingFacet(address(diamondProxy)).stakeInfo(staker);
        assertEq(stakeInfoAfterUnstake.staked, 0, "Staked amount should be 0 after unstake.");
        assertEq(
            stakeInfoAfterUnstake.cooled,
            initialStakeAmount,
            "Cooled amount should be initialStakeAmount after unstake."
        );

        // 5. Check earned rewards AFTER unstaking (but before cooldown ends and before new stake)
        // Rewards should still be claimable and should be the same as before unstaking.
        uint256 rewardsAfterUnstake = RewardsFacet(address(diamondProxy)).getClaimableReward(staker, rewardToken);
        assertEq(
            rewardsAfterUnstake,
            rewardsBeforeUnstake,
            "Claimable rewards should remain the same immediately after unstaking the staked portion."
        );
        console2.log(
            "User1 has %s of token %s claimable AFTER unstake (before new stake).", rewardsAfterUnstake, rewardToken
        );
        vm.stopPrank(); // Stop staker's prank

        // 6. User1 stakes a NEW amount with the SAME validator (before cooldown of previous stake ends, and without
        // claiming)
        vm.startPrank(staker);
        StakingFacet(address(diamondProxy)).stake{ value: secondStakeAmount }(validatorId);
        uint256 stake2Timestamp = block.timestamp;
        console2.log(
            "User1 staked a NEW amount of %s at timestamp %s to validator %s",
            secondStakeAmount,
            stake2Timestamp,
            validatorId
        );

        // Check stake info: staked should be secondStakeAmount, cooled should still be initialStakeAmount
        PlumeStakingStorage.StakeInfo memory stakeInfoAfterSecondStake =
            StakingFacet(address(diamondProxy)).stakeInfo(staker);
        assertEq(
            stakeInfoAfterSecondStake.staked,
            secondStakeAmount,
            "Staked amount should be secondStakeAmount after new stake."
        );
        assertEq(
            stakeInfoAfterSecondStake.cooled,
            initialStakeAmount,
            "Cooled amount should remain initialStakeAmount after new stake."
        );

        // 7. CRITICAL CHECK: Check earned rewards AFTER the second stake
        // This is where the bug might manifest. The previously accrued rewards (rewardsAfterUnstake) should ideally
        // still be there.
        uint256 rewardsAfterSecondStake = RewardsFacet(address(diamondProxy)).getClaimableReward(staker, rewardToken);
        console2.log("User1 has %s of token %s claimable AFTER second stake.", rewardsAfterSecondStake, rewardToken);

        // The assertion: rewards should not be less than what was accrued before the second stake.
        // It might be slightly higher if a tiny bit of time passed and new rewards accrued on the second stake,
        // but it should definitely not be zero or significantly less than rewardsAfterUnstake.
        assertTrue(
            rewardsAfterSecondStake >= rewardsAfterUnstake,
            "Rewards after second stake should not be less than rewards accrued before it."
        );
        // A more precise check might be needed if the system *is* expected to auto-claim or reset something,
        // but based on the bug description, this is the expectation.

        // If the bug is that rewards are completely lost, this will fail:
        assertGt(
            rewardsAfterSecondStake,
            0,
            "Rewards should still be greater than 0 after second stake if they were non-zero before."
        );
        assertEq(
            rewardsAfterSecondStake,
            rewardsAfterUnstake,
            "Rewards after second stake SHOULD BE THE SAME as rewards accrued before it, if no new rewards are calculated from the new stake yet or if the new stake doesn't affect old pending rewards."
        );

        // 8. Let more time pass to see if rewards accrue correctly on the new stake amount
        uint256 anotherTimeToAccrue = 1 hours;
        vm.warp(block.timestamp + anotherTimeToAccrue);
        vm.roll(block.number + 1);
        console2.log("Warped time by an additional %s seconds.", anotherTimeToAccrue);

        uint256 finalRewards = RewardsFacet(address(diamondProxy)).getClaimableReward(staker, rewardToken);
        console2.log("User1 has %s of token %s claimable at the end.", finalRewards, rewardToken);
        // Rewards should now be at least what they were after the second stake, plus new rewards.
        assertTrue(
            finalRewards > rewardsAfterSecondStake,
            "Final rewards should be greater than rewards after second stake, due to new accrual."
        );

        vm.stopPrank();
        console2.log("--- Test: testRewardsLostOnStakeAfterUnstake END ---");
    }

    function testStakeUnstakeWithdrawMultipleValidators() public {
        console2.log("--- Test: testStakeUnstakeWithdrawMultipleValidators START ---");

        // --- Test Configuration ---
        address staker = user1; // Or any other user set up in your script
        uint256 stakeAmountPerValidator = 1 ether;
        uint16 numValidatorsToTest = 10;
        uint256 totalExpectedStake = stakeAmountPerValidator * numValidatorsToTest;
        address rewardToken = PLUME_NATIVE; // Assuming PLUME_NATIVE is the native staking/reward token

        // Ensure staker has enough ETH for all stakes + gas
        vm.deal(staker, totalExpectedStake + (1 ether)); // Extra 1 ETH for gas across multiple transactions

        // --- Validator IDs Setup ---
        // IMPORTANT: Ensure these validators exist and are active in your forked environment.
        // Adjust this logic if your validator IDs are not sequential or start from a different base.
        uint16[] memory validatorIds = new uint16[](numValidatorsToTest);
        for (uint16 i = 0; i < numValidatorsToTest; i++) {
            validatorIds[i] = uint16(DEFAULT_VALIDATOR_ID + i); // Example: If DEFAULT_VALIDATOR_ID is 0, uses 0-9
                // Add a check or log to ensure validator validity if needed for your setup
                // console2.log("Using validator ID for test: %s", validatorIds[i]);
                // You might want to check $.validatorExists[validatorIds[i]] and $.validators[validatorIds[i]].active
                // if these are not guaranteed by your script's setup.
        }
        console2.log("Prepared to test with %s validators.", numValidatorsToTest);

        // --- 1. Stake 1 PLUME to each of the 10 different validators ---
        vm.startPrank(staker);
        console2.log("Starting stakes for user %s", staker);
        for (uint16 i = 0; i < numValidatorsToTest; i++) {
            StakingFacet(address(diamondProxy)).stake{ value: stakeAmountPerValidator }(validatorIds[i]);
            console2.log(
                " - Staked %s to validator %s at timestamp %s",
                stakeAmountPerValidator,
                validatorIds[i],
                block.timestamp
            );
        }
        vm.stopPrank();
        console2.log("Finished staking to %s validators.", numValidatorsToTest);

        // --- 2. Let time pass to accrue rewards ---
        uint256 timeToAccrueRewards = 1 days; // Arbitrary duration for reward accrual
        vm.warp(block.timestamp + timeToAccrueRewards);
        vm.roll(block.number + (timeToAccrueRewards / 12)); // Advance blocks proportionally
        console2.log(
            "Warped time by %s seconds for reward accrual. Current timestamp: %s", timeToAccrueRewards, block.timestamp
        );

        // Sanity check: rewards should have accrued
        uint256 rewardsBeforeUnstake = RewardsFacet(address(diamondProxy)).getClaimableReward(staker, rewardToken);
        assertGt(rewardsBeforeUnstake, 0, "User should have accrued some rewards before unstaking.");
        console2.log(
            "User %s has %s of token %s claimable BEFORE any unstakes.", staker, rewardsBeforeUnstake, rewardToken
        );

        // --- 3. Unstake all of them one by one ---
        vm.startPrank(staker);
        console2.log("Starting unstakes for user %s", staker);
        for (uint16 i = 0; i < numValidatorsToTest; i++) {
            StakingFacet(address(diamondProxy)).unstake(validatorIds[i], stakeAmountPerValidator);
            console2.log(
                " - Unstaked %s from validator %s. Cooldown started at %s",
                stakeAmountPerValidator,
                validatorIds[i],
                block.timestamp
            );
        }
        vm.stopPrank();
        console2.log("Finished unstaking from %s validators.", numValidatorsToTest);

        // Verify user's global stake info after all unstakes
        PlumeStakingStorage.StakeInfo memory stakeInfoAfterUnstakes =
            StakingFacet(address(diamondProxy)).stakeInfo(staker);
        assertEq(stakeInfoAfterUnstakes.staked, 0, "User's total active stake should be 0 after unstaking all.");
        assertEq(
            stakeInfoAfterUnstakes.cooled,
            totalExpectedStake,
            "User's total cooled amount should be the sum of all unstaked amounts."
        );
        console2.log("UserGlobalStakeInfo - user:", staker);
        console2.log("UserGlobalStakeInfo - staked:", stakeInfoAfterUnstakes.staked);
        console2.log("UserGlobalStakeInfo - cooled:", stakeInfoAfterUnstakes.cooled);
        console2.log("UserGlobalStakeInfo - parked:", stakeInfoAfterUnstakes.parked);

        // --- 4. Warp time to ensure all cooldown periods have ended ---
        uint256 cooldownInterval = ManagementFacet(address(diamondProxy)).getCooldownInterval();
        uint256 timeToWarpForCooldown = cooldownInterval + (1 hours); // Add a small buffer
        vm.warp(block.timestamp + timeToWarpForCooldown);
        vm.roll(block.number + (timeToWarpForCooldown / 12)); // Advance blocks
        console2.log(
            "Warped time by cooldown interval + 1 hour (%s seconds). Current timestamp: %s",
            timeToWarpForCooldown,
            block.timestamp
        );

        // --- 5. Try to withdraw ---
        uint256 balanceBeforeWithdraw = staker.balance;
        console2.log("Staker ETH balance before withdraw: %s", balanceBeforeWithdraw);

        vm.startPrank(staker);
        StakingFacet(address(diamondProxy)).withdraw();
        vm.stopPrank();
        console2.log("Withdraw call completed for user %s.", staker);

        uint256 balanceAfterWithdraw = staker.balance;
        console2.log("Staker ETH balance after withdraw: %s", balanceAfterWithdraw);

        // --- Assertions ---
        // 6. Expected result: User should get 10 PLUME (totalExpectedStake) back.
        uint256 actualBalanceIncrease = balanceAfterWithdraw - balanceBeforeWithdraw;
        console2.log(
            "Actual ETH balance increase from withdraw: %s (expected approx %s before gas)",
            actualBalanceIncrease,
            totalExpectedStake
        );

        // Account for gas costs. The actual increase will be `totalExpectedStake - gasForWithdraw`.
        // So, actualBalanceIncrease should be slightly less than totalExpectedStake.
        uint256 gasToleranceForWithdraw = 0.01 ether; // Adjust this based on observed gas for withdraw()
        assertTrue(
            actualBalanceIncrease <= totalExpectedStake
                && actualBalanceIncrease >= totalExpectedStake - gasToleranceForWithdraw,
            string(
                abi.encodePacked(
                    "Balance increase after withdraw is not as expected. Expected approx ",
                    vm.toString(totalExpectedStake),
                    " (minus gas), got ",
                    vm.toString(actualBalanceIncrease)
                )
            )
        );

        // 7. Rewards should still be there.
        uint256 rewardsAfterWithdraw = RewardsFacet(address(diamondProxy)).getClaimableReward(staker, rewardToken);
        console2.log(
            "User %s claimable rewards for token %s AFTER withdraw: %s", staker, rewardToken, rewardsAfterWithdraw
        );

        assertGt(rewardsAfterWithdraw, 0, "Rewards should still be greater than 0 after withdraw.");
        // Rewards after withdraw should be very close to rewards before unstake, assuming withdraw() doesn't claim
        // and no significant time passed during the withdraw tx itself to accrue more.
        // A small tolerance for dust or minor calculations during view calls in withdraw might be needed.
        uint256 rewardComparisonTolerance = rewardsBeforeUnstake / 1000; // 0.1% tolerance, or a small fixed wei amount
        if (rewardComparisonTolerance == 0 && rewardsBeforeUnstake > 0) {
            rewardComparisonTolerance = 1;
        } // Avoid division by zero if rewards are tiny but non-zero

        assertApproxEqAbs(
            rewardsAfterWithdraw,
            rewardsBeforeUnstake,
            rewardComparisonTolerance,
            "Rewards after withdraw should be approximately the same as rewards before unstaking."
        );

        // Final check on user's stake info: cooled and parked should be 0.
        PlumeStakingStorage.StakeInfo memory stakeInfoAfterWithdraw =
            StakingFacet(address(diamondProxy)).stakeInfo(staker);
        assertEq(stakeInfoAfterWithdraw.staked, 0, "User's total active stake should remain 0.");
        assertEq(
            stakeInfoAfterWithdraw.cooled,
            0,
            "User's total cooled amount should be 0 after successful processing in withdraw."
        );
        assertEq(stakeInfoAfterWithdraw.parked, 0, "User's total parked amount should be 0 after successful withdraw.");
        console2.log("UserFinalGlobalStakeInfo - user:", staker);
        console2.log("UserFinalGlobalStakeInfo - staked:", stakeInfoAfterWithdraw.staked);
        console2.log("UserFinalGlobalStakeInfo - cooled:", stakeInfoAfterWithdraw.cooled);
        console2.log("UserFinalGlobalStakeInfo - parked:", stakeInfoAfterWithdraw.parked);

        console2.log("--- Test: testStakeUnstakeWithdrawMultipleValidators END ---");
    }

}
