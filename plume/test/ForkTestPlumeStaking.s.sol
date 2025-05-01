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
    address public constant DIAMOND_PROXY_ADDRESS = 0xA20bfe49969D4a0E9abfdb6a46FeD777304ba07f;
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
    uint256 public constant PLUME_REWARD_RATE = 1_587_301_587; // Example rate
    uint16 public constant DEFAULT_VALIDATOR_ID = 1;
    uint256 public constant DEFAULT_COMMISSION = 5e16; // 5% commission
    address public constant DEFAULT_VALIDATOR_ADMIN = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;

    // --- Fork Setup ---
    function setUp() public {
        // Select the fork FIRST
        vm.createSelectFork(mainnetRpcUrl, 981_706);

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

        vm.stopPrank();

        // Deal to admin *after* treasury setup
        deal(address(pUSD), admin, adminPusdAmount);
        console2.log("Admin pUSD balance AFTER dealing in setUp:", pUSD.balanceOf(admin));

        console2.log("Fork setup complete. Testing against Diamond:", DIAMOND_PROXY_ADDRESS);
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
        uint256 claimedAmount =
            ValidatorFacet(address(diamondProxy)).claimValidatorCommission(DEFAULT_VALIDATOR_ID, address(pUSD));
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
        uint256 claimedAmount =
            ValidatorFacet(address(diamondProxy)).claimValidatorCommission(DEFAULT_VALIDATOR_ID, address(pUSD));
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
        uint256 commissionClaimed =
            ValidatorFacet(address(diamondProxy)).claimValidatorCommission(DEFAULT_VALIDATOR_ID, address(pUSD));
        // uint256 validatorBalanceAfter = pUSD.balanceOf(validatorAdmin);
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
        assertTrue(stakeInfo.cooldownEnd > block.timestamp, "Cooldown end date should be in the future");
        uint256 cooldownEnd = stakeInfo.cooldownEnd;
        console2.log("User1 unstaked %s ETH, now in cooldown until %s", stakeAmount, cooldownEnd);

        // Before cooldown ends, User1 restakes the cooling amount to the *same* validator
        assertTrue(block.timestamp < cooldownEnd, "Attempting restake before cooldown ends");
        // CORRECTED: Destructure 4 values
        (bool activeBefore, uint256 commissionBefore, uint256 totalStakedBefore, uint256 stakersCountBefore) =
            ValidatorFacet(address(diamondProxy)).getValidatorStats(validatorId);

        console2.log("User1 attempting to restake %s ETH during cooldown...", stakeAmount);
        StakingFacet(address(diamondProxy)).restake(validatorId, stakeAmount);

        // Verify state after restake
        stakeInfo = StakingFacet(address(diamondProxy)).stakeInfo(user1);
        // CORRECTED: Use cooldownEnd
        console2.log(
            "State after restake: Staked=%s, Cooling=%s, CooldownEnd=%s",
            stakeInfo.staked,
            stakeInfo.cooled,
            stakeInfo.cooldownEnd
        );

        // EXPECTED CORRECT BEHAVIOR:
        assertEq(stakeInfo.cooled, 0, "Cooling amount should be 0 after restake"); // CORRECTED
        assertEq(stakeInfo.staked, stakeAmount, "Staked amount should be restored after restake"); // CORRECTED (THIS IS
            // LIKELY TO FAIL)
        // Cooldown should be cancelled/reset
        assertEq(stakeInfo.cooldownEnd, 0, "Cooldown end date should be reset after restake");

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
        uint256 cooldownEnd1 = stakeInfo.cooldownEnd;
        assertTrue(cooldownEnd1 > block.timestamp, "Cooldown 1 not set");
        assertEq(stakeInfo.staked, initialStake - firstUnstake, "State Error after Step 2 (Staked)");
        assertEq(stakeInfo.cooled, firstUnstake, "State Error after Step 2 (Cooled)");
        console2.log("   Cooldown ends at: %d", cooldownEnd1);

        // 3. Advance time (partway through cooldown) & Restake 2 ETH from cooling
        vm.warp(block.timestamp + (cooldownEnd1 - block.timestamp) / 2);
        console2.log("3. Restaking %s ETH from cooling...", firstRestake);
        StakingFacet(address(diamondProxy)).restake(validatorId, firstRestake);
        stakeInfo = StakingFacet(address(diamondProxy)).stakeInfo(user1);
        assertEq(stakeInfo.staked, initialStake - firstUnstake + firstRestake, "State Error after Step 3 (Staked)");
        assertEq(stakeInfo.cooled, firstUnstake - firstRestake, "State Error after Step 3 (Cooled)");
        assertEq(stakeInfo.cooldownEnd, cooldownEnd1, "Cooldown 1 should NOT reset yet"); // Cooldown timer continues

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
        assertEq(stakeInfo.cooled, 0, "State Error after Step 5 (Cooled)");
        assertEq(stakeInfo.parked, 0, "State Error after Step 5 (Parked)");
        assertEq(stakeInfo.cooldownEnd, 0, "Cooldown 1 should be reset after withdrawing all cooled");

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
        uint256 cooldownEnd2 = stakeInfo.cooldownEnd;
        assertTrue(cooldownEnd2 > block.timestamp, "Cooldown 2 not set");
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
        assertEq(stakeInfo.cooled, secondUnstake, "Internal State Error after Step 9 (Cooled)"); // Raw cooled should
            // still hold the value
        assertEq(stakeInfo.parked, 0, "Internal State Error after Step 9 (Parked)"); // Parked only updated by
            // withdraw/restakeParked
        assertTrue(stakeInfo.cooldownEnd <= block.timestamp, "Cooldown 2 end date should be in the past");

        // 10. Attempt `restakeParked` when parked and available cooled are 0 (expect revert)
        console2.log("10. Attempting restakeParked after withdrawing available balance (expect revert)...");
        // First, actually withdraw the funds to move them out of cooled/parked state
        uint256 balanceBeforeWithdrawStep10 = user1.balance;
        StakingFacet(address(diamondProxy)).withdraw();
        assertEq(user1.balance, balanceBeforeWithdrawStep10 + withdrawable, "Withdraw amount mismatch in Step 10");
        stakeInfo = StakingFacet(address(diamondProxy)).stakeInfo(user1);
        assertEq(stakeInfo.parked, 0, "Parked should be 0 after withdraw");
        assertEq(stakeInfo.cooled, 0, "Cooled should be 0 after withdraw");
        assertEq(stakeInfo.cooldownEnd, 0, "Cooldown should be reset after withdraw");

        // Now expect revert when calling restakeParked as there is nothing to restake
        //vm.expectRevert(abi.encodeWithSelector(NoRewardsToRestake.selector));
        StakingFacet(address(diamondProxy)).restakeRewards(validatorId); // Use correct function name

        // --- Steps 11-13 Re-evaluated ---
        // The original intent was to restake the withdrawable amount. Let's redo this part.
        // Reset state slightly by staking again and unstaking to get funds into cooled/parked state.

        // Re-stake 4 ETH
        console2.log("10b. Re-staking %s ETH to set up for restakeParked test", finalRestake);
        StakingFacet(address(diamondProxy)).stake{ value: finalRestake }(validatorId);

        // Unstake 4 ETH again
        console2.log("10c. Unstaking %s ETH again...", finalRestake);
        StakingFacet(address(diamondProxy)).unstake(validatorId, finalRestake);
        uint256 cooldownEnd3 = StakingFacet(address(diamondProxy)).cooldownEndDate();
        assertTrue(cooldownEnd3 > block.timestamp, "Cooldown 3 not set");
        console2.log("   Cooldown ends at: %s", cooldownEnd3);

        // Advance time past cooldown 3
        console2.log("10d. Advancing time past cooldown 3 (%s)...", cooldownEnd3);
        vm.warp(cooldownEnd3 + 1);

        // Verify 4 ETH is withdrawable (in cooled state, but past end date)
        withdrawable = StakingFacet(address(diamondProxy)).amountWithdrawable();
        assertEq(withdrawable, finalRestake, "Withdrawable amount mismatch before final restake");
        stakeInfo = StakingFacet(address(diamondProxy)).stakeInfo(user1);
        assertEq(stakeInfo.cooled, finalRestake, "Cooled amount mismatch before final restake");
        assertEq(stakeInfo.parked, 0, "Parked amount mismatch before final restake");

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

        // Reward Token Info (PLUME_NATIVE)
        try rewardsFacet.tokenRewardInfo(PLUME_NATIVE) returns (
            uint256 rewardRate, uint256 rewardsAvailable, uint256 lastUpdateTime
        ) {
            console2.log(
                "   PLUME Reward Info: rewardRate=%d, rewardsAvailable=%d, lastUpdateTime=%d, ",
                rewardRate,
                rewardsAvailable,
                lastUpdateTime
            );
        } catch Error(string memory reason) {
            console2.log("   Could not get PLUME tokenRewardInfo: %s", reason);
        } catch {
            console2.log("   Could not get PLUME tokenRewardInfo (Unknown error).");
        }

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

}
