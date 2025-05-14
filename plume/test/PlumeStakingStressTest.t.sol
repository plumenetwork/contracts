// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { StdCheats } from "forge-std/StdCheats.sol";
import { Test, console2 } from "forge-std/Test.sol";

// Diamond Proxy & Storage
import { PlumeStaking } from "../src/PlumeStaking.sol";
import { PlumeStakingStorage } from "../src/lib/PlumeStakingStorage.sol";

// Custom Facet Contracts
import { AccessControlFacet } from "../src/facets/AccessControlFacet.sol";
import { ManagementFacet } from "../src/facets/ManagementFacet.sol";
import { RewardsFacet } from "../src/facets/RewardsFacet.sol";
import { StakingFacet } from "../src/facets/StakingFacet.sol";
import { ValidatorFacet } from "../src/facets/ValidatorFacet.sol";
import { IAccessControl } from "../src/interfaces/IAccessControl.sol";
import { IPlumeStakingRewardTreasury } from "../src/interfaces/IPlumeStakingRewardTreasury.sol";

// SolidState Diamond Interface & Cut Interface
import { IERC2535DiamondCutInternal } from "@solidstate/interfaces/IERC2535DiamondCutInternal.sol";
import { ISolidStateDiamond } from "@solidstate/proxy/diamond/ISolidStateDiamond.sol";

// Libs & Errors/Events
import { NoRewardsToRestake, NotValidatorAdmin, Unauthorized } from "../src/lib/PlumeErrors.sol";
import "../src/lib/PlumeErrors.sol";
import "../src/lib/PlumeEvents.sol";

import { PlumeRewardLogic } from "../src/lib/PlumeRewardLogic.sol";
import { PlumeRoles } from "../src/lib/PlumeRoles.sol"; // Needed for REWARD_PRECISION

// OZ Contracts
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Treasury Proxy
import { PlumeStakingRewardTreasury } from "../src/PlumeStakingRewardTreasury.sol";
import { PlumeStakingRewardTreasuryProxy } from "../src/proxy/PlumeStakingRewardTreasuryProxy.sol";

contract PlumeStakingStressTest is Test {

    // Diamond Proxy Address
    PlumeStaking internal diamondProxy;
    PlumeStakingRewardTreasury public treasury;

    // Addresses
    address public constant ADMIN_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;
    address payable public constant PLUME_NATIVE = payable(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE); // Payable for
        // treasury funding

    address public admin;

    // Constants
    uint256 public constant MIN_STAKE = 1e17; // 0.1 PLUME for stress testing
    uint256 public constant INITIAL_COOLDOWN = 7 days; // Keep real cooldown
    uint16 public constant NUM_VALIDATORS = 15;
    uint256 public constant VALIDATOR_COMMISSION = 0.005 * 1e18; // 0.5% scaled by 1e18
    // Approx 5% APR for PLUME rewards per second = (0.05 * 1e18) / (365 days * 24 hours * 60 mins * 60 secs)
    uint256 public constant PLUME_REWARD_RATE_PER_SECOND = 1_585_489_599; // ~5% APR (5e16 / 31536000)

    // Test parameters
    uint256 constant MAX_RANDOM_STAKE_AMOUNT = 5 ether; // Max amount for a single random stake action
    uint256 constant TEST_STAKER_INITIAL_BALANCE = 100 ether; // Ensure test staker has plenty of funds
    uint256 constant GAS_TEST_NUM_ACTIONS = 100; // Number of actions to measure gas for

    // Cost calculation parameters (adjust as needed)
    uint256 constant ETH_PRICE_USD = 3500; // Example ETH price
    uint256 constant L2_GAS_PRICE_GWEI = 0.001 * 1e9; // Example L2 gas price (0.001 Gwei) - SCALE BY 1e9 for wei

    // Unique address for the staker whose actions we measure
    address constant TEST_STAKER = address(0xBADBADBAD);

    function setUp() public {
        console2.log("Starting Stress Test setup");

        admin = ADMIN_ADDRESS;
        vm.deal(admin, 10_000 ether); // Ensure admin has funds

        vm.startPrank(admin);

        // 1. Deploy Diamond Proxy
        diamondProxy = new PlumeStaking();
        assertEq(
            ISolidStateDiamond(payable(address(diamondProxy))).owner(), admin, "Deployer should be owner initially"
        );

        // 2. Deploy Custom Facets
        AccessControlFacet accessControlFacet = new AccessControlFacet();
        StakingFacet stakingFacet = new StakingFacet();
        RewardsFacet rewardsFacet = new RewardsFacet();
        ValidatorFacet validatorFacet = new ValidatorFacet();
        ManagementFacet managementFacet = new ManagementFacet();

        // 3. Prepare Diamond Cut
        IERC2535DiamondCutInternal.FacetCut[] memory cut = new IERC2535DiamondCutInternal.FacetCut[](5);

        // --- Get Selectors (using helper or manual list) ---
        bytes4[] memory accessControlSigs = new bytes4[](7);
        accessControlSigs[0] = AccessControlFacet.initializeAccessControl.selector;
        accessControlSigs[1] = IAccessControl.hasRole.selector;
        accessControlSigs[2] = IAccessControl.getRoleAdmin.selector;
        accessControlSigs[3] = IAccessControl.grantRole.selector;
        accessControlSigs[4] = IAccessControl.revokeRole.selector;
        accessControlSigs[5] = IAccessControl.renounceRole.selector;
        accessControlSigs[6] = IAccessControl.setRoleAdmin.selector;

        bytes4[] memory stakingSigs = new bytes4[](14);
        stakingSigs[0] = StakingFacet.stake.selector;
        stakingSigs[1] = StakingFacet.restake.selector;
        stakingSigs[2] = bytes4(keccak256("unstake(uint16)"));
        stakingSigs[3] = bytes4(keccak256("unstake(uint16,uint256)"));
        stakingSigs[4] = StakingFacet.withdraw.selector;
        stakingSigs[5] = StakingFacet.stakeOnBehalf.selector;
        stakingSigs[6] = StakingFacet.stakeInfo.selector;
        stakingSigs[7] = StakingFacet.amountStaked.selector;
        stakingSigs[8] = StakingFacet.amountCooling.selector;
        stakingSigs[9] = StakingFacet.amountWithdrawable.selector;
        stakingSigs[10] = StakingFacet.cooldownEndDate.selector;
        stakingSigs[11] = StakingFacet.getUserValidatorStake.selector;
        stakingSigs[12] = StakingFacet.restakeRewards.selector;
        stakingSigs[13] = StakingFacet.totalAmountStaked.selector;

        bytes4[] memory rewardsSigs = new bytes4[](15);
        rewardsSigs[0] = RewardsFacet.addRewardToken.selector;
        rewardsSigs[1] = RewardsFacet.removeRewardToken.selector;
        rewardsSigs[2] = RewardsFacet.setRewardRates.selector;
        rewardsSigs[3] = RewardsFacet.setMaxRewardRate.selector;
        rewardsSigs[4] = bytes4(keccak256("claim(address)"));
        rewardsSigs[5] = bytes4(keccak256("claim(address,uint16)"));
        rewardsSigs[6] = RewardsFacet.claimAll.selector;
        rewardsSigs[7] = RewardsFacet.earned.selector;
        rewardsSigs[8] = RewardsFacet.getClaimableReward.selector;
        rewardsSigs[9] = RewardsFacet.getRewardTokens.selector;
        rewardsSigs[10] = RewardsFacet.getMaxRewardRate.selector;
        rewardsSigs[11] = RewardsFacet.tokenRewardInfo.selector;
        rewardsSigs[12] = RewardsFacet.setTreasury.selector;
        rewardsSigs[13] = RewardsFacet.getPendingRewardForValidator.selector;

        bytes4[] memory validatorSigs = new bytes4[](14);
        validatorSigs[0] = ValidatorFacet.addValidator.selector;
        validatorSigs[1] = ValidatorFacet.setValidatorCapacity.selector;
        validatorSigs[2] = ValidatorFacet.setValidatorCommission.selector;
        validatorSigs[3] = ValidatorFacet.setValidatorAddresses.selector;
        validatorSigs[4] = ValidatorFacet.setValidatorStatus.selector;
        validatorSigs[5] = ValidatorFacet.getValidatorInfo.selector;
        validatorSigs[6] = ValidatorFacet.getValidatorStats.selector;
        validatorSigs[7] = ValidatorFacet.getUserValidators.selector;
        validatorSigs[8] = ValidatorFacet.getAccruedCommission.selector;
        validatorSigs[9] = ValidatorFacet.getValidatorsList.selector;
        validatorSigs[10] = ValidatorFacet.getActiveValidatorCount.selector;
        validatorSigs[11] = ValidatorFacet.claimValidatorCommission.selector;
        validatorSigs[12] = ValidatorFacet.voteToSlashValidator.selector;
        validatorSigs[13] = ValidatorFacet.slashValidator.selector;

        bytes4[] memory managementSigs = new bytes4[](6); // Size reduced from 7 to 6
        managementSigs[0] = ManagementFacet.setMinStakeAmount.selector;
        managementSigs[1] = ManagementFacet.setCooldownInterval.selector;
        managementSigs[2] = ManagementFacet.adminWithdraw.selector;
        managementSigs[3] = ManagementFacet.getMinStakeAmount.selector; // Index shifted from 4
        managementSigs[4] = ManagementFacet.getCooldownInterval.selector; // Index shifted from 5
        managementSigs[5] = ManagementFacet.setMaxSlashVoteDuration.selector; // Index shifted from 6

        // Define the Facet Cuts
        cut[0] = IERC2535DiamondCutInternal.FacetCut({
            target: address(accessControlFacet),
            action: IERC2535DiamondCutInternal.FacetCutAction.ADD,
            selectors: accessControlSigs
        });
        cut[1] = IERC2535DiamondCutInternal.FacetCut({
            target: address(managementFacet),
            action: IERC2535DiamondCutInternal.FacetCutAction.ADD,
            selectors: managementSigs
        });
        cut[2] = IERC2535DiamondCutInternal.FacetCut({
            target: address(stakingFacet),
            action: IERC2535DiamondCutInternal.FacetCutAction.ADD,
            selectors: stakingSigs
        });
        cut[3] = IERC2535DiamondCutInternal.FacetCut({
            target: address(validatorFacet),
            action: IERC2535DiamondCutInternal.FacetCutAction.ADD,
            selectors: validatorSigs
        });
        cut[4] = IERC2535DiamondCutInternal.FacetCut({
            target: address(rewardsFacet),
            action: IERC2535DiamondCutInternal.FacetCutAction.ADD,
            selectors: rewardsSigs
        });

        // 4. Execute Diamond Cut
        ISolidStateDiamond(payable(address(diamondProxy))).diamondCut(cut, address(0), "");
        console2.log("Diamond cut applied.");

        // 5. Initialize
        diamondProxy.initializePlume(address(0), MIN_STAKE, INITIAL_COOLDOWN);
        AccessControlFacet(address(diamondProxy)).initializeAccessControl();
        AccessControlFacet(address(diamondProxy)).grantRole(PlumeRoles.ADMIN_ROLE, admin);
        AccessControlFacet(address(diamondProxy)).grantRole(PlumeRoles.VALIDATOR_ROLE, admin);
        AccessControlFacet(address(diamondProxy)).grantRole(PlumeRoles.REWARD_MANAGER_ROLE, admin); // Grant reward
            // manager
        AccessControlFacet(address(diamondProxy)).grantRole(PlumeRoles.TIMELOCK_ROLE, admin);
        console2.log("Diamond initialized.");

        // 6. Deploy and setup reward treasury
        PlumeStakingRewardTreasury treasuryImpl = new PlumeStakingRewardTreasury();
        bytes memory initData =
            abi.encodeWithSelector(PlumeStakingRewardTreasury.initialize.selector, admin, address(diamondProxy));
        PlumeStakingRewardTreasuryProxy treasuryProxy =
            new PlumeStakingRewardTreasuryProxy(address(treasuryImpl), initData);
        treasury = PlumeStakingRewardTreasury(payable(address(treasuryProxy)));
        RewardsFacet(address(diamondProxy)).setTreasury(address(treasury));
        console2.log("Treasury deployed and set.");

        // 7. Add PLUME_NATIVE as the only reward token
        RewardsFacet(address(diamondProxy)).addRewardToken(PLUME_NATIVE);
        treasury.addRewardToken(PLUME_NATIVE); // Also add to treasury allowed list
        vm.deal(address(treasury), 1_000_000 ether); // Give treasury a large amount of native ETH for rewards
        console2.log("PLUME_NATIVE reward token added and treasury funded.");

        // 8. Setup Validators (15)
        uint256 defaultMaxCapacity = 1_000_000_000 ether; // High capacity
        for (uint16 i = 0; i < NUM_VALIDATORS; i++) {
            address valAdmin = vm.addr(uint256(keccak256(abi.encodePacked("validatorAdmin", i))));
            vm.deal(valAdmin, 1 ether); // Give admin some gas money
            ValidatorFacet(address(diamondProxy)).addValidator(
                i,
                VALIDATOR_COMMISSION,
                valAdmin, // Use unique admin
                valAdmin, // Use same address for withdraw for simplicity
                string(abi.encodePacked("l1val", i)),
                string(abi.encodePacked("l1acc", i)),
                vm.addr(uint256(keccak256(abi.encodePacked("l1evm", i)))),
                defaultMaxCapacity
            );
        }
        console2.log("%d validators added.", NUM_VALIDATORS);

        // 9. Set reward rates for PLUME_NATIVE
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = PLUME_NATIVE;
        uint256[] memory rates = new uint256[](1);
        rates[0] = PLUME_REWARD_RATE_PER_SECOND;
        // Set Max Rate slightly higher just in case
        RewardsFacet(address(diamondProxy)).setMaxRewardRate(PLUME_NATIVE, PLUME_REWARD_RATE_PER_SECOND * 2);
        RewardsFacet(address(diamondProxy)).setRewardRates(rewardTokens, rates);
        console2.log("PLUME reward rate set.");

        vm.stopPrank();
        console2.log("Stress Test setup complete.");
    }

    // --- Helper Function for Initial Setup ---

    /**
     * @notice Internal helper to set up the contract with a number of initial stakers.
     * @param numInitialStakers The number of stakers to create and have stake initially.
     */
    function _setupInitialStakers(
        uint256 numInitialStakers
    ) internal {
        console2.log("Setting up %d initial stakers...", numInitialStakers);
        uint256 initialStakeAmount = 2 ether;

        // --- Create and fund initial stakers ---
        address[] memory initialStakers = new address[](numInitialStakers);
        for (uint256 i = 0; i < numInitialStakers; i++) {
            initialStakers[i] = vm.addr(uint256(keccak256(abi.encodePacked("initial_staker_", i))));
            vm.deal(initialStakers[i], initialStakeAmount * 2); // Give them enough for one stake + gas
        }

        // --- Have initial stakers perform one stake action ---
        StakingFacet staking = StakingFacet(address(diamondProxy));
        for (uint256 i = 0; i < numInitialStakers; i++) {
            if (i > 0 && i % 500 == 0) {
                vm.roll(block.number + 1);
            }
            address staker = initialStakers[i];
            vm.startPrank(staker);
            uint16 validatorId = uint16(uint256(keccak256(abi.encodePacked("initial_val_", i))) % NUM_VALIDATORS);
            // Simple stake, ignore reverts for setup simplicity
            try staking.stake{ value: initialStakeAmount }(validatorId) { } catch { /* ignore */ }
            vm.stopPrank();
        }
        console2.log("%d initial stakers set up.", numInitialStakers);
    }

    // --- Combined Gas Measurement and Stress Test Logic ---

    /**
     * @notice Internal helper to run stress tests and measure gas for key actions.
     * @dev Sets up initial stakers, then performs a series of random actions for a
     *      dedicated test staker, logging gas usage for each action.
     * @param numInitialStakers Number of stakers to setup *before* the test actions begin.
     * @param numActionsToTest Number of random actions to perform and measure for the test staker.
     */
    function _runGasAndStressTest(uint256 numInitialStakers, uint256 numActionsToTest) internal {
        // 1. Setup Initial Stakers
        _setupInitialStakers(numInitialStakers);

        // 2. Setup Test Staker
        vm.deal(TEST_STAKER, TEST_STAKER_INITIAL_BALANCE);
        console2.log("--- Starting Gas & Stress Test Actions for 1 Staker (%d actions) --- ", numActionsToTest);
        console2.log(" (Initial Staker Count: %d)", numInitialStakers);
        vm.startPrank(TEST_STAKER);

        StakingFacet staking = StakingFacet(address(diamondProxy));
        RewardsFacet rewards = RewardsFacet(address(diamondProxy));
        ValidatorFacet validator = ValidatorFacet(address(diamondProxy));

        uint256 gasBefore;
        uint256 gasAfter;
        uint256 gasUsed;
        uint256 totalGasUsedSuccess = 0;
        uint256 successfulActions = 0;

        // 3. Perform and Measure Actions
        for (uint256 j = 0; j < numActionsToTest; j++) {
            // Pseudo-randomness
            uint256 randomSeed =
                uint256(keccak256(abi.encodePacked(block.timestamp, j, TEST_STAKER, numInitialStakers)));
            uint16 validatorId = uint16(randomSeed % NUM_VALIDATORS);
            uint256 actionType = randomSeed % 5; // 0:stake, 1:unstake, 2:restake, 3:withdraw, 4:restakeRewards
            uint256 amount = (randomSeed >> 32) % MAX_RANDOM_STAKE_AMOUNT + MIN_STAKE; // Ensure amount >= MIN_STAKE

            // Advance time slightly between actions to allow some reward accrual
            vm.warp(block.timestamp + 1 hours);

            if (actionType == 0) {
                // Stake
                console2.log("Action %d: Stake %d wei to Validator %d", j + 1, amount, validatorId);
                uint256 balanceBefore = TEST_STAKER.balance;
                uint256 stakeBefore = staking.getUserValidatorStake(TEST_STAKER, validatorId);
                uint256 totalStakedBefore = staking.totalAmountStaked();
                (,, uint256 validatorStakeBefore,) = validator.getValidatorStats(validatorId);
                uint256 stakerInfoStakedBefore = staking.stakeInfo(TEST_STAKER).staked;

                if (balanceBefore >= amount) {
                    gasBefore = gasleft();
                    try staking.stake{ value: amount }(validatorId) returns (uint256 stakedAmount) {
                        gasAfter = gasleft();
                        gasUsed = gasBefore - gasAfter;
                        console2.log("  Gas Used (Stake Success): %d", gasUsed);
                        totalGasUsedSuccess += gasUsed;
                        successfulActions++;
                        // Assertions
                        assertEq(
                            TEST_STAKER.balance, balanceBefore - stakedAmount, "Staker balance incorrect after stake"
                        );
                        assertEq(
                            staking.getUserValidatorStake(TEST_STAKER, validatorId),
                            stakeBefore + stakedAmount,
                            "User validator stake incorrect after stake"
                        );
                        assertEq(
                            staking.totalAmountStaked(),
                            totalStakedBefore + stakedAmount,
                            "Total staked incorrect after stake"
                        );
                        (,, uint256 validatorStakeAfter,) = validator.getValidatorStats(validatorId);
                        assertEq(
                            validatorStakeAfter,
                            validatorStakeBefore + stakedAmount,
                            "Validator total stake incorrect after stake"
                        );
                        assertEq(
                            staking.stakeInfo(TEST_STAKER).staked,
                            stakerInfoStakedBefore + stakedAmount,
                            "Staker info staked amount incorrect after stake"
                        );
                    } catch Error(string memory reason) {
                        gasAfter = gasleft();
                        gasUsed = gasBefore - gasAfter;
                        console2.log("  Gas Used (Stake Revert '%s'): %d", reason, gasUsed);
                        // Assertions (state should be unchanged)
                        assertEq(TEST_STAKER.balance, balanceBefore, "Staker balance changed after failed stake");
                        assertEq(
                            staking.getUserValidatorStake(TEST_STAKER, validatorId),
                            stakeBefore,
                            "User validator stake changed after failed stake"
                        );
                        assertEq(
                            staking.totalAmountStaked(), totalStakedBefore, "Total staked changed after failed stake"
                        );
                        (,, uint256 validatorStakeAfter,) = validator.getValidatorStats(validatorId);
                        assertEq(
                            validatorStakeAfter,
                            validatorStakeBefore,
                            "Validator total stake changed after failed stake"
                        );
                        assertEq(
                            staking.stakeInfo(TEST_STAKER).staked,
                            stakerInfoStakedBefore,
                            "Staker info staked amount changed after failed stake"
                        );
                    } catch (bytes memory) /* lowLevelData */ {
                        gasAfter = gasleft();
                        gasUsed = gasBefore - gasAfter;
                        console2.log("  Gas Used (Stake Revert LowLevel): %d", gasUsed);
                        // Assertions (state should be unchanged)
                        assertEq(
                            TEST_STAKER.balance, balanceBefore, "Staker balance changed after failed low-level stake"
                        );
                        assertEq(
                            staking.getUserValidatorStake(TEST_STAKER, validatorId),
                            stakeBefore,
                            "User validator stake changed after failed low-level stake"
                        );
                        assertEq(
                            staking.totalAmountStaked(),
                            totalStakedBefore,
                            "Total staked changed after failed low-level stake"
                        );
                        (,, uint256 validatorStakeAfter,) = validator.getValidatorStats(validatorId);
                        assertEq(
                            validatorStakeAfter,
                            validatorStakeBefore,
                            "Validator total stake changed after failed low-level stake"
                        );
                        assertEq(
                            staking.stakeInfo(TEST_STAKER).staked,
                            stakerInfoStakedBefore,
                            "Staker info staked amount changed after failed low-level stake"
                        );
                    }
                } else {
                    console2.log("  Skipping stake (insufficient balance)");
                }
            } else if (actionType == 1) {
                // Unstake
                uint256 stakeBefore = staking.getUserValidatorStake(TEST_STAKER, validatorId);
                console2.log(
                    "Action %d: Unstake from Validator %d (current stake: %d)", j + 1, validatorId, stakeBefore
                );
                if (stakeBefore > 0) {
                    uint256 unstakeAmount = amount > stakeBefore ? stakeBefore : amount; // Unstake max currentStake or
                        // random amount
                    if (unstakeAmount == 0) {
                        unstakeAmount = stakeBefore;
                    } // Ensure we unstake *something* if stake > 0
                    console2.log("  Attempting to unstake: %d", unstakeAmount);

                    if (unstakeAmount >= MIN_STAKE || unstakeAmount == stakeBefore) {
                        // Check validity
                        uint256 totalStakedBefore = staking.totalAmountStaked();
                        (,, uint256 validatorStakeBefore,) = validator.getValidatorStats(validatorId);
                        PlumeStakingStorage.StakeInfo memory infoBefore = staking.stakeInfo(TEST_STAKER);

                        gasBefore = gasleft();
                        try staking.unstake(validatorId, unstakeAmount) returns (uint256 cooledAmount) {
                            gasAfter = gasleft();
                            gasUsed = gasBefore - gasAfter;
                            console2.log("  Gas Used (Unstake Success): %d", gasUsed);
                            totalGasUsedSuccess += gasUsed;
                            successfulActions++;
                            // Assertions
                            assertEq(
                                staking.getUserValidatorStake(TEST_STAKER, validatorId),
                                stakeBefore - cooledAmount,
                                "User validator stake incorrect after unstake"
                            );
                            assertEq(
                                staking.totalAmountStaked(),
                                totalStakedBefore - cooledAmount,
                                "Total staked incorrect after unstake"
                            );
                            (,, uint256 validatorStakeAfter,) = validator.getValidatorStats(validatorId);
                            assertEq(
                                validatorStakeAfter,
                                validatorStakeBefore - cooledAmount,
                                "Validator total stake incorrect after unstake"
                            );
                            assertEq(
                                staking.stakeInfo(TEST_STAKER).staked,
                                infoBefore.staked - cooledAmount,
                                "Staker info staked amount incorrect after unstake"
                            );
                            assertEq(
                                staking.stakeInfo(TEST_STAKER).cooled,
                                infoBefore.cooled + cooledAmount,
                                "Staker info cooled amount incorrect after unstake"
                            ); // Check relative increase
                        } catch Error(string memory reason) {
                            gasAfter = gasleft();
                            gasUsed = gasBefore - gasAfter;
                            console2.log("  Gas Used (Unstake Revert '%s'): %d", reason, gasUsed);
                            // Assertions (state should be unchanged)
                            assertEq(
                                staking.getUserValidatorStake(TEST_STAKER, validatorId),
                                stakeBefore,
                                "User validator stake changed after failed unstake"
                            );
                            assertEq(
                                staking.totalAmountStaked(),
                                totalStakedBefore,
                                "Total staked changed after failed unstake"
                            );
                            (,, uint256 validatorStakeAfter,) = validator.getValidatorStats(validatorId);
                            assertEq(
                                validatorStakeAfter,
                                validatorStakeBefore,
                                "Validator total stake changed after failed unstake"
                            );
                            PlumeStakingStorage.StakeInfo memory infoAfter = staking.stakeInfo(TEST_STAKER);
                            assertEq(
                                infoAfter.staked, infoBefore.staked, "Staker info staked changed after failed unstake"
                            );
                            assertEq(
                                infoAfter.cooled, infoBefore.cooled, "Staker info cooled changed after failed unstake"
                            );
                        } catch (bytes memory) /* lowLevelData */ {
                            gasAfter = gasleft();
                            gasUsed = gasBefore - gasAfter;
                            console2.log("  Gas Used (Unstake Revert LowLevel): %d", gasUsed);
                            // Assertions (state should be unchanged)
                            assertEq(
                                staking.getUserValidatorStake(TEST_STAKER, validatorId),
                                stakeBefore,
                                "User validator stake changed after failed low-level unstake"
                            );
                            assertEq(
                                staking.totalAmountStaked(),
                                totalStakedBefore,
                                "Total staked changed after failed low-level unstake"
                            );
                            (,, uint256 validatorStakeAfter,) = validator.getValidatorStats(validatorId);
                            assertEq(
                                validatorStakeAfter,
                                validatorStakeBefore,
                                "Validator total stake changed after failed low-level unstake"
                            );
                            PlumeStakingStorage.StakeInfo memory infoAfter = staking.stakeInfo(TEST_STAKER);
                            assertEq(
                                infoAfter.staked,
                                infoBefore.staked,
                                "Staker info staked changed after failed low-level unstake"
                            );
                            assertEq(
                                infoAfter.cooled,
                                infoBefore.cooled,
                                "Staker info cooled changed after failed low-level unstake"
                            );
                        }
                    } else {
                        console2.log("  Skipping unstake (invalid amount: %d)", unstakeAmount);
                    }
                } else {
                    console2.log("  Skipping unstake (no stake with validator)");
                }
            } else if (actionType == 2) {
                // Restake (from cooled/parked)
                PlumeStakingStorage.StakeInfo memory infoBefore = staking.stakeInfo(TEST_STAKER);
                uint256 availableToRestake = infoBefore.cooled + infoBefore.parked;
                console2.log(
                    "Action %d: Restake to Validator %d (available: %d)", j + 1, validatorId, availableToRestake
                );

                if (availableToRestake > 0) {
                    uint256 restakeAmount = amount > availableToRestake ? availableToRestake : amount;
                    if (restakeAmount == 0) {
                        restakeAmount = availableToRestake;
                    } // Ensure we restake *something*
                    console2.log("  Attempting to restake: %d", restakeAmount);

                    if (restakeAmount >= MIN_STAKE) {
                        // Check validity
                        uint256 totalStakedBefore = staking.totalAmountStaked();
                        (,, uint256 validatorStakeBefore,) = validator.getValidatorStats(validatorId);

                        gasBefore = gasleft();
                        try staking.restake(validatorId, restakeAmount) returns (uint256 actualRestaked) {
                            gasAfter = gasleft();
                            gasUsed = gasBefore - gasAfter;
                            console2.log("  Gas Used (Restake Success): %d", gasUsed);
                            totalGasUsedSuccess += gasUsed;
                            successfulActions++;
                            // Assertions (only check if successful)
                            PlumeStakingStorage.StakeInfo memory infoAfter = staking.stakeInfo(TEST_STAKER);
                            assertEq(
                                infoAfter.staked,
                                infoBefore.staked + actualRestaked,
                                "Staker info staked incorrect after restake"
                            );
                            assertEq(
                                infoAfter.cooled + infoAfter.parked,
                                availableToRestake - actualRestaked,
                                "Staker info available incorrect after restake"
                            );
                            assertEq(
                                staking.totalAmountStaked(),
                                totalStakedBefore + actualRestaked,
                                "Total staked incorrect after restake"
                            );
                            (,, uint256 validatorStakeAfter,) = validator.getValidatorStats(validatorId);
                            assertEq(
                                validatorStakeAfter,
                                validatorStakeBefore + actualRestaked,
                                "Validator total stake incorrect after restake"
                            );
                        } catch Error(string memory reason) {
                            gasAfter = gasleft();
                            gasUsed = gasBefore - gasAfter;
                            console2.log("  Gas Used (Restake Revert '%s'): %d", reason, gasUsed);
                            // Assertions (state should be unchanged) - Difficult due to partial restake logic, check
                            // overall available remains same
                            PlumeStakingStorage.StakeInfo memory infoAfter = staking.stakeInfo(TEST_STAKER);
                            assertEq(
                                infoAfter.cooled + infoAfter.parked,
                                availableToRestake,
                                "Staker info available changed after failed restake"
                            );
                            assertEq(
                                infoAfter.staked, infoBefore.staked, "Staker info staked changed after failed restake"
                            );
                            assertEq(
                                staking.totalAmountStaked(),
                                totalStakedBefore,
                                "Total staked changed after failed restake"
                            );
                            (,, uint256 validatorStakeAfter,) = validator.getValidatorStats(validatorId);
                            assertEq(
                                validatorStakeAfter,
                                validatorStakeBefore,
                                "Validator total stake changed after failed restake"
                            );
                        } catch (bytes memory) /*lowLevelData*/ {
                            gasAfter = gasleft();
                            gasUsed = gasBefore - gasAfter;
                            console2.log("  Gas Used (Restake Revert LowLevel): %d", gasUsed);
                            // Assertions (state should be unchanged)
                            PlumeStakingStorage.StakeInfo memory infoAfter = staking.stakeInfo(TEST_STAKER);
                            assertEq(
                                infoAfter.cooled + infoAfter.parked,
                                availableToRestake,
                                "Staker info available changed after failed low-level restake"
                            );
                            assertEq(
                                infoAfter.staked,
                                infoBefore.staked,
                                "Staker info staked changed after failed low-level restake"
                            );
                            assertEq(
                                staking.totalAmountStaked(),
                                totalStakedBefore,
                                "Total staked changed after failed low-level restake"
                            );
                            (,, uint256 validatorStakeAfter,) = validator.getValidatorStats(validatorId);
                            assertEq(
                                validatorStakeAfter,
                                validatorStakeBefore,
                                "Validator total stake changed after failed low-level restake"
                            );
                        }
                    } else {
                        console2.log("  Skipping restake (invalid amount: %d)", restakeAmount);
                    }
                } else {
                    console2.log("  Skipping restake (nothing available)");
                }
            } else if (actionType == 3) {
                // Withdraw
                // Note: Withdraw depends on cooldown completion. We force it here for gas measurement.
                // Warp time far enough to ensure any cooled amount becomes withdrawable (parked).
                vm.warp(block.timestamp + INITIAL_COOLDOWN + 1 days);

                uint256 withdrawableBefore = staking.amountWithdrawable(); // Includes parked + cooled_if_ready
                PlumeStakingStorage.StakeInfo memory infoBefore = staking.stakeInfo(TEST_STAKER);
                uint256 balanceBefore = TEST_STAKER.balance;
                console2.log("Action %d: Withdraw (available: %d)", j + 1, withdrawableBefore);

                if (withdrawableBefore > 0) {
                    gasBefore = gasleft();
                    try staking.withdraw() returns (uint256 withdrawnAmount) {
                        gasAfter = gasleft();
                        gasUsed = gasBefore - gasAfter;
                        console2.log("  Gas Used (Withdraw Success): %d", gasUsed);
                        totalGasUsedSuccess += gasUsed;
                        successfulActions++;
                        // Assertions
                        PlumeStakingStorage.StakeInfo memory infoAfter = staking.stakeInfo(TEST_STAKER);
                        // Cooled might become 0 or stay same depending on if it was ready
                        assertTrue(infoAfter.cooled <= infoBefore.cooled, "Cooled should not increase on withdraw");
                        assertEq(infoAfter.parked, 0, "Parked should be 0 after withdraw"); // Assumes withdraw takes
                            // all parked
                        assertEq(
                            TEST_STAKER.balance, balanceBefore + withdrawnAmount, "Balance incorrect after withdraw"
                        );
                    } catch Error(string memory reason) {
                        gasAfter = gasleft();
                        gasUsed = gasBefore - gasAfter;
                        console2.log("  Gas Used (Withdraw Revert '%s'): %d", reason, gasUsed);
                        // Assertions (state should be unchanged)
                        PlumeStakingStorage.StakeInfo memory infoAfter = staking.stakeInfo(TEST_STAKER);
                        assertEq(infoAfter.cooled, infoBefore.cooled, "Cooled changed after failed withdraw");
                        assertEq(infoAfter.parked, infoBefore.parked, "Parked changed after failed withdraw");
                        assertEq(TEST_STAKER.balance, balanceBefore, "Balance changed after failed withdraw");
                    } catch (bytes memory) /*lowLevelData*/ {
                        gasAfter = gasleft();
                        gasUsed = gasBefore - gasAfter;
                        console2.log("  Gas Used (Withdraw Revert LowLevel): %d", gasUsed);
                        // Assertions (state should be unchanged)
                        PlumeStakingStorage.StakeInfo memory infoAfter = staking.stakeInfo(TEST_STAKER);
                        assertEq(infoAfter.cooled, infoBefore.cooled, "Cooled changed after failed low-level withdraw");
                        assertEq(infoAfter.parked, infoBefore.parked, "Parked changed after failed low-level withdraw");
                        assertEq(TEST_STAKER.balance, balanceBefore, "Balance changed after failed low-level withdraw");
                    }
                } else {
                    console2.log("  Skipping withdraw (nothing available or cooled)");
                }
            } else if (actionType == 4) {
                // Restake Rewards (PLUME)
                console2.log("Action %d: RestakeRewards to Validator %d", j + 1, validatorId);
                // Check pending rewards specifically for the target validator
                uint256 pending = rewards.getPendingRewardForValidator(TEST_STAKER, validatorId, PLUME_NATIVE);
                uint256 stakeBefore = staking.getUserValidatorStake(TEST_STAKER, validatorId);
                uint256 totalStakedBefore = staking.totalAmountStaked();
                (,, uint256 validatorStakeBefore,) = validator.getValidatorStats(validatorId);
                uint256 stakerInfoStakedBefore = staking.stakeInfo(TEST_STAKER).staked;

                if (pending > 0) {
                    gasBefore = gasleft();
                    try staking.restakeRewards(validatorId) returns (uint256 restakedAmount) {
                        gasAfter = gasleft();
                        gasUsed = gasBefore - gasAfter;
                        console2.log("  Gas Used (RestakeRewards Success): %d", gasUsed);
                        totalGasUsedSuccess += gasUsed;
                        successfulActions++;
                        // Assertions
                        assertTrue(restakedAmount > 0, "Restaked amount should be > 0 if pending > 0");
                        assertEq(
                            staking.getUserValidatorStake(TEST_STAKER, validatorId),
                            stakeBefore + restakedAmount,
                            "User validator stake incorrect after restakeRewards"
                        );
                        assertEq(
                            staking.totalAmountStaked(),
                            totalStakedBefore + restakedAmount,
                            "Total staked incorrect after restakeRewards"
                        );
                        (,, uint256 validatorStakeAfter,) = validator.getValidatorStats(validatorId);
                        assertEq(
                            validatorStakeAfter,
                            validatorStakeBefore + restakedAmount,
                            "Validator total stake incorrect after restakeRewards"
                        );
                        assertEq(
                            staking.stakeInfo(TEST_STAKER).staked,
                            stakerInfoStakedBefore + restakedAmount,
                            "Staker info staked incorrect after restakeRewards"
                        );
                        // Verify pending is now (near) zero for this validator
                        uint256 pendingAfter =
                            rewards.getPendingRewardForValidator(TEST_STAKER, validatorId, PLUME_NATIVE);
                        assertTrue(
                            pendingAfter < pending && pendingAfter < 100 wei,
                            "Pending rewards not cleared after restakeRewards"
                        ); // Allow for small dust due to precision/timing
                    } catch Error(string memory reason) {
                        gasAfter = gasleft();
                        gasUsed = gasBefore - gasAfter;
                        // Allow expected NoRewardsToRestake revert without failing test
                        bytes4 expectedSelector = NoRewardsToRestake.selector;
                        if (keccak256(bytes(reason)) != keccak256(abi.encodeWithSelector(expectedSelector))) {
                            // Compare selector hash
                            console2.log("  Gas Used (RestakeRewards Revert Unexpected '%s'): %d", reason, gasUsed);
                            // Fail the test for unexpected reverts
                            revert(string(abi.encodePacked("Unexpected RestakeRewards Revert: ", reason)));
                        } else {
                            console2.log(
                                "  Gas Used (RestakeRewards Revert Expected 'NoRewardsToRestake'): %d", gasUsed
                            );
                        }
                        // Assertions (state should be unchanged)
                        assertEq(
                            staking.getUserValidatorStake(TEST_STAKER, validatorId),
                            stakeBefore,
                            "User validator stake changed after failed restakeRewards"
                        );
                        assertEq(
                            staking.totalAmountStaked(),
                            totalStakedBefore,
                            "Total staked changed after failed restakeRewards"
                        );
                        (,, uint256 validatorStakeAfter,) = validator.getValidatorStats(validatorId);
                        assertEq(
                            validatorStakeAfter,
                            validatorStakeBefore,
                            "Validator total stake changed after failed restakeRewards"
                        );
                        assertEq(
                            staking.stakeInfo(TEST_STAKER).staked,
                            stakerInfoStakedBefore,
                            "Staker info staked changed after failed restakeRewards"
                        );
                    } catch (bytes memory) /*lowLevelData*/ {
                        gasAfter = gasleft();
                        gasUsed = gasBefore - gasAfter;
                        console2.log("  Gas Used (RestakeRewards Revert LowLevel): %d", gasUsed);
                        // Assertions (state should be unchanged)
                        assertEq(
                            staking.getUserValidatorStake(TEST_STAKER, validatorId),
                            stakeBefore,
                            "User validator stake changed after failed low-level restakeRewards"
                        );
                        assertEq(
                            staking.totalAmountStaked(),
                            totalStakedBefore,
                            "Total staked changed after failed low-level restakeRewards"
                        );
                        (,, uint256 validatorStakeAfter,) = validator.getValidatorStats(validatorId);
                        assertEq(
                            validatorStakeAfter,
                            validatorStakeBefore,
                            "Validator total stake changed after failed low-level restakeRewards"
                        );
                        assertEq(
                            staking.stakeInfo(TEST_STAKER).staked,
                            stakerInfoStakedBefore,
                            "Staker info staked changed after failed low-level restakeRewards"
                        );
                    }
                } else {
                    console2.log("  Skipping restakeRewards (no pending rewards for validator)");
                }
            }
        } // end actions loop

        vm.stopPrank();
        console2.log("--- Finished Gas & Stress Test Actions ---");

        // 4. Cost Calculation & Final Logs
        if (successfulActions > 0) {
            uint256 avgGasPerSuccess = totalGasUsedSuccess / successfulActions;
            console2.log("\n--- Gas Cost Summary (Initial Stakers: %d) ---", numInitialStakers);
            console2.log("  Total Successful Actions Measured: %d", successfulActions);
            console2.log("  Total Gas Used (Successful Actions): %d", totalGasUsedSuccess);
            console2.log("  Average Gas Per Successful Action: %d", avgGasPerSuccess);

            // Calculate cost based on constants defined at the top
            // Note: L2_GAS_PRICE_GWEI already includes 1e9 factor
            uint256 totalCostWei = totalGasUsedSuccess * L2_GAS_PRICE_GWEI;
            uint256 totalCostEth = totalCostWei / 1 ether; // For potential future use, not logged directly
            uint256 totalCostUsd = (totalCostWei * ETH_PRICE_USD) / 1 ether;

            console2.log("  Estimated Total Cost (Wei): %d wei", totalCostWei); // Log total cost in Wei
            // console2.log("  Estimated Total Cost (USD @ $%d/ETH): $%d.%02d", ETH_PRICE_USD, totalCostUsd / 100,
            // totalCostUsd % 100); // Keep USD calculation commented for now
            console2.log("  (Using L2 Gas Price: %d wei)", L2_GAS_PRICE_GWEI); // Log gas price in Wei
        } else {
            console2.log("\n--- Gas Cost Summary (Initial Stakers: %d) ---", numInitialStakers);
            console2.log("  No successful actions measured.");
        }

        // Final state checks (optional but good practice)
        uint256 finalTotalStaked = StakingFacet(address(diamondProxy)).totalAmountStaked();
        console2.log("Final Total Staked (after %d initial stakers): %d", numInitialStakers, finalTotalStaked);
        (bool v0Active, uint256 v0Comm, uint256 v0Total, uint256 v0Stakers) =
            ValidatorFacet(address(diamondProxy)).getValidatorStats(0);
        console2.log("Validator 0 Stats: Active=%d", v0Active);
        console2.log("Validator 0 Stats: Commission=%d, TotalStaked=%d, Stakers=%d", v0Comm, v0Total, v0Stakers);
    }

    // --- New Top-Level Test Functions ---

    function testGasAndStress_a10() public {
        _runGasAndStressTest(10, GAS_TEST_NUM_ACTIONS);
    }

    function testGasAndStress_b100() public {
        _runGasAndStressTest(100, GAS_TEST_NUM_ACTIONS);
    }

    function testGasAndStress_c500() public {
        _runGasAndStressTest(500, GAS_TEST_NUM_ACTIONS);
    }

    function testGasAndStress_d1000() public {
        _runGasAndStressTest(1000, GAS_TEST_NUM_ACTIONS);
    }

    // Note: 10k initial stakers might be very slow or hit gas limits during setup.
    // Run this specific test with increased block gas limit if needed:
    // forge test --match-path plume/test/PlumeStakingStressTest.t.sol --match-test testGasAndStress_10k --gas-limit
    // 300000000 -vv
    function testGasAndStress_e10k() public {
        // Consider increasing block gas limit for setup if this fails
        // vm.blockGasLimit(300_000_000); // Example
        _runGasAndStressTest(10_000, GAS_TEST_NUM_ACTIONS);
    }

    function testGasAndStress_f100k() public {
        // Consider increasing block gas limit for setup if this fails
        // vm.blockGasLimit(300_000_000); // Example
        _runGasAndStressTest(100_000, GAS_TEST_NUM_ACTIONS);
    }
    /*

    function testGasAndStress_g1m() public {
         // Consider increasing block gas limit for setup if this fails
         //vm.blockGasLimit(10_000_000_000); // Example
        // 9_000_000_000_000_000
        // 8 999 999 999 978 936
        // 8 999 999 999 999 978 936
        _runGasAndStressTest(1000000, GAS_TEST_NUM_ACTIONS);
    }
    */
    // --- REMOVE OLD FUNCTIONS ---
    /*
    // --- Gas Cost Measurement Tests ---

    address constant MEASUREMENT_STAKER = address(0xBAD);
    uint256 constant MEASUREMENT_STAKE_AMOUNT = 1 ether;
    uint256 constant MEASUREMENT_UNSTAKE_AMOUNT = 0.5 ether;

    function _performMeasuredActions() internal {
        // ... removed ...
    }

    function testGasCost_10_Stakers() public {
        // ... removed ...
    }

    function testGasCost_100_Stakers() public {
        // ... removed ...
    }

     function testGasCost_500_Stakers() public {
        // ... removed ...
    }

     function testGasCost_1000_Stakers() public {
        // ... removed ...
    }


    // --- Stress Test ---

    function testStress_10k_Stakers_RandomActions() public {
        // ... removed ...
    }
    */

} // End Contract
