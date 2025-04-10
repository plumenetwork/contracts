// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { Test, console2 } from "forge-std/Test.sol";

// Diamond Proxy & Storage
import { PlumeStaking } from "../src/PlumeStaking.sol";
import { PlumeStakingStorage } from "../src/lib/PlumeStakingStorage.sol";

// Custom Facet Contracts (needed for casting interactions AND struct definitions)
// Import needed for ValidatorListData struct
import { AccessControlFacet } from "../src/facets/AccessControlFacet.sol";

import { ManagementFacet } from "../src/facets/ManagementFacet.sol";
import { RewardsFacet } from "../src/facets/RewardsFacet.sol";
import { StakingFacet } from "../src/facets/StakingFacet.sol";
import { ValidatorFacet } from "../src/facets/ValidatorFacet.sol";
import { IAccessControl } from "../src/interfaces/IAccessControl.sol";

// SolidState Diamond Interface & Cut Interface

import { IERC2535DiamondCutInternal } from "@solidstate/interfaces/IERC2535DiamondCutInternal.sol";
import { ISolidStateDiamond } from "@solidstate/proxy/diamond/ISolidStateDiamond.sol";

// Libs & Errors/Events

import "../src/lib/PlumeErrors.sol";
import "../src/lib/PlumeEvents.sol";
import { PlumeRoles } from "../src/lib/PlumeRoles.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Mocks & Tokens (If used)
// import { MockPUSD } from "../src/mocks/MockPUSD.sol";
// import { Plume } from "../src/Plume.sol";

contract PlumeStakingDiamondTest is Test {

    // --- Declare Events Needed for vm.expectEmit --- Needed because imports aren't resolving correctly
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    // ---

    // Diamond Proxy Address
    PlumeStaking internal diamondProxy;

    // Tokens (Adjust if using mocks or real token contracts)
    IERC20 public plume; // Example: Use IERC20 interface
    IERC20 public pUSD;

    // Addresses
    address public constant ADMIN_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;
    address public constant PLUME_TOKEN = 0x17F085f1437C54498f0085102AB33e7217C067C8; // Example address
    address public constant PUSD_TOKEN = 0x466a756E9A7401B5e2444a3fCB3c2C12FBEa0a54; // Example address
    address public constant PLUME_NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address public user1;
    address public user2;
    address public admin;
    address public validatorAdmin;

    // Constants
    uint256 public constant MIN_STAKE = 1e18;
    uint256 public constant INITIAL_COOLDOWN = 7 days;
    uint256 public constant INITIAL_BALANCE = 1000e18;
    uint256 public constant PUSD_REWARD_RATE = 1e18; // Example rate
    uint256 public constant PLUME_REWARD_RATE = 1_587_301_587; // Example rate
    uint16 public constant DEFAULT_VALIDATOR_ID = 0;
    // uint256 public constant REWARD_PRECISION = 1e18; // Defined in logic lib now

    function setUp() public {
        console2.log("Starting Diamond test setup (Correct Path)");

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        admin = ADMIN_ADDRESS;
        validatorAdmin = makeAddr("validatorAdmin");

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

        // 3. Prepare Diamond Cut
        IERC2535DiamondCutInternal.FacetCut[] memory cut = new IERC2535DiamondCutInternal.FacetCut[](5);

        // AccessControl Facet Selectors (Copied from deployment script)
        bytes4[] memory accessControlSigs_Manual = new bytes4[](7);
        accessControlSigs_Manual[0] = bytes4(keccak256(bytes("initializeAccessControl()")));
        accessControlSigs_Manual[1] = bytes4(keccak256(bytes("hasRole(bytes32,address)")));
        accessControlSigs_Manual[2] = bytes4(keccak256(bytes("getRoleAdmin(bytes32)")));
        accessControlSigs_Manual[3] = bytes4(keccak256(bytes("grantRole(bytes32,address)")));
        accessControlSigs_Manual[4] = bytes4(keccak256(bytes("revokeRole(bytes32,address)")));
        accessControlSigs_Manual[5] = bytes4(keccak256(bytes("renounceRole(bytes32,address)")));
        accessControlSigs_Manual[6] = bytes4(keccak256(bytes("setRoleAdmin(bytes32,bytes32)")));

        // Staking Facet Selectors (Copied from deployment script)
        bytes4[] memory stakingSigs_Manual = new bytes4[](11);
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

        // Rewards Facet Selectors (Copied from deployment script)
        bytes4[] memory rewardsSigs_Manual = new bytes4[](19);
        rewardsSigs_Manual[0] = bytes4(keccak256(bytes("addRewardToken(address)")));
        rewardsSigs_Manual[1] = bytes4(keccak256(bytes("removeRewardToken(address)")));
        rewardsSigs_Manual[2] = bytes4(keccak256(bytes("setRewardRates(address[],uint256[])")));
        rewardsSigs_Manual[3] = bytes4(keccak256(bytes("setMaxRewardRate(address,uint256)")));
        rewardsSigs_Manual[4] = bytes4(keccak256(bytes("addRewards(address,uint256)")));
        rewardsSigs_Manual[5] = bytes4(keccak256(bytes("claim(address)")));
        rewardsSigs_Manual[6] = bytes4(keccak256(bytes("claim(address,uint16)")));
        rewardsSigs_Manual[7] = bytes4(keccak256(bytes("claimAll()")));
        rewardsSigs_Manual[8] = bytes4(keccak256(bytes("restakeRewards(uint16)")));
        rewardsSigs_Manual[9] = bytes4(keccak256(bytes("earned(address,address)")));
        rewardsSigs_Manual[10] = bytes4(keccak256(bytes("getClaimableReward(address,address)")));
        rewardsSigs_Manual[11] = bytes4(keccak256(bytes("getRewardTokens()")));
        rewardsSigs_Manual[12] = bytes4(keccak256(bytes("getMaxRewardRate(address)")));
        rewardsSigs_Manual[13] = bytes4(keccak256(bytes("tokenRewardInfo(address)")));
        rewardsSigs_Manual[14] = bytes4(keccak256(bytes("getRewardRateCheckpointCount(address)")));
        rewardsSigs_Manual[15] = bytes4(keccak256(bytes("getValidatorRewardRateCheckpointCount(uint16,address)")));
        rewardsSigs_Manual[16] = bytes4(keccak256(bytes("getUserLastCheckpointIndex(address,uint16,address)")));
        rewardsSigs_Manual[17] = bytes4(keccak256(bytes("getRewardRateCheckpoint(address,uint256)")));
        rewardsSigs_Manual[18] = bytes4(keccak256(bytes("getValidatorRewardRateCheckpoint(uint16,address,uint256)")));

        // Validator Facet Selectors (Copied + getAccruedCommission + new views)
        bytes4[] memory validatorSigs_Manual = new bytes4[](10); // Increase size to 10
        validatorSigs_Manual[0] = bytes4(keccak256(bytes("addValidator(uint16,uint256,address,address,string,string)")));
        validatorSigs_Manual[1] = bytes4(keccak256(bytes("setValidatorCapacity(uint16,uint256)")));
        validatorSigs_Manual[2] = bytes4(keccak256(bytes("updateValidator(uint16,uint8,bytes)")));
        validatorSigs_Manual[3] = bytes4(keccak256(bytes("claimValidatorCommission(uint16,address)")));
        validatorSigs_Manual[4] = bytes4(keccak256(bytes("getValidatorInfo(uint16)")));
        validatorSigs_Manual[5] = bytes4(keccak256(bytes("getValidatorStats(uint16)")));
        validatorSigs_Manual[6] = bytes4(keccak256(bytes("getUserValidators(address)")));
        validatorSigs_Manual[7] = bytes4(keccak256(bytes("getAccruedCommission(uint16,address)")));
        validatorSigs_Manual[8] = bytes4(keccak256(bytes("getValidatorsList()"))); // Add new selector
        validatorSigs_Manual[9] = bytes4(keccak256(bytes("getActiveValidatorCount()"))); // Add new selector

        // Management Facet Selectors (Copied + new views)
        bytes4[] memory managementSigs_Manual = new bytes4[](6); // Increase size to 6
        managementSigs_Manual[0] = bytes4(keccak256(bytes("setMinStakeAmount(uint256)")));
        managementSigs_Manual[1] = bytes4(keccak256(bytes("setCooldownInterval(uint256)")));
        managementSigs_Manual[2] = bytes4(keccak256(bytes("adminWithdraw(address,uint256,address)")));
        managementSigs_Manual[3] = bytes4(keccak256(bytes("updateTotalAmounts(uint256,uint256)")));
        managementSigs_Manual[4] = bytes4(keccak256(bytes("getMinStakeAmount()"))); // Add new selector
        managementSigs_Manual[5] = bytes4(keccak256(bytes("getCooldownInterval()"))); // Add new selector

        // Use correct struct type and enum path for each cut
        cut[0] = IERC2535DiamondCutInternal.FacetCut({
            target: address(accessControlFacet),
            action: IERC2535DiamondCutInternal.FacetCutAction.ADD,
            selectors: accessControlSigs_Manual
        });
        cut[1] = IERC2535DiamondCutInternal.FacetCut({
            target: address(stakingFacet),
            action: IERC2535DiamondCutInternal.FacetCutAction.ADD,
            selectors: stakingSigs_Manual
        });
        cut[2] = IERC2535DiamondCutInternal.FacetCut({
            target: address(rewardsFacet),
            action: IERC2535DiamondCutInternal.FacetCutAction.ADD,
            selectors: rewardsSigs_Manual
        });
        cut[3] = IERC2535DiamondCutInternal.FacetCut({
            target: address(validatorFacet),
            action: IERC2535DiamondCutInternal.FacetCutAction.ADD,
            selectors: validatorSigs_Manual
        });
        cut[4] = IERC2535DiamondCutInternal.FacetCut({
            target: address(managementFacet),
            action: IERC2535DiamondCutInternal.FacetCutAction.ADD,
            selectors: managementSigs_Manual
        });

        // 4. Execute Diamond Cut
        // Use payable cast
        ISolidStateDiamond(payable(address(diamondProxy))).diamondCut(cut, address(0), "");

        // 5. Initialize Plume Settings (AFTER cut)
        diamondProxy.initializePlume(admin, MIN_STAKE, INITIAL_COOLDOWN);
        // Use payable cast for owner check
        assertEq(ISolidStateDiamond(payable(address(diamondProxy))).owner(), admin, "Owner mismatch after init");

        // 5b. Initialize Access Control (grant DEFAULT_ADMIN_ROLE to admin)
        // Use the AccessControlFacet type cast to the proxy address
        AccessControlFacet(address(diamondProxy)).initializeAccessControl();

        // --- Grant Initial Roles (Mirrors Deployment Script) ---
        IAccessControl accessControl = IAccessControl(address(diamondProxy));
        accessControl.grantRole(PlumeRoles.ADMIN_ROLE, admin);
        accessControl.setRoleAdmin(PlumeRoles.ADMIN_ROLE, PlumeRoles.ADMIN_ROLE);
        accessControl.setRoleAdmin(PlumeRoles.UPGRADER_ROLE, PlumeRoles.ADMIN_ROLE);
        accessControl.setRoleAdmin(PlumeRoles.VALIDATOR_ROLE, PlumeRoles.ADMIN_ROLE);
        accessControl.setRoleAdmin(PlumeRoles.REWARD_MANAGER_ROLE, PlumeRoles.ADMIN_ROLE);
        accessControl.grantRole(PlumeRoles.UPGRADER_ROLE, admin);
        accessControl.grantRole(PlumeRoles.VALIDATOR_ROLE, admin);
        accessControl.grantRole(PlumeRoles.REWARD_MANAGER_ROLE, admin);

        // --- Initial Contract State Setup ---
        // Setup token references (assuming mocks or interfaces)
        plume = IERC20(PLUME_TOKEN);
        pUSD = IERC20(PUSD_TOKEN);

        // Fund accounts
        vm.deal(user1, INITIAL_BALANCE);
        vm.deal(user2, INITIAL_BALANCE);
        vm.deal(admin, INITIAL_BALANCE * 2); // Ensure admin has enough ETH too
        vm.deal(validatorAdmin, INITIAL_BALANCE);
        // Fund the proxy itself only if needed for native token rewards
        vm.deal(address(diamondProxy), INITIAL_BALANCE); // For PLUME_NATIVE rewards

        console2.log("Setting up initial contract state via diamond...");
        // Calls via Facet types cast to proxy address
        RewardsFacet(address(diamondProxy)).addRewardToken(PUSD_TOKEN);
        RewardsFacet(address(diamondProxy)).addRewardToken(PLUME_NATIVE);
        RewardsFacet(address(diamondProxy)).setMaxRewardRate(PUSD_TOKEN, PUSD_REWARD_RATE * 2);
        RewardsFacet(address(diamondProxy)).setMaxRewardRate(PLUME_NATIVE, PLUME_REWARD_RATE * 2);
        address[] memory tokens = new address[](2);
        uint256[] memory rates = new uint256[](2);
        tokens[0] = PUSD_TOKEN;
        rates[0] = PUSD_REWARD_RATE;
        tokens[1] = PLUME_NATIVE;
        rates[1] = PLUME_REWARD_RATE;
        RewardsFacet(address(diamondProxy)).setRewardRates(tokens, rates);

        // Mock PUSD transfer and add rewards
        vm.mockCall(
            PUSD_TOKEN,
            abi.encodeWithSelector(IERC20.transferFrom.selector, admin, address(diamondProxy), INITIAL_BALANCE),
            abi.encode(true)
        );
        RewardsFacet(address(diamondProxy)).addRewards(PUSD_TOKEN, INITIAL_BALANCE);
        // Add native rewards
        RewardsFacet(address(diamondProxy)).addRewards{ value: INITIAL_BALANCE }(PLUME_NATIVE, INITIAL_BALANCE);

        ValidatorFacet(address(diamondProxy)).addValidator(
            DEFAULT_VALIDATOR_ID, 5e16, validatorAdmin, validatorAdmin, "0xval1", "0xacc1"
        );
        ValidatorFacet(address(diamondProxy)).setValidatorCapacity(DEFAULT_VALIDATOR_ID, 1_000_000e18);

        uint16 secondValidatorId = 1;
        ValidatorFacet(address(diamondProxy)).addValidator(secondValidatorId, 10e16, user2, user2, "0xval2", "0xacc2");
        ValidatorFacet(address(diamondProxy)).setValidatorCapacity(secondValidatorId, 1_000_000e18);

        vm.stopPrank();
        console2.log("Diamond test setup complete (with AccessControlFacet)");
    }

    // --- Test Cases ---

    function testInitialState() public {
        // Directly check the initialized flag using the new view function
        // Need to cast diamondProxy to PlumeStaking to call isInitialized
        // Note: Directly accessing storage layout might not work reliably with Diamonds
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

    function testRewardAccrualAndClaim() public {
        uint256 stakeAmount = 100e18;
        vm.startPrank(user1);
        StakingFacet(address(diamondProxy)).stake{ value: stakeAmount }(DEFAULT_VALIDATOR_ID);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);

        // Use RewardsFacet type cast
        uint256 claimable = RewardsFacet(address(diamondProxy)).getClaimableReward(user1, PUSD_TOKEN);
        assertTrue(claimable > 0, "Claimable > 0");
        uint256 expectedRewardApprox = PUSD_REWARD_RATE * 1 days * 95 / 100;
        assertApproxEqRel(claimable, expectedRewardApprox, 1e16);

        vm.startPrank(user1);
        vm.mockCall(PUSD_TOKEN, abi.encodeWithSelector(IERC20.transfer.selector, user1, claimable), abi.encode(true));
        uint256 claimed = RewardsFacet(address(diamondProxy)).claim(PUSD_TOKEN, DEFAULT_VALIDATOR_ID);
        assertEq(claimed, claimable, "Claimed amount mismatch");
        uint256 claimableAfter = RewardsFacet(address(diamondProxy)).getClaimableReward(user1, PUSD_TOKEN);
        assertLt(claimableAfter, 1e12, "Claimable near zero");

        vm.stopPrank();
    }

    // Test based on source code review: claim updates then transfers
    function testClaimValidatorCommission() public {
        uint256 stakeAmount = 100e18;
        uint16 validatorId = DEFAULT_VALIDATOR_ID;
        address token = PUSD_TOKEN;
        address recipient = validatorAdmin; // l2WithdrawAddress for validatorId 0
        address staker = user1;

        vm.startPrank(staker);
        StakingFacet(address(diamondProxy)).stake{ value: stakeAmount }(validatorId);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);

        // --- Claiming Logic & Verification ---
        vm.startPrank(recipient); // Prank as the L2 Admin (who calls claim)

        // Call claim - this performs the update, transfer, and returns the amount
        uint256 claimedAmount = ValidatorFacet(address(diamondProxy)).claimValidatorCommission(validatorId, token);
        assertTrue(claimedAmount > 0, "Claimed commission should be > 0");

        // Verify commission is now zero after the claim
        uint256 commissionAfterClaim = ValidatorFacet(address(diamondProxy)).getAccruedCommission(validatorId, token);
        assertLt(commissionAfterClaim, 1e6, "Commission after claim should be near zero");

        vm.stopPrank();
        // Note: Does not explicitly check transfer/event due to complexity of predicting exact amount.
    }

    function testClaimValidatorCommission_Native() public {
        uint256 stakeAmount = 100e18;
        uint16 validatorId = DEFAULT_VALIDATOR_ID;
        address token = PLUME_NATIVE;
        address recipient = validatorAdmin; // l2WithdrawAddress for validatorId 0
        address staker = user1;

        vm.startPrank(staker);
        StakingFacet(address(diamondProxy)).stake{ value: stakeAmount }(validatorId);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);

        // --- Claiming Logic & Verification ---
        vm.startPrank(recipient); // Prank as the L2 Admin
        uint256 balanceBefore = recipient.balance;

        // Call claim - performs update, transfer, returns amount
        uint256 claimedAmount = ValidatorFacet(address(diamondProxy)).claimValidatorCommission(validatorId, token);
        assertTrue(claimedAmount > 0, "Claimed native commission should be > 0");

        uint256 balanceAfter = recipient.balance;
        assertEq(balanceAfter, balanceBefore + claimedAmount, "Recipient native balance mismatch");

        // Verify commission is now zero
        uint256 commissionAfterClaim = ValidatorFacet(address(diamondProxy)).getAccruedCommission(validatorId, token);
        assertLt(commissionAfterClaim, 1e6, "Native commission after claim should be near zero");

        vm.stopPrank();
    }

    // --- Access Control / Edge Cases ---

    function testClaimValidatorCommission_ZeroAmount() public {
        uint16 validatorId = DEFAULT_VALIDATOR_ID;
        address token = PUSD_TOKEN;
        address recipient = validatorAdmin;

        // No staking, no time warp -> commission should be 0
        vm.startPrank(recipient);

        // Claim should return 0 and not revert
        uint256 claimedCommission = ValidatorFacet(address(diamondProxy)).claimValidatorCommission(validatorId, token);
        assertEq(claimedCommission, 0, "Claimed amount should be zero when none accrued");

        vm.stopPrank();
    }

    // function testClaimValidatorCommission_Inactive() public {
    //     uint16 validatorId = DEFAULT_VALIDATOR_ID;
    //     address token = PUSD_TOKEN;

    //     // Deactivate validator first - needs to be done by L2 Admin
    //     // NOTE: updateValidator currently does NOT support changing active status.
    //     // This test needs to be revisited if/when deactivation functionality is added.
    //     vm.startPrank(validatorAdmin);
    //     // ValidatorFacet(address(diamondProxy)).updateValidator(validatorId, ??, abi.encode(false));
    //     vm.stopPrank();

    //     // Try claiming - should revert due to inactive status
    //     vm.startPrank(validatorAdmin);
    //     vm.expectRevert(abi.encodeWithSelector(ValidatorInactive.selector, validatorId));
    //     ValidatorFacet(address(diamondProxy)).claimValidatorCommission(validatorId, token);
    //     vm.stopPrank();
    // }

    function testClaimValidatorCommission_NonExistent() public {
        uint16 nonExistentId = 999;
        address token = PUSD_TOKEN;

        vm.startPrank(validatorAdmin); // Prank as a valid admin for *some* validator (e.g., ID 0)
        // Expect revert from onlyValidatorAdmin(nonExistentId) as validator 999 data doesn't exist to check admin
        vm.expectRevert(bytes("Not validator admin"));
        ValidatorFacet(address(diamondProxy)).claimValidatorCommission(nonExistentId, token);
        vm.stopPrank();
    }

    function testClaimValidatorCommission_NotAdmin() public {
        uint16 validatorId = DEFAULT_VALIDATOR_ID;
        address token = PUSD_TOKEN;

        vm.startPrank(user1); // user1 is not the admin for validator 0
        vm.expectRevert(bytes("Not validator admin"));
        ValidatorFacet(address(diamondProxy)).claimValidatorCommission(validatorId, token);
        vm.stopPrank();
    }

    function testUpdateValidator_Commission() public {
        uint16 validatorId = DEFAULT_VALIDATOR_ID;
        uint256 newCommission = 20e16; // 20%
        bytes memory data = abi.encode(newCommission);
        uint8 fieldCode = 0; // Correct field code for Commission is 0

        // Get current state BEFORE update to build expected event
        (PlumeStakingStorage.ValidatorInfo memory infoBefore,,) =
            ValidatorFacet(address(diamondProxy)).getValidatorInfo(validatorId);

        // Correct event check (only topic1 is indexed)
        vm.expectEmit(true, false, false, true, address(diamondProxy));
        // Use correct values based on state *after* update
        emit ValidatorUpdated(
            validatorId,
            newCommission, // The new value
            infoBefore.l2AdminAddress, // Existing value
            infoBefore.l2WithdrawAddress, // Existing value
            infoBefore.l1ValidatorAddress, // Existing value
            infoBefore.l1AccountAddress // Existing value
        );

        // Call as the VALIDATOR ADMIN (l2AdminAddress)
        vm.startPrank(validatorAdmin);
        ValidatorFacet(address(diamondProxy)).updateValidator(validatorId, fieldCode, data);
        vm.stopPrank();

        // Verify
        (PlumeStakingStorage.ValidatorInfo memory infoAfter,,) =
            ValidatorFacet(address(diamondProxy)).getValidatorInfo(validatorId);
        assertEq(infoAfter.commission, newCommission, "Commission not updated");
    }

    function testUpdateValidator_Commission_NotOwner() public {
        uint16 validatorId = DEFAULT_VALIDATOR_ID;
        uint256 newCommission = 20e16;
        bytes memory data = abi.encode(newCommission);
        uint8 fieldCode = 0;

        // Expect revert from the validator admin check
        vm.expectRevert(bytes("Not validator admin"));
        vm.startPrank(user1); // user1 is not the validator admin for validator 0
        ValidatorFacet(address(diamondProxy)).updateValidator(validatorId, fieldCode, data);
        vm.stopPrank();
    }

    function testUpdateValidator_L2Admin() public {
        uint16 validatorId = DEFAULT_VALIDATOR_ID;
        address newAdmin = makeAddr("newAdminForVal0");
        bytes memory data = abi.encode(newAdmin);
        uint8 fieldCode = 1; // Correct field code for L2 Admin is 1

        // Get current state BEFORE update
        (PlumeStakingStorage.ValidatorInfo memory infoBefore,,) =
            ValidatorFacet(address(diamondProxy)).getValidatorInfo(validatorId);

        // Correct event check
        vm.expectEmit(true, false, false, true, address(diamondProxy));
        // Use correct values based on state *after* update
        emit ValidatorUpdated(
            validatorId,
            infoBefore.commission, // Existing value
            newAdmin, // The new value
            infoBefore.l2WithdrawAddress, // Existing value
            infoBefore.l1ValidatorAddress, // Existing value
            infoBefore.l1AccountAddress // Existing value
        );

        // Call as the CURRENT VALIDATOR ADMIN
        vm.startPrank(validatorAdmin);
        // Use correct field code for L2 Admin
        ValidatorFacet(address(diamondProxy)).updateValidator(validatorId, fieldCode, data);
        vm.stopPrank();

        (PlumeStakingStorage.ValidatorInfo memory infoAfter,,) =
            ValidatorFacet(address(diamondProxy)).getValidatorInfo(validatorId);
        assertEq(infoAfter.l2AdminAddress, newAdmin, "L2 Admin not updated");
    }

    function testUpdateValidator_L2Admin_NotOwner() public {
        uint16 validatorId = DEFAULT_VALIDATOR_ID;
        address newAdmin = makeAddr("newAdminForVal0");
        bytes memory data = abi.encode(newAdmin);
        uint8 fieldCode = 1;

        // Expect revert from the validator admin check
        // vm.expectEmit(...) removed as call should revert before emitting
        vm.expectRevert(bytes("Not validator admin"));
        vm.startPrank(user1); // user1 is not the validator admin for validator 0
        ValidatorFacet(address(diamondProxy)).updateValidator(validatorId, fieldCode, data);
        vm.stopPrank();
    }

    function testUpdateValidator_NonExistent() public {
        uint16 nonExistentId = 999;
        uint256 newCommission = 20e16;
        bytes memory data = abi.encode(newCommission);
        uint8 fieldCode = 0;

        vm.startPrank(validatorAdmin); // Call as an admin of *some* validator
        // Expect revert from onlyValidatorAdmin(nonExistentId)
        vm.expectRevert(bytes("Not validator admin"));
        ValidatorFacet(address(diamondProxy)).updateValidator(nonExistentId, fieldCode, data);
        vm.stopPrank();
    }

    function testSetMinStakeAmount() public {
        uint256 newMinStake = 2 ether;
        uint256 oldMinStake = ManagementFacet(address(diamondProxy)).getMinStakeAmount();

        // Check event emission - Use the correct event name 'MinStakeAmountSet'
        // Note: MinStakeAmountSet only emits the new amount, not old and new.
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

    function testSetMinStakeAmount_NotOwner() public {
        uint256 newMinStake = 2 ether;

        // Expect revert when called by non-owner - Use the actual revert string
        vm.expectRevert(bytes("Must be owner"));

        // Call as user1
        vm.startPrank(user1);
        ManagementFacet(address(diamondProxy)).setMinStakeAmount(newMinStake);
        vm.stopPrank();
    }

    function testSetCooldownInterval() public {
        uint256 newCooldown = 14 days;
        uint256 oldCooldown = ManagementFacet(address(diamondProxy)).getCooldownInterval(); // Not needed for event, but
            // good practice

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

    function testSetCooldownInterval_NotOwner() public {
        uint256 newCooldown = 14 days;

        // Expect revert when called by non-owner - Use the actual revert string
        vm.expectRevert(bytes("Must be owner"));

        // Call as user1
        vm.startPrank(user1);
        ManagementFacet(address(diamondProxy)).setCooldownInterval(newCooldown);
        vm.stopPrank();
    }

    // --- ValidatorFacet Tests ---

    function testAddValidator() public {
        uint16 newValidatorId = 2;
        uint256 commission = 15e16; // 15%
        address l2Admin = makeAddr("newValAdmin");
        address l2Withdraw = makeAddr("newValWithdraw");
        string memory l1ValAddr = "0xval3";
        string memory l1AccAddr = "0xacc3";

        // Check event emission
        vm.expectEmit(true, true, true, true, address(diamondProxy));
        emit ValidatorAdded(newValidatorId, commission, l2Admin, l2Withdraw, l1ValAddr, l1AccAddr);

        // Call as admin
        vm.startPrank(admin);
        ValidatorFacet(address(diamondProxy)).addValidator(
            newValidatorId, commission, l2Admin, l2Withdraw, l1ValAddr, l1AccAddr
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
        assertTrue(storedInfo.active, "Newly added validator should be active");
    }

    function testAddValidator_NotOwner() public {
        uint16 newValidatorId = 3;
        vm.expectRevert(bytes("Must be owner"));

        vm.startPrank(user1);
        ValidatorFacet(address(diamondProxy)).addValidator(newValidatorId, 5e16, user1, user1, "0xval4", "0xacc4");
        vm.stopPrank();
    }

    function testGetValidatorInfo_Existing() public {
        // Use validator added in setUp
        (PlumeStakingStorage.ValidatorInfo memory info,,) =
            ValidatorFacet(address(diamondProxy)).getValidatorInfo(DEFAULT_VALIDATOR_ID);

        assertEq(info.validatorId, DEFAULT_VALIDATOR_ID, "ID mismatch");
        assertTrue(info.active, "Should be active");
        assertEq(info.commission, 5e16, "Commission mismatch"); // Value from setUp
        assertEq(info.l2AdminAddress, validatorAdmin, "L2 Admin mismatch"); // Value from setUp
        assertEq(info.l2WithdrawAddress, validatorAdmin, "L2 Withdraw mismatch"); // Value from setUp
        assertEq(info.maxCapacity, 1_000_000e18, "Capacity mismatch"); // Value from setUp
        // Check L1 addresses added in setUp
        assertEq(info.l1ValidatorAddress, "0xval1", "L1 validator address mismatch");
        assertEq(info.l1AccountAddress, "0xacc1", "L1 account address mismatch");
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

    function testSetValidatorCapacity_NotOwner() public {
        uint16 validatorId = DEFAULT_VALIDATOR_ID;
        uint256 newCapacity = 2_000_000 ether;

        vm.expectRevert(bytes("Must be owner"));

        vm.startPrank(user1);
        ValidatorFacet(address(diamondProxy)).setValidatorCapacity(validatorId, newCapacity);
        vm.stopPrank();
    }

    function testSetValidatorCapacity_NonExistent() public {
        uint16 nonExistentId = 999;
        uint256 newCapacity = 2_000_000 ether;

        vm.expectRevert(abi.encodeWithSelector(ValidatorDoesNotExist.selector, nonExistentId));

        vm.startPrank(admin);
        ValidatorFacet(address(diamondProxy)).setValidatorCapacity(nonExistentId, newCapacity);
        vm.stopPrank();
    }

    function testGetValidatorStats_Existing() public {
        uint16 validatorId = DEFAULT_VALIDATOR_ID;
        // Stake to ensure staker count and total staked are non-zero if needed
        vm.startPrank(user1);
        StakingFacet(address(diamondProxy)).stake{ value: 100 ether }(validatorId);
        vm.stopPrank();

        (bool active, uint256 commission, uint256 totalStaked, uint256 stakersCount) =
            ValidatorFacet(address(diamondProxy)).getValidatorStats(validatorId);

        assertTrue(active, "Stats: Should be active");
        assertEq(commission, 5e16, "Stats: Commission mismatch"); // Value from setUp
        assertEq(totalStaked, 100 ether, "Stats: Total staked mismatch");
        assertEq(stakersCount, 1, "Stats: Stakers count mismatch");
    }

    function testGetValidatorStats_NonExistent() public {
        uint16 nonExistentId = 999;
        vm.expectRevert(abi.encodeWithSelector(ValidatorDoesNotExist.selector, nonExistentId));
        ValidatorFacet(address(diamondProxy)).getValidatorStats(nonExistentId);
    }

    function testGetUserValidators() public {
        uint16 validatorId0 = DEFAULT_VALIDATOR_ID; // 0
        uint16 validatorId1 = 1;

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
        address user3 = makeAddr("user3");
        uint16[] memory user3Validators = ValidatorFacet(address(diamondProxy)).getUserValidators(user3);
        assertEq(user3Validators.length, 0, "User3 validator count mismatch");
    }

    function testGetAccruedCommission_Direct() public {
        uint16 validatorId = DEFAULT_VALIDATOR_ID;
        address token = PUSD_TOKEN;

        // Check initial commission is 0
        uint256 commissionBefore = ValidatorFacet(address(diamondProxy)).getAccruedCommission(validatorId, token);
        assertEq(commissionBefore, 0, "Initial commission should be 0");

        // Stake and warp time
        vm.startPrank(user1);
        StakingFacet(address(diamondProxy)).stake{ value: 100 ether }(validatorId);
        vm.stopPrank();
        vm.warp(block.timestamp + 1 days);

        // Trigger reward update (e.g., by user claiming, could also call claimCommission)
        vm.startPrank(user1);
        uint256 claimable = RewardsFacet(address(diamondProxy)).getClaimableReward(user1, token);
        vm.mockCall(token, abi.encodeWithSelector(IERC20.transfer.selector, user1, claimable), abi.encode(true));
        RewardsFacet(address(diamondProxy)).claim(token, validatorId);
        vm.stopPrank();

        // Check commission after update
        uint256 commissionAfter = ValidatorFacet(address(diamondProxy)).getAccruedCommission(validatorId, token);
        assertTrue(commissionAfter > 0, "Commission should be > 0 after user claim");
    }

    // --- StakingFacet / RewardsFacet Interaction Bug Test ---

    function testRewardsAfterUnstake() public {
        uint256 stakeAmount = 100 ether;
        uint16 validatorId = DEFAULT_VALIDATOR_ID;
        address token = PUSD_TOKEN; // Use a token with a known reward rate
        address staker = user1;

        // 1. Stake
        vm.startPrank(staker);
        StakingFacet(address(diamondProxy)).stake{ value: stakeAmount }(validatorId);
        vm.stopPrank();

        // 2. Warp time
        uint256 warpDuration = 1 days;
        vm.warp(block.timestamp + warpDuration);

        // 3. Check rewards accrued BEFORE unstake
        // Calling earned should trigger updateRewardsForValidator
        uint256 earnedBefore = RewardsFacet(address(diamondProxy)).earned(staker, token);
        assertTrue(earnedBefore > 0, "Rewards should have accrued before unstake");
        console2.log("Earned Before Unstake:", earnedBefore);

        // 4. Unstake
        vm.startPrank(staker);
        StakingFacet(address(diamondProxy)).unstake(validatorId, stakeAmount); // Unstake full amount
        vm.stopPrank();

        // 5. Check rewards accrued AFTER unstake
        // Calling earned again should read the stored rewards, potentially updating slightly if time passed
        uint256 earnedAfter = RewardsFacet(address(diamondProxy)).earned(staker, token);
        console2.log("Earned After Unstake:", earnedAfter);

        // Assertion: Earned amount after unstake should be >= earned amount just before unstake.
        // It should NOT reset to zero.
        assertGe(earnedAfter, earnedBefore, "Rewards disappeared after unstake");

        // Optional: Check claimable amount as well
        uint256 claimableAfter = RewardsFacet(address(diamondProxy)).getClaimableReward(staker, token);
        console2.log("Claimable After Unstake:", claimableAfter);
        assertGe(claimableAfter, earnedBefore, "Claimable rewards disappeared after unstake"); // Should also be >=
            // earnedBefore
    }

    // ... testGetValidatorsList (can keep or remove, this is more thorough) ...

    function testGetValidatorsList_Data() public {
        uint16 validatorId0 = DEFAULT_VALIDATOR_ID; // 0
        uint16 validatorId1 = 1;
        uint256 stake0 = 50 ether;
        uint256 stake1_user1 = 75 ether;
        uint256 stake1_user2 = 100 ether;
        uint256 totalStake1 = stake1_user1 + stake1_user2;

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
        assertEq(listData[0].totalStaked, stake0, "Validator 0 total staked mismatch");
        assertEq(listData[0].commission, 5e16, "Validator 0 commission mismatch"); // From setUp

        // Verify data for validator 1
        assertEq(listData[1].id, validatorId1, "Validator 1 ID mismatch");
        assertEq(listData[1].totalStaked, totalStake1, "Validator 1 total staked mismatch");
        assertEq(listData[1].commission, 10e16, "Validator 1 commission mismatch"); // From setUp
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
        // Expect revert from AccessControlInternal check based on getRoleAdmin(VALIDATOR_ROLE) which is ADMIN_ROLE
        vm.expectRevert(
            bytes(
                "AccessControl: account 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 is missing role 0xdf8b4c520ffe197c5343c6f5aec59570151ef9a492f2c624fd45ddde6135ec42"
            )
        );
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
        vm.expectRevert(
            bytes(
                "AccessControl: account 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC is missing role 0xdf8b4c520ffe197c5343c6f5aec59570151ef9a492f2c624fd45ddde6135ec42"
            )
        );
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
        vm.expectRevert(
            bytes(
                "AccessControl: account 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 is missing role 0xdf8b4c520ffe197c5343c6f5aec59570151ef9a492f2c624fd45ddde6135ec42"
            )
        );
        ac.setRoleAdmin(roleToManage, newAdminRole);
        vm.stopPrank();
    }

    // --- Test Protected Functions ---

    function testProtected_AddValidator_Success() public {
        // Admin (who has VALIDATOR_ROLE) calls addValidator
        vm.startPrank(admin);
        ValidatorFacet(address(diamondProxy)).addValidator(10, 5e16, user1, user1, "v10", "a10");
        vm.stopPrank();
        // Check validator exists (implicitly checks success)
        (,, uint256 stakerCount) = ValidatorFacet(address(diamondProxy)).getValidatorInfo(10);
        assertEq(stakerCount, 0);
    }

    function testProtected_AddValidator_Fail() public {
        // User1 (no VALIDATOR_ROLE) calls addValidator
        vm.startPrank(user1);
        vm.expectRevert(bytes("Caller does not have the required role"));
        ValidatorFacet(address(diamondProxy)).addValidator(11, 5e16, user2, user2, "v11", "a11");
        vm.stopPrank();
    }

    // Add similar tests for other protected functions (setValidatorCapacity, setMinStakeAmount, addRewardToken etc.)

}
