// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script, console2 } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol"; // Include Test for address helpers if needed

// Diamond Proxy & Base
import { PlumeStaking } from "../src/PlumeStaking.sol";
import { ISolidStateDiamond, SolidStateDiamond } from "@solidstate/proxy/diamond/SolidStateDiamond.sol";

// Custom Facets
import { AccessControlFacet } from "../src/facets/AccessControlFacet.sol";
import { ManagementFacet } from "../src/facets/ManagementFacet.sol";
import { RewardsFacet } from "../src/facets/RewardsFacet.sol";
import { StakingFacet } from "../src/facets/StakingFacet.sol";
import { ValidatorFacet } from "../src/facets/ValidatorFacet.sol";

// SolidState Interfaces
import { IERC2535DiamondCutInternal } from "@solidstate/interfaces/IERC2535DiamondCutInternal.sol";

// Plume Roles
import { PlumeRoles } from "../src/lib/PlumeRoles.sol";

// Plume Interface for setup call
import { IAccessControl } from "../src/interfaces/IAccessControl.sol";

contract DeployPlumeStakingDiamond is Script, Test {

    // --- Deployment Configuration ---
    address private constant DEPLOYER_OWNER = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;
    // deployer
    uint256 private constant INITIAL_MIN_STAKE = 1e18;
    uint256 private constant INITIAL_COOLDOWN = 7 days;

    // --- Main Deployment Logic ---
    function run() external {
        // Use DEPLOYER_OWNER for broadcasting
        vm.startBroadcast(DEPLOYER_OWNER);

        console2.log("Deploying Plume Staking Diamond...");

        // 1. Deploy Diamond Proxy (inherits SolidStateDiamond)
        PlumeStaking diamondProxy = new PlumeStaking();
        console2.log("Diamond Proxy deployed at:", address(diamondProxy));
        console2.log("Initial Owner (Deployer):", ISolidStateDiamond(payable(address(diamondProxy))).owner());

        // 2. Initialize Plume-specific settings
        console2.log("Initializing Plume Settings...");
        diamondProxy.initializePlume(DEPLOYER_OWNER, INITIAL_MIN_STAKE, INITIAL_COOLDOWN);
        console2.log("Plume Settings Initialized.");
        console2.log("Final Owner after init:", ISolidStateDiamond(payable(address(diamondProxy))).owner());

        // 3. Deploy Custom Facets ONLY
        console2.log("Deploying Custom Facets...");
        AccessControlFacet accessControlFacet = new AccessControlFacet();
        console2.log("  AccessControlFacet deployed at:", address(accessControlFacet));
        StakingFacet stakingFacet = new StakingFacet();
        console2.log("  StakingFacet deployed at:", address(stakingFacet));
        RewardsFacet rewardsFacet = new RewardsFacet();
        console2.log("  RewardsFacet deployed at:", address(rewardsFacet));
        ValidatorFacet validatorFacet = new ValidatorFacet();
        console2.log("  ValidatorFacet deployed at:", address(validatorFacet));
        ManagementFacet managementFacet = new ManagementFacet();
        console2.log("  ManagementFacet deployed at:", address(managementFacet));

        // 4. Prepare Diamond Cut for Custom Facets
        console2.log("Preparing Diamond Cut for Custom Facets...");
        IERC2535DiamondCutInternal.FacetCut[] memory cut = new IERC2535DiamondCutInternal.FacetCut[](5);

        // --- AccessControl Facet Selectors --- (NEW)
        bytes4[] memory accessControlSigs_Manual = new bytes4[](6);
        accessControlSigs_Manual[0] = bytes4(keccak256(bytes("hasRole(bytes32,address)")));
        accessControlSigs_Manual[1] = bytes4(keccak256(bytes("getRoleAdmin(bytes32)")));
        accessControlSigs_Manual[2] = bytes4(keccak256(bytes("grantRole(bytes32,address)")));
        accessControlSigs_Manual[3] = bytes4(keccak256(bytes("revokeRole(bytes32,address)")));
        accessControlSigs_Manual[4] = bytes4(keccak256(bytes("renounceRole(bytes32,address)")));
        accessControlSigs_Manual[5] = bytes4(keccak256(bytes("setRoleAdmin(bytes32,bytes32)")));
        cut[0] = IERC2535DiamondCutInternal.FacetCut({ // Put AC facet first (index 0)
            target: address(accessControlFacet),
            action: IERC2535DiamondCutInternal.FacetCutAction.ADD,
            selectors: accessControlSigs_Manual
        });

        // Staking Facet Selectors (Shifted index to 1)
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
        cut[1] = IERC2535DiamondCutInternal.FacetCut({
            target: address(stakingFacet),
            action: IERC2535DiamondCutInternal.FacetCutAction.ADD,
            selectors: stakingSigs_Manual
        });

        // Rewards Facet Selectors (Shifted index to 2)
        bytes4[] memory rewardsSigs_Manual = new bytes4[](19);
        rewardsSigs_Manual[0] = bytes4(keccak256(bytes("addRewardToken(address)")));
        rewardsSigs_Manual[1] = bytes4(keccak256(bytes("removeRewardToken(address)")));
        rewardsSigs_Manual[2] = bytes4(keccak256(bytes("setRewardRates(address[],uint256[])")));
        rewardsSigs_Manual[3] = bytes4(keccak256(bytes("setMaxRewardRate(address,uint256)")));
        rewardsSigs_Manual[4] = bytes4(keccak256(bytes("addRewards(address,uint256)")));

        // Handle overloaded claim function
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
        cut[2] = IERC2535DiamondCutInternal.FacetCut({
            target: address(rewardsFacet),
            action: IERC2535DiamondCutInternal.FacetCutAction.ADD,
            selectors: rewardsSigs_Manual
        });

        // Validator Facet Selectors (Shifted index to 3)
        bytes4[] memory validatorSigs_Manual = new bytes4[](10);
        validatorSigs_Manual[0] = bytes4(keccak256(bytes("addValidator(uint16,uint256,address,address,string,string)")));
        validatorSigs_Manual[1] = bytes4(keccak256(bytes("setValidatorCapacity(uint16,uint256)")));
        validatorSigs_Manual[2] = bytes4(keccak256(bytes("updateValidator(uint16,uint8,bytes)")));
        validatorSigs_Manual[3] = bytes4(keccak256(bytes("claimValidatorCommission(uint16,address)")));
        validatorSigs_Manual[4] = bytes4(keccak256(bytes("getValidatorInfo(uint16)")));
        validatorSigs_Manual[5] = bytes4(keccak256(bytes("getValidatorStats(uint16)")));
        validatorSigs_Manual[6] = bytes4(keccak256(bytes("getUserValidators(address)")));
        validatorSigs_Manual[7] = bytes4(keccak256(bytes("getAccruedCommission(uint16,address)")));
        validatorSigs_Manual[8] = bytes4(keccak256(bytes("getActiveValidatorCount()")));
        validatorSigs_Manual[9] = bytes4(keccak256(bytes("getValidatorsList()")));
        cut[3] = IERC2535DiamondCutInternal.FacetCut({
            target: address(validatorFacet),
            action: IERC2535DiamondCutInternal.FacetCutAction.ADD,
            selectors: validatorSigs_Manual
        });

        // Management Facet Selectors (Shifted index to 4)
        bytes4[] memory managementSigs_Manual = new bytes4[](6); // Size back to 6
        managementSigs_Manual[0] = bytes4(keccak256(bytes("setMinStakeAmount(uint256)")));
        managementSigs_Manual[1] = bytes4(keccak256(bytes("setCooldownInterval(uint256)")));
        managementSigs_Manual[2] = bytes4(keccak256(bytes("adminWithdraw(address,uint256,address)")));
        managementSigs_Manual[3] = bytes4(keccak256(bytes("updateTotalAmounts(uint256,uint256)")));
        managementSigs_Manual[4] = bytes4(keccak256(bytes("getMinStakeAmount()")));
        managementSigs_Manual[5] = bytes4(keccak256(bytes("getCooldownInterval()")));
        cut[4] = IERC2535DiamondCutInternal.FacetCut({
            target: address(managementFacet),
            action: IERC2535DiamondCutInternal.FacetCutAction.ADD,
            selectors: managementSigs_Manual
        });

        address payable payableProxy = payable(address(diamondProxy));

        // 5. Execute Diamond Cut
        console2.log("Executing Diamond Cut for Custom Facets...");
        ISolidStateDiamond(payableProxy).diamondCut(cut, address(0), "");
        console2.log("Diamond Cut executed.");

        // --- Grant Initial Roles (POST CUT) ---
        console2.log("Granting initial roles...");
        // Get interface for the AccessControlFacet *through the proxy*
        IAccessControl accessControl = IAccessControl(payableProxy);

        // Grant ADMIN_ROLE to the deployer
        accessControl.grantRole(PlumeRoles.ADMIN_ROLE, DEPLOYER_OWNER);
        console2.log(" - ADMIN_ROLE granted to deployer");

        // Set the ADMIN_ROLE itself as the admin of the ADMIN_ROLE (so admins can manage admins)
        accessControl.setRoleAdmin(PlumeRoles.ADMIN_ROLE, PlumeRoles.ADMIN_ROLE);
        console2.log(" - ADMIN_ROLE set as admin for ADMIN_ROLE");

        // Set ADMIN_ROLE as the admin for UPGRADER_ROLE and VALIDATOR_ROLE
        accessControl.setRoleAdmin(PlumeRoles.UPGRADER_ROLE, PlumeRoles.ADMIN_ROLE);
        console2.log(" - ADMIN_ROLE set as admin for UPGRADER_ROLE");
        accessControl.setRoleAdmin(PlumeRoles.VALIDATOR_ROLE, PlumeRoles.ADMIN_ROLE);
        console2.log(" - ADMIN_ROLE set as admin for VALIDATOR_ROLE");
        // Set ADMIN_ROLE as the admin for REWARD_MANAGER_ROLE
        accessControl.setRoleAdmin(PlumeRoles.REWARD_MANAGER_ROLE, PlumeRoles.ADMIN_ROLE);
        console2.log(" - ADMIN_ROLE set as admin for REWARD_MANAGER_ROLE");

        // Grant UPGRADER_ROLE and VALIDATOR_ROLE to the deployer initially
        accessControl.grantRole(PlumeRoles.UPGRADER_ROLE, DEPLOYER_OWNER);
        console2.log(" - UPGRADER_ROLE granted to deployer");
        accessControl.grantRole(PlumeRoles.VALIDATOR_ROLE, DEPLOYER_OWNER);
        console2.log(" - VALIDATOR_ROLE granted to deployer");
        // Grant REWARD_MANAGER_ROLE to the deployer initially
        accessControl.grantRole(PlumeRoles.REWARD_MANAGER_ROLE, DEPLOYER_OWNER);
        console2.log(" - REWARD_MANAGER_ROLE granted to deployer");

        console2.log("Initial roles granted.");

        // 6. Verify Deployment (Optional but recommended)
        console2.log("Verifying deployment...");

        // Verify Ownership
        address deployer = DEPLOYER_OWNER;
        if (deployer == address(0)) {
            deployer = msg.sender;
        }
        // Use the payable variable for the assertion
        assertEq(ISolidStateDiamond(payableProxy).owner(), deployer);
        console2.log("- Owner verified.");

        // Log deployed addresses
        console2.log("Deployment Complete!");
        console2.log("  Proxy Address:", address(diamondProxy));
        console2.log("  AccessControlFacet:", address(accessControlFacet));
        console2.log("  StakingFacet:", address(stakingFacet));
        console2.log("  RewardsFacet:", address(rewardsFacet));
        console2.log("  ValidatorFacet:", address(validatorFacet));
        console2.log("  ManagementFacet:", address(managementFacet));

        vm.stopBroadcast();
    }

}
