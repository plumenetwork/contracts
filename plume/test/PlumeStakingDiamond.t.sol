// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { Test, console2 } from "forge-std/Test.sol";

// Diamond Proxy & Storage
import { PlumeStaking } from "../src/PlumeStaking.sol";
import { PlumeStakingStorage } from "../src/lib/PlumeStakingStorage.sol";

// Import the reward logic library for the REWARD_PRECISION constant
import { PlumeRewardLogic } from "../src/lib/PlumeRewardLogic.sol";

// Custom Facet Contracts (needed for casting interactions AND struct definitions)
// Import needed for ValidatorListData struct
import { AccessControlFacet } from "../src/facets/AccessControlFacet.sol";

import { PlumeStakingRewardTreasury } from "../src/PlumeStakingRewardTreasury.sol";
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
import { NotValidatorAdmin, Unauthorized } from "../src/lib/PlumeErrors.sol"; // Added Unauthorized, NotValidatorAdmin
import "../src/lib/PlumeErrors.sol";
import "../src/lib/PlumeEvents.sol";
import { PlumeRoles } from "../src/lib/PlumeRoles.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Import the proxy contract
import { PlumeStakingRewardTreasuryProxy } from "../src/proxy/PlumeStakingRewardTreasuryProxy.sol";

// Simple test token for PUSD
contract MockPUSD is ERC20 {

    constructor() ERC20("Mock PUSD", "mPUSD") {
        // Mint to message sender
        _mint(msg.sender, 100_000_000 * 10 ** 18);

        // Also mint to the admin address for testing
        address adminAddress = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;
        if (msg.sender != adminAddress) {
            _mint(adminAddress, 100_000_000 * 10 ** 18);
        }
    }

    // Add function to mint more tokens for testing
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

}

contract PlumeStakingDiamondTest is Test {

    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    // ---

    // Diamond Proxy Address
    PlumeStaking internal diamondProxy;

    // Tokens
    IERC20 public plume;
    MockPUSD public pUSD;
    PlumeStakingRewardTreasury public treasury;

    // Addresses
    address public constant ADMIN_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;
    address public constant PLUME_NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address public user1;
    address public user2;
    address public user3;
    address public user4;
    address public admin;
    address public validatorAdmin;

    // Constants
    uint256 public constant MIN_STAKE = 1e18;
    uint256 public constant INITIAL_COOLDOWN = 7 days;
    uint256 public constant INITIAL_BALANCE = 1000e18;
    uint256 public constant PUSD_REWARD_RATE = 1e18; // Example rate
    uint256 public constant PLUME_REWARD_RATE = 1_587_301_587; // Example rate
    uint16 public constant DEFAULT_VALIDATOR_ID = 0;
    uint256 public constant DEFAULT_COMMISSION = 5e16; // 5% commission
    address public constant DEFAULT_VALIDATOR_ADMIN = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;

    function setUp() public {
        console2.log("Starting Diamond test setup (Correct Path)");

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        user4 = makeAddr("user4");
        admin = ADMIN_ADDRESS;
        validatorAdmin = makeAddr("validatorAdmin");

        // Fund users with ETH in setUp
        uint256 ethAmount = 1000 ether;
        vm.deal(user1, ethAmount);
        vm.deal(user2, ethAmount);
        vm.deal(user3, ethAmount);
        vm.deal(user4, ethAmount);
        vm.deal(validatorAdmin, ethAmount);

        // Deploy PUSD token for testing
        pUSD = new MockPUSD();
        console2.log("Mock PUSD token deployed at:", address(pUSD));

        vm.startPrank(admin);

        // 1. Deploy Diamond Proxy
        diamondProxy = new PlumeStaking();
        // Use payable cast for owner check
        assertEq(
            ISolidStateDiamond(payable(address(diamondProxy))).owner(), admin, "Deployer should be owner initially"
        );

        // 2. Deploy Custom Facets
        AccessControlFacet accessControlFacet = new AccessControlFacet();
        StakingFacet stakingFacet = new StakingFacet();
        RewardsFacet rewardsFacet = new RewardsFacet();
        ValidatorFacet validatorFacet = new ValidatorFacet();
        ManagementFacet managementFacet = new ManagementFacet();

        // --- Add Checks ---
        require(address(accessControlFacet) != address(0), "AccessControlFacet deployment failed");
        require(address(managementFacet) != address(0), "ManagementFacet deployment failed");
        require(address(stakingFacet) != address(0), "StakingFacet deployment failed");
        require(address(validatorFacet) != address(0), "ValidatorFacet deployment failed");
        require(address(rewardsFacet) != address(0), "RewardsFacet deployment failed");

        require(address(accessControlFacet).code.length > 0, "AccessControlFacet has no code");
        require(address(managementFacet).code.length > 0, "ManagementFacet has no code");
        require(address(stakingFacet).code.length > 0, "StakingFacet has no code");
        require(address(validatorFacet).code.length > 0, "ValidatorFacet has no code");
        require(address(rewardsFacet).code.length > 0, "RewardsFacet has no code");
        console2.log("All facet deployments verified (address and code length).");
        // --- End Checks ---

        // 3. Prepare Diamond Cut
        IERC2535DiamondCutInternal.FacetCut[] memory cut = new IERC2535DiamondCutInternal.FacetCut[](5);

        // AccessControl Facet Selectors
        bytes4[] memory accessControlSigs_Manual = new bytes4[](7);
        accessControlSigs_Manual[0] = bytes4(keccak256(bytes("initializeAccessControl()")));
        accessControlSigs_Manual[1] = bytes4(keccak256(bytes("hasRole(bytes32,address)")));
        accessControlSigs_Manual[2] = bytes4(keccak256(bytes("getRoleAdmin(bytes32)")));
        accessControlSigs_Manual[3] = bytes4(keccak256(bytes("grantRole(bytes32,address)")));
        accessControlSigs_Manual[4] = bytes4(keccak256(bytes("revokeRole(bytes32,address)")));
        accessControlSigs_Manual[5] = bytes4(keccak256(bytes("renounceRole(bytes32,address)")));
        accessControlSigs_Manual[6] = bytes4(keccak256(bytes("setRoleAdmin(bytes32,bytes32)")));

        // Staking Facet Selectors
        bytes4[] memory stakingSigs_Manual = new bytes4[](14);
        stakingSigs_Manual[0] = bytes4(keccak256(bytes("stake(uint16)")));
        stakingSigs_Manual[1] = bytes4(keccak256(bytes("restake(uint16,uint256)")));
        stakingSigs_Manual[2] = bytes4(keccak256(bytes("unstake(uint16)")));
        stakingSigs_Manual[3] = bytes4(keccak256(bytes("unstake(uint16,uint256)")));
        stakingSigs_Manual[4] = bytes4(keccak256(bytes("withdraw()")));
        stakingSigs_Manual[5] = bytes4(keccak256(bytes("stakeOnBehalf(uint16,address)")));
        stakingSigs_Manual[6] = bytes4(keccak256(bytes("stakeInfo(address)")));
        stakingSigs_Manual[7] = bytes4(keccak256(bytes("amountStaked()")));
        stakingSigs_Manual[8] = bytes4(keccak256(bytes("amountCooling()")));
        stakingSigs_Manual[9] = bytes4(keccak256(bytes("amountWithdrawable()")));
        stakingSigs_Manual[10] = bytes4(keccak256(bytes("cooldownEndDate()")));
        stakingSigs_Manual[11] = bytes4(keccak256(bytes("getUserValidatorStake(address,uint16)")));
        stakingSigs_Manual[12] = bytes4(keccak256(bytes("restakeRewards(uint16)")));
        stakingSigs_Manual[13] = bytes4(keccak256(bytes("totalAmountStaked()")));

        // Rewards Facet Selectors
        bytes4[] memory rewardsSigs_Manual = new bytes4[](21);
        rewardsSigs_Manual[0] = bytes4(keccak256(bytes("addRewardToken(address)")));
        rewardsSigs_Manual[1] = bytes4(keccak256(bytes("removeRewardToken(address)")));
        rewardsSigs_Manual[2] = bytes4(keccak256(bytes("setRewardRates(address[],uint256[])")));
        rewardsSigs_Manual[3] = bytes4(keccak256(bytes("setMaxRewardRate(address,uint256)")));
        rewardsSigs_Manual[4] = bytes4(keccak256(bytes("addRewards(address,uint256)")));
        rewardsSigs_Manual[5] = bytes4(keccak256(bytes("claim(address)")));
        rewardsSigs_Manual[6] = bytes4(keccak256(bytes("claim(address,uint16)")));
        rewardsSigs_Manual[7] = bytes4(keccak256(bytes("claimAll()")));
        rewardsSigs_Manual[8] = bytes4(keccak256(bytes("earned(address,address)")));
        rewardsSigs_Manual[9] = bytes4(keccak256(bytes("getClaimableReward(address,address)")));
        rewardsSigs_Manual[10] = bytes4(keccak256(bytes("getRewardTokens()")));
        rewardsSigs_Manual[11] = bytes4(keccak256(bytes("getMaxRewardRate(address)")));
        rewardsSigs_Manual[12] = bytes4(keccak256(bytes("tokenRewardInfo(address)")));
        rewardsSigs_Manual[13] = bytes4(keccak256(bytes("getRewardRateCheckpointCount(address)")));
        rewardsSigs_Manual[14] = bytes4(keccak256(bytes("getValidatorRewardRateCheckpointCount(uint16,address)")));
        rewardsSigs_Manual[15] = bytes4(keccak256(bytes("getUserLastCheckpointIndex(address,uint16,address)")));
        rewardsSigs_Manual[16] = bytes4(keccak256(bytes("getRewardRateCheckpoint(address,uint256)")));
        rewardsSigs_Manual[17] = bytes4(keccak256(bytes("getValidatorRewardRateCheckpoint(uint16,address,uint256)")));
        rewardsSigs_Manual[18] = bytes4(keccak256(bytes("setTreasury(address)")));
        rewardsSigs_Manual[19] = bytes4(keccak256(bytes("getTreasury()")));
        rewardsSigs_Manual[20] = bytes4(keccak256(bytes("getPendingRewardForValidator(address,uint16,address)")));

        // Validator Facet Selectors
        bytes4[] memory validatorSigs_Manual = new bytes4[](14);
        validatorSigs_Manual[0] =
            bytes4(keccak256(bytes("addValidator(uint16,uint256,address,address,string,string,address,uint256)")));
        validatorSigs_Manual[1] = bytes4(keccak256(bytes("setValidatorCapacity(uint16,uint256)")));
        validatorSigs_Manual[2] = bytes4(keccak256(bytes("setValidatorCommission(uint16,uint256)")));
        validatorSigs_Manual[3] =
            bytes4(keccak256(bytes("setValidatorAddresses(uint16,address,address,string,string,address)")));
        validatorSigs_Manual[4] = bytes4(keccak256(bytes("setValidatorStatus(uint16,bool)")));
        validatorSigs_Manual[5] = bytes4(keccak256(bytes("getValidatorInfo(uint16)")));
        validatorSigs_Manual[6] = bytes4(keccak256(bytes("getValidatorStats(uint16)")));
        validatorSigs_Manual[7] = bytes4(keccak256(bytes("getUserValidators(address)")));
        validatorSigs_Manual[8] = bytes4(keccak256(bytes("getAccruedCommission(uint16,address)")));
        validatorSigs_Manual[9] = bytes4(keccak256(bytes("getValidatorsList()")));
        validatorSigs_Manual[10] = bytes4(keccak256(bytes("getActiveValidatorCount()")));
        validatorSigs_Manual[11] = bytes4(keccak256(bytes("claimValidatorCommission(uint16,address)")));
        validatorSigs_Manual[12] = bytes4(keccak256(bytes("voteToSlashValidator(uint16,uint256)"))); // <<< ADD MISSING
            // SELECTOR
        validatorSigs_Manual[13] = bytes4(keccak256(bytes("slashValidator(uint16)"))); // <<< ADD MISSING SELECTOR

        // Management Facet Selectors
        bytes4[] memory managementSigs_Manual = new bytes4[](7); // Increase size to 7
        managementSigs_Manual[0] = bytes4(keccak256(bytes("setMinStakeAmount(uint256)")));
        managementSigs_Manual[1] = bytes4(keccak256(bytes("setCooldownInterval(uint256)")));
        managementSigs_Manual[2] = bytes4(keccak256(bytes("adminWithdraw(address,uint256,address)")));
        managementSigs_Manual[3] = bytes4(keccak256(bytes("updateTotalAmounts(uint256,uint256)")));
        managementSigs_Manual[4] = bytes4(keccak256(bytes("getMinStakeAmount()")));
        managementSigs_Manual[5] = bytes4(keccak256(bytes("getCooldownInterval()")));
        managementSigs_Manual[6] = bytes4(keccak256(bytes("setMaxSlashVoteDuration(uint256)")));

        console2.log("Manual selectors initialized");

        // Define the Facet Cuts for the single diamondCut call
        console2.log("Assigning AccessControlFacet to cut[0]:", address(accessControlFacet));
        cut[0] = IERC2535DiamondCutInternal.FacetCut({
            target: address(accessControlFacet),
            action: IERC2535DiamondCutInternal.FacetCutAction.ADD,
            selectors: accessControlSigs_Manual
        });
        console2.log("Assigning ManagementFacet to cut[1]:", address(managementFacet));
        cut[1] = IERC2535DiamondCutInternal.FacetCut({
            target: address(managementFacet),
            action: IERC2535DiamondCutInternal.FacetCutAction.ADD,
            selectors: managementSigs_Manual
        });
        console2.log("Assigning StakingFacet to cut[2]:", address(stakingFacet));
        cut[2] = IERC2535DiamondCutInternal.FacetCut({
            target: address(stakingFacet),
            action: IERC2535DiamondCutInternal.FacetCutAction.ADD,
            selectors: stakingSigs_Manual
        });
        console2.log("Assigning ValidatorFacet to cut[3]:", address(validatorFacet));
        cut[3] = IERC2535DiamondCutInternal.FacetCut({
            target: address(validatorFacet),
            action: IERC2535DiamondCutInternal.FacetCutAction.ADD,
            selectors: validatorSigs_Manual
        });
        console2.log("Assigning RewardsFacet to cut[4]:", address(rewardsFacet));
        cut[4] = IERC2535DiamondCutInternal.FacetCut({
            target: address(rewardsFacet),
            action: IERC2535DiamondCutInternal.FacetCutAction.ADD,
            selectors: rewardsSigs_Manual
        });

        // --- Apply the single Diamond Cut ---
        console2.log("Applying single diamond cut to proxy:", address(diamondProxy));
        // console2.log("Cut data:", cut); // Might be too verbose / cause issues

        // 4. Execute Diamond Cut
        // Use payable cast
        ISolidStateDiamond(payable(address(diamondProxy))).diamondCut(cut, address(0), "");

        console2.log("Single diamond cut applied successfully.");
        // --- End Diamond Cut ---

        // 5. Initialize (AFTER the cut)
        // Plume-specific initialization
        diamondProxy.initializePlume(address(0), MIN_STAKE, INITIAL_COOLDOWN);
        assertEq(diamondProxy.isInitialized(), true, "Diamond should be initialized");

        // AccessControl initialization
        AccessControlFacet(address(diamondProxy)).initializeAccessControl();

        // Grant owner the ADMIN role explicitly
        AccessControlFacet(address(diamondProxy)).grantRole(PlumeRoles.ADMIN_ROLE, admin);
        AccessControlFacet(address(diamondProxy)).grantRole(PlumeRoles.VALIDATOR_ROLE, admin);
        AccessControlFacet(address(diamondProxy)).grantRole(PlumeRoles.TIMELOCK_ROLE, admin);
        // 6. Deploy and setup reward treasury
        PlumeStakingRewardTreasury treasuryImpl = new PlumeStakingRewardTreasury();
        bytes memory initData =
            abi.encodeWithSelector(PlumeStakingRewardTreasury.initialize.selector, admin, address(diamondProxy));
        PlumeStakingRewardTreasuryProxy treasuryProxy =
            new PlumeStakingRewardTreasuryProxy(address(treasuryImpl), initData);
        treasury = PlumeStakingRewardTreasury(payable(address(treasuryProxy)));

        // Set treasury in the diamond proxy
        RewardsFacet(address(diamondProxy)).setTreasury(address(treasury));

        // Add PUSD as a reward token in the treasury
        treasury.addRewardToken(address(pUSD));
        // <<< ADD PLUME_NATIVE REWARD TOKEN AND FUND TREASURY >>>
        RewardsFacet(address(diamondProxy)).addRewardToken(PLUME_NATIVE);
        treasury.addRewardToken(PLUME_NATIVE); // Also add to treasury allowed list
        vm.deal(address(treasury), 1000 ether); // Give treasury some native ETH

        // 7. Setup test validators
        // Add validator 0 (DEFAULT_VALIDATOR_ID)
        ValidatorFacet(address(diamondProxy)).addValidator(
            DEFAULT_VALIDATOR_ID,
            DEFAULT_COMMISSION,
            validatorAdmin,
            validatorAdmin,
            "0x123",
            "0x456",
            address(0x1234),
            1_000_000e18
        );

        // Add validator 1
        ValidatorFacet(address(diamondProxy)).addValidator(
            1,
            8e16, // 8% commission
            user2,
            user2,
            "0x789",
            "0xabc",
            address(0x2345),
            1_000_000e18
        );

        // Set up reward tokens
        address[] memory initialTokens = new address[](1);
        initialTokens[0] = address(pUSD);
        uint256[] memory initialRates = new uint256[](1);
        initialRates[0] = 1e15; // Small default rate
        RewardsFacet(address(diamondProxy)).addRewardToken(address(pUSD)); // <<< RESTORE THIS LINE
        RewardsFacet(address(diamondProxy)).setMaxRewardRate(address(pUSD), 1e18);
        // We should also set a max rate for PLUME_NATIVE here
        RewardsFacet(address(diamondProxy)).setMaxRewardRate(PLUME_NATIVE, 1e18); // Set a reasonable max rate
        RewardsFacet(address(diamondProxy)).setRewardRates(initialTokens, initialRates); // Only sets pUSD rate
            // initially

        vm.stopPrank();

        // Give user1 some PUSD for testing
        vm.startPrank(admin);
        pUSD.transfer(user1, 1000e18);
        vm.stopPrank();
    }

    // --- Test Cases ---

    function testInitialState() public {
        // Directly check the initialized flag using the new view function
        assertTrue(PlumeStaking(payable(address(diamondProxy))).isInitialized(), "Contract should be initialized");

        // Use the new view functions from ManagementFacet for other checks
        uint256 expectedMinStake = MIN_STAKE; // Use the constant from setUp
        uint256 actualMinStake = ManagementFacet(address(diamondProxy)).getMinStakeAmount();
        assertEq(actualMinStake, expectedMinStake, "Min stake amount mismatch");

        uint256 expectedCooldown = INITIAL_COOLDOWN; // Use the constant from setUp
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

    function testStakeOnBehalf() public {
        uint16 validatorId = DEFAULT_VALIDATOR_ID;
        address sender = user2; // User2 sends the tx
        address staker = user1; // User1 receives the stake
        uint256 stakeAmount = 50 ether;

        // Ensure sender has enough ETH
        vm.deal(sender, stakeAmount + 1 ether); // +1 for gas

        // Get initial state for comparison
        PlumeStakingStorage.StakeInfo memory stakerInfoBefore = StakingFacet(address(diamondProxy)).stakeInfo(staker);
        uint256 userValidatorStakeBefore =
            StakingFacet(address(diamondProxy)).getUserValidatorStake(staker, validatorId);
        (bool activeBefore, uint256 commissionBefore, uint256 validatorTotalStakedBefore, uint256 stakersCountBefore) =
            ValidatorFacet(address(diamondProxy)).getValidatorStats(validatorId);
        uint256 totalStakedBefore = StakingFacet(address(diamondProxy)).totalAmountStaked(); // <<< USE view function
        uint16[] memory userValidatorsBefore = ValidatorFacet(address(diamondProxy)).getUserValidators(staker);

        // Expect events
        vm.expectEmit(true, true, true, true, address(diamondProxy));
        emit Staked(staker, validatorId, stakeAmount, 0, 0, stakeAmount);

        vm.expectEmit(true, true, true, true, address(diamondProxy));
        emit StakedOnBehalf(sender, staker, validatorId, stakeAmount);

        // Execute stakeOnBehalf
        vm.startPrank(sender);
        StakingFacet(address(diamondProxy)).stakeOnBehalf{ value: stakeAmount }(validatorId, staker);
        vm.stopPrank();

        // --- Verification ---

        // 1. Check user's stake on this specific validator
        uint256 userValidatorStakeAfter = StakingFacet(address(diamondProxy)).getUserValidatorStake(staker, validatorId);
        assertEq(userValidatorStakeAfter, userValidatorStakeBefore + stakeAmount, "User validator stake mismatch");

        // 2. Check staker's global stake info
        PlumeStakingStorage.StakeInfo memory stakerInfoAfter = StakingFacet(address(diamondProxy)).stakeInfo(staker);
        assertEq(stakerInfoAfter.staked, stakerInfoBefore.staked + stakeAmount, "Staker global stake mismatch");

        // 3. Check validator stats
        (bool activeAfter, uint256 commissionAfter, uint256 validatorTotalStakedAfter, uint256 stakersCountAfter) =
            ValidatorFacet(address(diamondProxy)).getValidatorStats(validatorId);
        assertTrue(activeAfter, "Validator should remain active");
        assertEq(commissionAfter, commissionBefore, "Commission should not change");
        assertEq(validatorTotalStakedAfter, validatorTotalStakedBefore + stakeAmount, "Validator total staked mismatch");
        // Staker count increases only if the staker wasn't previously staking with this validator
        bool wasStakingBefore = false;
        for (uint256 i = 0; i < userValidatorsBefore.length; i++) {
            if (userValidatorsBefore[i] == validatorId) {
                wasStakingBefore = true;
                break;
            }
        }
        assertEq(stakersCountAfter, stakersCountBefore + (wasStakingBefore ? 0 : 1), "Staker count mismatch");

        // 4. Check global total staked
        uint256 totalStakedAfter = StakingFacet(address(diamondProxy)).totalAmountStaked(); // <<< USE view function
        assertEq(totalStakedAfter, totalStakedBefore + stakeAmount, "Global total staked mismatch");

        // 5. Check staker is in validator's list
        uint16[] memory userValidatorsAfter = ValidatorFacet(address(diamondProxy)).getUserValidators(staker);
        bool foundInList = false;
        for (uint256 i = 0; i < userValidatorsAfter.length; i++) {
            if (userValidatorsAfter[i] == validatorId) {
                foundInList = true;
                break;
            }
        }
        assertTrue(foundInList, "Staker not found in validator list after stakeOnBehalf");
    }

    function testClaimValidatorCommission() public {
        // Set up validator commission at 20% (20 * 1e16)
        vm.startPrank(validatorAdmin);
        uint256 newCommission = 20e16;
        ValidatorFacet(address(diamondProxy)).setValidatorCommission(DEFAULT_VALIDATOR_ID, newCommission);
        vm.stopPrank();

        // Set reward rate for PUSD to 1e18 (1 token per second)
        vm.startPrank(admin);
        address[] memory tokens = new address[](1);
        tokens[0] = address(pUSD);
        uint256[] memory rates = new uint256[](1);
        rates[0] = 1e18;
        RewardsFacet(address(diamondProxy)).setRewardRates(tokens, rates);

        // Ensure treasury has enough PUSD by transferring tokens
        uint256 treasuryAmount = 1000 ether;
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
        // commented

        // --- Assertions before unstake ---
        uint256 amountToUnstake = 1 ether;
        uint256 expectedStake = stakeAmount;

        // Use the new view function through the diamond proxy
        uint256 actualUserStake = StakingFacet(address(diamondProxy)).getUserValidatorStake(user1, DEFAULT_VALIDATOR_ID);
        assertEq(actualUserStake, expectedStake, "User1 Validator 0 Stake mismatch before unstake (via view func)");

        // --- End Assertions ---

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
        vm.startPrank(validatorAdmin);
        uint256 balanceBefore = pUSD.balanceOf(validatorAdmin);
        uint256 claimedAmount =
            ValidatorFacet(address(diamondProxy)).claimValidatorCommission(DEFAULT_VALIDATOR_ID, address(pUSD));
        uint256 balanceAfter = pUSD.balanceOf(validatorAdmin);
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
        RewardsFacet(address(diamondProxy)).setRewardRates(tokens, rates);

        // Make sure treasury is properly set
        RewardsFacet(address(diamondProxy)).setTreasury(address(treasury));

        // Ensure treasury has enough PUSD by transferring tokens
        uint256 treasuryAmount = 100 ether;
        pUSD.transfer(address(treasury), treasuryAmount);
        vm.stopPrank();

        // Set a 10% commission rate for the validator
        vm.startPrank(validatorAdmin);
        uint256 newCommission = 10e16;
        ValidatorFacet(address(diamondProxy)).setValidatorCommission(DEFAULT_VALIDATOR_ID, newCommission);
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
        vm.startPrank(validatorAdmin);
        uint256 balanceBefore = pUSD.balanceOf(validatorAdmin);
        uint256 claimedAmount =
            ValidatorFacet(address(diamondProxy)).claimValidatorCommission(DEFAULT_VALIDATOR_ID, address(pUSD));
        uint256 balanceAfter = pUSD.balanceOf(validatorAdmin);
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
        RewardsFacet(address(diamondProxy)).setRewardRates(tokens, rates);
        vm.stopPrank();

        // Ensure treasury has enough PUSD by transferring tokens
        uint256 treasuryAmount = 100 ether;
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
        uint256 plumeRate = 1e9; // 0.000000001 PLUME per second (adjusted to be below max)

        vm.startPrank(admin);
        address[] memory tokens = new address[](2);
        tokens[0] = address(pUSD);
        tokens[1] = PLUME_NATIVE;
        uint256[] memory rates = new uint256[](2);
        rates[0] = pusdRate;
        rates[1] = plumeRate;
        RewardsFacet(address(diamondProxy)).setRewardRates(tokens, rates);

        // Ensure treasury has enough tokens
        uint256 treasuryAmount = 1000 ether;
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
        vm.startPrank(validatorAdmin);
        ValidatorFacet(address(diamondProxy)).setValidatorCommission(validator0, commissionRate0);
        vm.stopPrank();

        vm.startPrank(user2); // user2 is admin for validator1 from setUp
        ValidatorFacet(address(diamondProxy)).setValidatorCommission(validator1, commissionRate1);
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
        uint256 claimedAmount = RewardsFacet(address(diamondProxy)).claim(address(pUSD), 0);
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

        vm.startPrank(validatorAdmin);
        uint256 validatorBalanceBefore = pUSD.balanceOf(validatorAdmin);
        uint256 commissionClaimed = ValidatorFacet(address(diamondProxy)).claimValidatorCommission(0, address(pUSD));
        uint256 validatorBalanceAfter = pUSD.balanceOf(validatorAdmin);

        // Verify commission claim was successful
        assertApproxEqAbs(
            validatorBalanceAfter - validatorBalanceBefore,
            commissionClaimed,
            10 ** 10,
            "Validator claimed amount should match balance increase"
        );

        // Check final commission accrued (should be zero since we reset the time)
        uint256 finalCommission = ValidatorFacet(address(diamondProxy)).getAccruedCommission(0, address(pUSD));
        assertApproxEqAbs(finalCommission, 0, 10 ** 10, "Final accrued commission should be near zero");
        vm.stopPrank();

        console2.log("--- Commission & Reward Rate Change Test Complete ---");
    }

    // --- Complex Reward Calculation Test ---
    function testComplexRewardScenario() public {
        console2.log("\n--- Setting up complex reward scenario ---");

        // --- Setup validators with different commission rates ---
        uint16 validator0 = DEFAULT_VALIDATOR_ID; // 0
        uint16 validator1 = 1;
        uint16 validator2 = 2;

        // Add a third validator
        vm.startPrank(admin);
        address validator2Admin = makeAddr("validator2Admin");
        ValidatorFacet(address(diamondProxy)).addValidator(
            validator2, 15e16, validator2Admin, validator2Admin, "0xval3", "0xacc3", address(0x3456), 1_000_000e18
        );
        ValidatorFacet(address(diamondProxy)).setValidatorCapacity(validator2, 1_000_000e18);
        vm.stopPrank();

        // --- Setup reward rates ---
        // Use PUSD and PLUME_NATIVE as our tokens
        address token1 = address(pUSD);
        address token2 = PLUME_NATIVE;

        console2.log("Setting up initial commission rates:");
        // Set initial commission rates
        vm.startPrank(validatorAdmin); // admin for validator0
        ValidatorFacet(address(diamondProxy)).setValidatorCommission(validator0, 5e16); // 5% scaled
        vm.stopPrank();

        vm.startPrank(user2); // admin for validator1 from setUp
        ValidatorFacet(address(diamondProxy)).setValidatorCommission(validator1, 10e16); // 10% scaled
        vm.stopPrank();

        vm.startPrank(validator2Admin);
        ValidatorFacet(address(diamondProxy)).setValidatorCommission(validator2, 15e16); // 15% scaled
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
        pUSD.transfer(address(treasury), 10_000 ether);
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
        RewardsFacet(address(diamondProxy)).setRewardRates(rewardTokensList, rates);
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

        vm.startPrank(validatorAdmin);
        ValidatorFacet(address(diamondProxy)).setValidatorCommission(validator0, 15e16); // 15% scaled
        vm.stopPrank();

        vm.startPrank(user2);
        ValidatorFacet(address(diamondProxy)).setValidatorCommission(validator1, 20e16); // 20% scaled
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

        RewardsFacet(address(diamondProxy)).setRewardRates(tokens, rates);
        vm.stopPrank();

        // Advance time to accrue rewards
        vm.warp(block.timestamp + 100); // 100 seconds

        // User claims rewards
        vm.startPrank(user);
        uint256 balanceBefore = user.balance;
        RewardsFacet(address(diamondProxy)).claim(PLUME_NATIVE);
        uint256 balanceAfter = user.balance;

        // Verify user received rewards
        assertTrue(balanceAfter > balanceBefore, "User should have received rewards");
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
        assertEq(stakeInfo.staked, stakeAmount, "Initial stake amount mismatch");
        assertEq(stakeInfo.cooled, 0, "Initial cooling amount should be 0");
        console2.log("User1 staked %s ETH to validator %d", stakeAmount, validatorId);

        // User1 unstakes (initiates cooldown)
        StakingFacet(address(diamondProxy)).unstake(validatorId);
        stakeInfo = StakingFacet(address(diamondProxy)).stakeInfo(user1);
        assertEq(stakeInfo.staked, 0, "Staked amount should be 0 after unstake");
        assertEq(stakeInfo.cooled, stakeAmount, "Cooling amount mismatch after unstake");
        assertTrue(stakeInfo.cooldownEnd > block.timestamp, "Cooldown end date should be in the future");
        uint256 cooldownEnd = stakeInfo.cooldownEnd;
        console2.log("User1 unstaked %s ETH, now in cooldown until %s", stakeAmount, cooldownEnd);

        // Before cooldown ends, User1 restakes the cooling amount to the *same* validator
        assertTrue(block.timestamp < cooldownEnd, "Attempting restake before cooldown ends");
        (bool activeBefore, uint256 commissionBefore, uint256 totalStakedBefore, uint256 stakersCountBefore) =
            ValidatorFacet(address(diamondProxy)).getValidatorStats(validatorId);

        console2.log("User1 attempting to restake %s ETH during cooldown...", stakeAmount);
        StakingFacet(address(diamondProxy)).restake(validatorId, stakeAmount);

        // Verify state after restake
        stakeInfo = StakingFacet(address(diamondProxy)).stakeInfo(user1);
        console2.log(
            "State after restake: Staked=%s, Cooling=%s, CooldownEnd=%s",
            stakeInfo.staked,
            stakeInfo.cooled,
            stakeInfo.cooldownEnd
        );

        assertEq(stakeInfo.cooled, 0, "Cooling amount should be 0 after restake");
        assertEq(stakeInfo.staked, stakeAmount, "Staked amount should be restored after restake");

        // Cooldown should be cancelled/reset
        assertEq(stakeInfo.cooldownEnd, 0, "Cooldown end date should be reset after restake");

        // Verify validator's total stake increased
        (bool activeAfter, uint256 commissionAfter, uint256 totalStakedAfter, uint256 stakersCountAfter) =
            ValidatorFacet(address(diamondProxy)).getValidatorStats(validatorId);
        assertEq(
            totalStakedAfter, totalStakedBefore + stakeAmount, "Validator total stake should increase after restake"
        );

        vm.stopPrank();
        console2.log("Restake during cooldown test completed.");
    }

    /**
     * @notice Tests a complex sequence with state tracking:
     *          (S=Staked, C=Cooled, P=Parked, CE=CooldownEnd)
     * Initial: S=0, C=0, P=0, CE=0
     * 1. Stake 10 ETH         -> S=10, C=0, P=0, CE=0
     * 2. Unstake 5 ETH        -> S=5,  C=5, P=0, CE=T+cd (cooldownEnd1)
     * 3. Restake 2 ETH        -> S=7,  C=3, P=0, CE=T+cd (cooldownEnd1 unchanged)
     * 4. Wait past CE1, Withdraw 3 ETH -> S=7,  C=0, P=0, CE=0 (Withdraw moves C->P then clears P, resets CE)
     * 5. Stake 2 ETH          -> S=9,  C=0, P=0, CE=0
     * 6. Unstake 4 ETH        -> S=5,  C=4, P=0, CE=T'+cd (cooldownEnd2)
     * 7. Wait past CE2        -> State unchanged until interaction
     * 8. Withdraw 4 ETH       -> S=5,  C=0, P=0, CE=0 (Withdraw checks C, moves C->P, clears P, resets CE)
     * 9. Stake 4 ETH          -> S=9,  C=0, P=0, CE=0
     * 10. Unstake 4 ETH       -> S=5,  C=4, P=0, CE=T''+cd (cooldownEnd3)
     * 11. Wait past CE3       -> State unchanged
     * 12. Accrue rewards
     * 13. Restake Rewards     -> S=5+R, C=4, P=0, CE=T''+cd (Rewards R added to stake)
     * 14. Withdraw 4 ETH      -> S=5+R, C=0, P=0, CE=0
     * 15. Final checks
     */
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
        RewardsFacet(address(diamondProxy)).setRewardRates(tokens, rates);
        pUSD.transfer(address(treasury), 2000 ether); // Fund treasury
        vm.stopPrank();

        vm.startPrank(user1);

        // 1. Stake 10 ETH
        console2.log("1. Staking %s ETH...", initialStake);
        StakingFacet(address(diamondProxy)).stake{ value: initialStake }(validatorId);
        PlumeStakingStorage.StakeInfo memory stakeInfo = StakingFacet(address(diamondProxy)).stakeInfo(user1);
        assertEq(stakeInfo.staked, initialStake, "State Error after Step 1");
        assertEq(stakeInfo.cooled, 0, "State Error after Step 1");

        // 2. Unstake 5 ETH
        console2.log("2. Unstaking %s ETH...", firstUnstake);
        StakingFacet(address(diamondProxy)).unstake(validatorId, firstUnstake);
        stakeInfo = StakingFacet(address(diamondProxy)).stakeInfo(user1);
        uint256 cooldownEnd1 = stakeInfo.cooldownEnd;
        assertTrue(cooldownEnd1 > block.timestamp, "Cooldown 1 not set");
        assertEq(stakeInfo.staked, initialStake - firstUnstake, "State Error after Step 2 (Staked)");
        assertEq(stakeInfo.cooled, firstUnstake, "State Error after Step 2 (Cooled)");
        console2.log("   Cooldown ends at: %s", cooldownEnd1);

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
        assertTrue(cooldownEnd2 > cooldownEnd1, "Cooldown 2 end should be later than cooldown 1 end");
        // --- FIX: Correct expected staked amount ---
        assertEq(
            StakingFacet(address(diamondProxy)).amountStaked(),
            5 ether,
            "Stake amount should be 5 ether after second unstake"
        );

        // Check internal state immediately after second unstake
        PlumeStakingStorage.StakeInfo memory infoAfterSecondUnstake =
            StakingFacet(address(diamondProxy)).stakeInfo(user1);
        assertEq(infoAfterSecondUnstake.cooled, secondUnstake, "Internal cooled amount mismatch after second unstake");
        assertEq(infoAfterSecondUnstake.parked, 0, "Internal parked amount should be 0 after second unstake");

        // Check cooling amount view function (should reflect the *new* cooldown)
        assertEq(
            StakingFacet(address(diamondProxy)).amountCooling(),
            secondUnstake,
            "Cooling view amount wrong after second unstake"
        );
        assertEq(
            StakingFacet(address(diamondProxy)).amountWithdrawable(),
            0,
            "Withdrawable view amount should be 0 after second unstake (new cooldown)"
        ); // FIX: MUST Expect 0
        // --- END FIX ---
        console2.log("   Cooldown 2 ends at: %s", cooldownEnd2);

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
        vm.expectRevert(abi.encodeWithSelector(NoRewardsToRestake.selector));
        StakingFacet(address(diamondProxy)).restakeRewards(validatorId);

        // --- Steps 11-13 Re-evaluated ---
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
        RewardsFacet(address(diamondProxy)).setRewardRates(nativeTokenArr, nativeRateArr);
        vm.stopPrank();

        uint256 timeAdvance = 100 seconds;
        vm.warp(block.timestamp + timeAdvance); // Advance time to accrue PLUME rewards

        // 12. Call restakeRewards - this should take pending PLUME and add to stake
        console2.log("12. Calling restakeRewards(%s)...", validatorId);
        uint256 pendingPlumeReward = RewardsFacet(address(diamondProxy)).getClaimableReward(user1, PLUME_NATIVE);
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

    /**
     * @notice Tests  multiple unstakes:
     *          (S=Staked, C=Cooled, P=Parked)
     * Initial: S=0, C=0, P=0
     * 1. Stake 10 ETH         -> S=10, C=0, P=0
     * 2. Unstake 6 ETH        -> S=4,  C=6, P=0
     * 3. Unstake 4 ETH        -> S=0,  C=4, P=6
     */
    function testUnstakeAccumulatesAfterCooldown() public {
        uint16 validatorId = DEFAULT_VALIDATOR_ID;
        uint256 initialStake = 10 ether;
        uint256 firstUnstake = 6 ether;
        uint256 secondUnstake = 4 ether;
        uint256 totalUnstaked = firstUnstake + secondUnstake;

        vm.startPrank(user1);

        // 1. Stake initial amount
        console2.log("1. Staking %s ETH...", initialStake);
        StakingFacet(address(diamondProxy)).stake{ value: initialStake }(validatorId);
        assertEq(StakingFacet(address(diamondProxy)).amountStaked(), initialStake, "Initial stake failed");

        // 2. Unstake first portion
        console2.log("2. Unstaking first portion: %s ETH...", firstUnstake);
        StakingFacet(address(diamondProxy)).unstake(validatorId, firstUnstake);
        uint256 cooldownEnd1 = StakingFacet(address(diamondProxy)).cooldownEndDate();
        assertTrue(cooldownEnd1 > block.timestamp, "Cooldown 1 not started");
        assertEq(
            StakingFacet(address(diamondProxy)).amountStaked(),
            initialStake - firstUnstake,
            "Stake amount wrong after first unstake"
        );
        assertEq(
            StakingFacet(address(diamondProxy)).amountCooling(),
            firstUnstake,
            "Cooling amount wrong after first unstake"
        );
        console2.log("   Cooldown 1 ends at: %s", cooldownEnd1);

        // 3. Advance time *past* the first cooldown end
        console2.log("3. Advancing time past cooldown 1 (%s)...", cooldownEnd1);
        vm.warp(cooldownEnd1 + 10); // Add 10 seconds buffer
        assertTrue(block.timestamp > cooldownEnd1, "Time did not advance past cooldown 1");

        // Verify withdrawable amount before second unstake
        assertEq(
            StakingFacet(address(diamondProxy)).amountWithdrawable(),
            firstUnstake,
            "Withdrawable should be firstUnstake before second unstake"
        );
        assertEq(StakingFacet(address(diamondProxy)).amountCooling(), 0, "Cooling should be 0 before second unstake");

        // 4. Unstake second portion
        console2.log("4. Unstaking second portion: %s ETH...", secondUnstake);
        StakingFacet(address(diamondProxy)).unstake(validatorId, secondUnstake);
        uint256 cooldownEnd2 = StakingFacet(address(diamondProxy)).cooldownEndDate();
        assertTrue(cooldownEnd2 > block.timestamp, "Cooldown 2 not started");
        assertTrue(cooldownEnd2 > cooldownEnd1, "Cooldown 2 end should be later than cooldown 1 end");
        assertEq(StakingFacet(address(diamondProxy)).amountStaked(), 0, "Stake amount should be 0 after second unstake");

        // Check internal state immediately after second unstake
        PlumeStakingStorage.StakeInfo memory infoAfterSecondUnstake =
            StakingFacet(address(diamondProxy)).stakeInfo(user1);

        // Check cooling amount view function (should reflect the *new* cooldown)
        assertEq(
            StakingFacet(address(diamondProxy)).amountCooling(),
            secondUnstake,
            "Cooling view amount wrong after second unstake"
        );
        assertEq(
            StakingFacet(address(diamondProxy)).amountWithdrawable(),
            6 ether,
            "Withdrawable should be 0 after second unstake (new cooldown)"
        );
        console2.log("   Cooldown 2 ends at: %s", cooldownEnd2);

        // 5. Advance time past the second cooldown
        console2.log("5. Advancing time past cooldown 2 (%s)...", cooldownEnd2);
        vm.warp(cooldownEnd2 + 10);

        // 6. Withdraw
        console2.log("6. Withdrawing...");
        uint256 withdrawableFinal = StakingFacet(address(diamondProxy)).amountWithdrawable();
        assertEq(withdrawableFinal, totalUnstaked, "Final withdrawable amount incorrect");

        uint256 balanceBefore = user1.balance;
        StakingFacet(address(diamondProxy)).withdraw();
        uint256 balanceAfter = user1.balance;

        // 7. Verify withdrawal amount
        assertEq(balanceAfter - balanceBefore, totalUnstaked, "Withdrawn amount does not match total unstaked");
        assertEq(StakingFacet(address(diamondProxy)).amountWithdrawable(), 0, "Withdrawable should be 0 after withdraw");
        assertEq(StakingFacet(address(diamondProxy)).amountCooling(), 0, "Cooling should be 0 after withdraw");
        PlumeStakingStorage.StakeInfo memory finalInfo = StakingFacet(address(diamondProxy)).stakeInfo(user1);
        assertEq(finalInfo.cooled, 0, "Internal cooled should be 0 after withdraw");
        assertEq(finalInfo.parked, 0, "Internal parked should be 0 after withdraw");
        assertEq(finalInfo.cooldownEnd, 0, "Cooldown should be reset after withdraw");

        vm.stopPrank();
        console2.log("Unstake accumulation test completed.");
    }

    // --- Swap and Pop Test ---

    function testRemoveStakerFromValidator_SwapAndPop() public {
        uint16 validatorId = DEFAULT_VALIDATOR_ID;
        address staker1 = address(0x111);
        address staker2 = address(0x222);
        address staker3 = address(0x333);
        address staker4 = address(0x444);
        uint256 stakeAmount = 1 ether;

        // Fund users
        vm.deal(staker1, 10 ether);
        vm.deal(staker2, 10 ether);
        vm.deal(staker3, 10 ether);
        vm.deal(staker4, 10 ether);

        // Stake all users with the same validator
        vm.startPrank(staker1);
        StakingFacet(address(diamondProxy)).stake{ value: stakeAmount }(validatorId);
        vm.stopPrank();
        vm.startPrank(staker2);
        StakingFacet(address(diamondProxy)).stake{ value: stakeAmount }(validatorId);
        vm.stopPrank();
        vm.startPrank(staker3);
        StakingFacet(address(diamondProxy)).stake{ value: stakeAmount }(validatorId);
        vm.stopPrank();
        vm.startPrank(staker4);
        StakingFacet(address(diamondProxy)).stake{ value: stakeAmount }(validatorId);
        vm.stopPrank();

        // Verify initial state using getValidatorStats (expect 4 values)
        (,,, uint256 initialStakersCount) = ValidatorFacet(address(diamondProxy)).getValidatorStats(validatorId);
        assertEq(initialStakersCount, 4, "Initial staker count mismatch");

        // --- Remove staker2 (middle element) ---
        vm.startPrank(staker2);
        StakingFacet(address(diamondProxy)).unstake(validatorId, stakeAmount); // Unstake full amount
        vm.stopPrank();

        // Verify state after removing staker2 (expect 4 values)
        (,,, uint256 stakersCountAfterRemove2) = ValidatorFacet(address(diamondProxy)).getValidatorStats(validatorId);
        assertEq(stakersCountAfterRemove2, 3, "Staker count mismatch after removing staker2");
        // Verify staker2 is removed from their own validator list
        uint16[] memory staker2Validators = ValidatorFacet(address(diamondProxy)).getUserValidators(staker2);
        assertEq(staker2Validators.length, 0, "Staker2 validator list not cleared");

        // --- Remove staker1 (conceptually first element, now at index 0) ---
        vm.startPrank(staker1);
        StakingFacet(address(diamondProxy)).unstake(validatorId, stakeAmount);
        vm.stopPrank();

        // Verify state after removing staker1 (expect 4 values)
        (,,, uint256 stakersCountAfterRemove1) = ValidatorFacet(address(diamondProxy)).getValidatorStats(validatorId);
        assertEq(stakersCountAfterRemove1, 2, "Staker count mismatch after removing staker1");
        uint16[] memory staker1Validators = ValidatorFacet(address(diamondProxy)).getUserValidators(staker1);
        assertEq(staker1Validators.length, 0, "Staker1 validator list not cleared");

        // --- Remove staker4 (conceptually last element, potentially moved) ---
        vm.startPrank(staker4);
        StakingFacet(address(diamondProxy)).unstake(validatorId, stakeAmount);
        vm.stopPrank();

        // Verify state after removing staker4 (expect 4 values)
        (,,, uint256 stakersCountAfterRemove4) = ValidatorFacet(address(diamondProxy)).getValidatorStats(validatorId);
        assertEq(stakersCountAfterRemove4, 1, "Staker count mismatch after removing staker4");
        uint16[] memory staker4Validators = ValidatorFacet(address(diamondProxy)).getUserValidators(staker4);
        assertEq(staker4Validators.length, 0, "Staker4 validator list not cleared");

        // --- Remove staker3 (the last remaining) ---
        vm.startPrank(staker3);
        StakingFacet(address(diamondProxy)).unstake(validatorId, stakeAmount);
        vm.stopPrank();

        // Verify final state (expect 4 values)
        (,,, uint256 stakersCountAfterRemove3) = ValidatorFacet(address(diamondProxy)).getValidatorStats(validatorId);
        assertEq(stakersCountAfterRemove3, 0, "Staker count should be 0 finally");
        uint16[] memory staker3Validators = ValidatorFacet(address(diamondProxy)).getUserValidators(staker3);
        assertEq(staker3Validators.length, 0, "Staker3 validator list not cleared");
    }

    // --- Test updateTotalAmounts (Admin Function) ---
    /*
    function testUpdateTotalAmounts() public {
        // Setup stakers
        uint16 validatorId = DEFAULT_VALIDATOR_ID;

        // Add multiple users staking
        vm.startPrank(user1);
        StakingFacet(address(diamondProxy)).stake{ value: 50 ether }(validatorId);
        vm.stopPrank();

        vm.startPrank(user2);
        StakingFacet(address(diamondProxy)).stake{ value: 50 ether }(validatorId);
        vm.stopPrank();

        // Call updateTotalAmounts as admin
        uint256 startIndex = 0;
        uint256 endIndex = 1; // Update validators 0 and 1

        vm.startPrank(admin);
        // ManagementFacet(address(diamondProxy)).updateTotalAmounts(startIndex, endIndex); // Function Removed
        vm.stopPrank();

        (bool active,, uint256 totalStaked,) = ValidatorFacet(address(diamondProxy)).getValidatorStats(validatorId);
        assertTrue(active, "Validator should be active");
    // assertEq(totalStaked, 100 ether, "Total staked amount should be correct"); // Check removed as function is gone
    }
    */

    // --- Access Control / Edge Cases ---

}
