// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script, console2 } from "forge-std/Script.sol";

// Diamond Proxy & Storage
import { PlumeStaking } from "../src/PlumeStaking.sol";
import { PlumeStakingStorage } from "../src/lib/PlumeStakingStorage.sol";

// Facets
import { AccessControlFacet } from "../src/facets/AccessControlFacet.sol";
import { ManagementFacet } from "../src/facets/ManagementFacet.sol";
import { RewardsFacet } from "../src/facets/RewardsFacet.sol";
import { StakingFacet } from "../src/facets/StakingFacet.sol";
import { ValidatorFacet } from "../src/facets/ValidatorFacet.sol";

// Interfaces

import { IPlumeStakingRewardTreasury } from "../src/interfaces/IPlumeStakingRewardTreasury.sol";
import { IERC2535DiamondCutInternal } from "@solidstate/interfaces/IERC2535DiamondCutInternal.sol";
import { ISolidStateDiamond } from "@solidstate/proxy/diamond/ISolidStateDiamond.sol";

// Libs & Others
import { PlumeRoles } from "../src/lib/PlumeRoles.sol";

contract DeployPlumeStaking is Script {

    // --- Configuration Constants ---
    // Replace with your generated addresses after running GenerateValidatorAdmins.s.sol
    address[] internal validatorAdminAddresses = [
        0x5E696f3E4bb7910a030d985b08D458DAa548587D,
        0xF0189c1698734c74521Ca010b83a82daB69051b5,
        0x592FCaeAbD04942E25190cA5318909f0715daaB4,
        0xe520f20C551017aB80980179E4B8725646625124,
        0x8043387d0EE7Fee12D251caB821eaad648A61570,
        0x56FE509FA512c37A932c64a49898e5E3baecE404,
        0x37dd08E36b8Fe2675CE1d15FD5D711256E5faD8c,
        0xb4Cc54b72E8D60E865a9743C4D88A090ec7A9e5B,
        0x7Bf729aF5e8b46899fBC31C15Ca9b295904dc9Dd,
        0x7F52402B5b188638dD0e264EA78b3f3FC00FdE82,
        0xB6d23d7e78d8912304152028875290e2F6E960D0,
        0xC18c6479c9ef80432A4e3E91512b68ce584B044b,
        0x9271D8c839d3F347b7215B5495783138E48F9FB2,
        0xb2D92c04A2487389f984cD9B271EB498B6D4eab6,
        0x2875A33D4Ae4304F6ea451Ca04A3304B7CA4c495
    ];

    address internal constant EXISTING_TREASURY_ADDRESS = 0x14789D64465f0F5521593e58cB120724bDf7d2cF;
    uint256 internal constant INITIAL_MIN_STAKE_AMOUNT = 0.1 ether; // 0.1 PLUME
    uint256 internal constant INITIAL_COOLDOWN_INTERVAL = 30 seconds;
    uint256 internal constant INITIAL_MAX_SLASH_VOTE_DURATION = 10 seconds;
    uint256 internal constant INITIAL_MAX_ALLOWED_VALIDATOR_COMMISSION = 25 * 10 ** 16; // 25%
    uint256 internal constant VALIDATOR_COMMISSION = 0.5 * 10 ** 16; // 0.5% 
    uint256 internal constant VALIDATOR_MAX_CAPACITY = 0 ether;

    // PLUME (Native) reward rate: 5.5% yearly approx 1744038559107051 per second per 1e18 staked
    uint256 internal constant PLUME_REWARD_RATE_PER_SECOND = 1_584_404_391;
    uint256 internal constant PLUME_MAX_REWARD_RATE = 4e15; // Slightly higher than actual rate

    function run() external {
        vm.startBroadcast();

        console2.log("Deploying Plume Staking Diamond...");

        // --- 0. Initial Checks ---
        if (validatorAdminAddresses.length != 15) {
            console2.log("Error: Please update validatorAdminAddresses in the script with 15 addresses.");
            revert("Invalid number of validator admin addresses defined.");
        }

        // --- 1. Deploy Diamond Proxy ---
        PlumeStaking diamondProxy = new PlumeStaking();
        console2.log("PlumeStaking Diamond Proxy deployed at:", address(diamondProxy));

        // --- 2. Deploy Facets ---
        AccessControlFacet accessControlFacet = new AccessControlFacet();
        ManagementFacet managementFacet = new ManagementFacet();
        RewardsFacet rewardsFacet = new RewardsFacet();
        StakingFacet stakingFacet = new StakingFacet();
        ValidatorFacet validatorFacet = new ValidatorFacet();

        console2.log("Facets deployed:");
        console2.log("- AccessControlFacet:", address(accessControlFacet));
        console2.log("- ManagementFacet:", address(managementFacet));
        console2.log("- RewardsFacet:", address(rewardsFacet));
        console2.log("- StakingFacet:", address(stakingFacet));
        console2.log("- ValidatorFacet:", address(validatorFacet));

        // --- 3. Prepare Diamond Cut ---
        IERC2535DiamondCutInternal.FacetCut[] memory cut = new IERC2535DiamondCutInternal.FacetCut[](5);

        // AccessControl Facet Selectors
        bytes4[] memory accessControlSigs = new bytes4[](13);
        accessControlSigs[0] = bytes4(keccak256(bytes("initializeAccessControl()")));
        accessControlSigs[1] = AccessControlFacet.hasRole.selector;
        accessControlSigs[2] = AccessControlFacet.getRoleAdmin.selector;
        accessControlSigs[3] = AccessControlFacet.grantRole.selector;
        accessControlSigs[4] = AccessControlFacet.revokeRole.selector;
        accessControlSigs[5] = AccessControlFacet.renounceRole.selector;
        accessControlSigs[6] = AccessControlFacet.setRoleAdmin.selector;
        accessControlSigs[7] = bytes4(keccak256(bytes("DEFAULT_ADMIN_ROLE()")));
        accessControlSigs[8] = bytes4(keccak256(bytes("ADMIN_ROLE()")));
        accessControlSigs[9] = bytes4(keccak256(bytes("UPGRADER_ROLE()")));
        accessControlSigs[10] = bytes4(keccak256(bytes("VALIDATOR_ROLE()")));
        accessControlSigs[11] = bytes4(keccak256(bytes("REWARD_MANAGER_ROLE()")));
        accessControlSigs[12] = bytes4(keccak256(bytes("TIMELOCK_ROLE()")));
        cut[0] = IERC2535DiamondCutInternal.FacetCut(
            address(accessControlFacet), IERC2535DiamondCutInternal.FacetCutAction.ADD, accessControlSigs
        );

        // Management Facet Selectors
        bytes4[] memory managementSigs = new bytes4[](9);
        managementSigs[0] = ManagementFacet.setMinStakeAmount.selector;
        managementSigs[1] = ManagementFacet.setCooldownInterval.selector;
        managementSigs[2] = ManagementFacet.adminWithdraw.selector;
        managementSigs[3] = ManagementFacet.getMinStakeAmount.selector;
        managementSigs[4] = ManagementFacet.getCooldownInterval.selector;
        managementSigs[5] = ManagementFacet.setMaxSlashVoteDuration.selector;
        managementSigs[6] = ManagementFacet.setMaxAllowedValidatorCommission.selector;
        managementSigs[7] = ManagementFacet.adminClearValidatorRecord.selector;
        managementSigs[8] = ManagementFacet.adminBatchClearValidatorRecords.selector;
        cut[1] = IERC2535DiamondCutInternal.FacetCut(
            address(managementFacet), IERC2535DiamondCutInternal.FacetCutAction.ADD, managementSigs
        );

        // Staking Facet Selectors
        bytes4[] memory stakingSigs = new bytes4[](17);
        stakingSigs[0] = StakingFacet.stake.selector;
        stakingSigs[1] = StakingFacet.restake.selector;
        stakingSigs[2] = bytes4(keccak256(bytes("unstake(uint16)")));
        stakingSigs[3] = bytes4(keccak256(bytes("unstake(uint16,uint256)")));
        stakingSigs[4] = StakingFacet.withdraw.selector;
        stakingSigs[5] = StakingFacet.stakeOnBehalf.selector;
        stakingSigs[6] = StakingFacet.restakeRewards.selector;
        stakingSigs[7] = StakingFacet.stakeInfo.selector;
        stakingSigs[8] = StakingFacet.amountStaked.selector;
        stakingSigs[9] = StakingFacet.amountCooling.selector;
        stakingSigs[10] = StakingFacet.amountWithdrawable.selector;
        stakingSigs[11] = StakingFacet.getUserCooldowns.selector;
        stakingSigs[12] = StakingFacet.getUserValidatorStake.selector;
        stakingSigs[13] = StakingFacet.totalAmountStaked.selector;
        stakingSigs[14] = StakingFacet.totalAmountCooling.selector;
        stakingSigs[15] = StakingFacet.totalAmountWithdrawable.selector;
        stakingSigs[16] = StakingFacet.totalAmountClaimable.selector;
        cut[2] = IERC2535DiamondCutInternal.FacetCut(
            address(stakingFacet), IERC2535DiamondCutInternal.FacetCutAction.ADD, stakingSigs
        );

        // Validator Facet Selectors
        bytes4[] memory validatorSigs = new bytes4[](18);
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
        validatorSigs[11] = ValidatorFacet.requestCommissionClaim.selector;
        validatorSigs[12] = ValidatorFacet.finalizeCommissionClaim.selector;
        validatorSigs[13] = ValidatorFacet.voteToSlashValidator.selector;
        validatorSigs[14] = ValidatorFacet.slashValidator.selector;
        validatorSigs[15] = ValidatorFacet.forceSettleValidatorCommission.selector;
        validatorSigs[16] = ValidatorFacet.getSlashVoteCount.selector;
        validatorSigs[17] = ValidatorFacet.cleanupExpiredVotes.selector;
        cut[3] = IERC2535DiamondCutInternal.FacetCut(
            address(validatorFacet), IERC2535DiamondCutInternal.FacetCutAction.ADD, validatorSigs
        );

        // Rewards Facet Selectors
        bytes4[] memory rewardsSigs = new bytes4[](21);
        rewardsSigs[0] = RewardsFacet.addRewardToken.selector;
        rewardsSigs[1] = RewardsFacet.removeRewardToken.selector;
        rewardsSigs[2] = RewardsFacet.setRewardRates.selector;
        rewardsSigs[3] = RewardsFacet.setMaxRewardRate.selector;
        rewardsSigs[4] = bytes4(keccak256(bytes("claim(address)")));
        rewardsSigs[5] = bytes4(keccak256(bytes("claim(address,uint16)")));
        rewardsSigs[6] = RewardsFacet.claimAll.selector;
        rewardsSigs[7] = RewardsFacet.earned.selector;
        rewardsSigs[8] = RewardsFacet.getClaimableReward.selector;
        rewardsSigs[9] = RewardsFacet.getRewardTokens.selector;
        rewardsSigs[10] = RewardsFacet.getMaxRewardRate.selector;
        rewardsSigs[11] = RewardsFacet.getRewardRate.selector;
        rewardsSigs[12] = RewardsFacet.tokenRewardInfo.selector;
        rewardsSigs[13] = RewardsFacet.getRewardRateCheckpointCount.selector;
        rewardsSigs[14] = RewardsFacet.getValidatorRewardRateCheckpointCount.selector;
        rewardsSigs[15] = RewardsFacet.getUserLastCheckpointIndex.selector;
        rewardsSigs[16] = RewardsFacet.getRewardRateCheckpoint.selector;
        rewardsSigs[17] = RewardsFacet.getValidatorRewardRateCheckpoint.selector;
        rewardsSigs[18] = RewardsFacet.setTreasury.selector;
        rewardsSigs[19] = RewardsFacet.getTreasury.selector;
        rewardsSigs[20] = RewardsFacet.getPendingRewardForValidator.selector;
        cut[4] = IERC2535DiamondCutInternal.FacetCut(
            address(rewardsFacet), IERC2535DiamondCutInternal.FacetCutAction.ADD, rewardsSigs
        );

        console2.log("Diamond cut prepared.");

        // --- 4. Execute Diamond Cut ---
        ISolidStateDiamond(payable(address(diamondProxy))).diamondCut(cut, address(0), "");
        console2.log("Diamond cut executed.");

        // --- 5. Initialize Diamond and Facets ---
        address deployer = msg.sender;
        diamondProxy.initializePlume(
            deployer,
            INITIAL_MIN_STAKE_AMOUNT,
            INITIAL_COOLDOWN_INTERVAL,
            INITIAL_MAX_SLASH_VOTE_DURATION,
            INITIAL_MAX_ALLOWED_VALIDATOR_COMMISSION
        );
        console2.log("PlumeStaking initialized.");

        AccessControlFacet(address(diamondProxy)).initializeAccessControl();
        console2.log("AccessControlFacet initialized.");

        // --- 6. Grant Roles to Deployer ---
        AccessControlFacet(address(diamondProxy)).grantRole(PlumeRoles.ADMIN_ROLE, deployer);
        AccessControlFacet(address(diamondProxy)).grantRole(PlumeRoles.UPGRADER_ROLE, deployer);
        AccessControlFacet(address(diamondProxy)).grantRole(PlumeRoles.VALIDATOR_ROLE, deployer);
        AccessControlFacet(address(diamondProxy)).grantRole(PlumeRoles.REWARD_MANAGER_ROLE, deployer);
        AccessControlFacet(address(diamondProxy)).grantRole(PlumeRoles.TIMELOCK_ROLE, deployer);
        console2.log("Deployer granted all standard roles.");

        // --- 7. Configure Treasury ---
        RewardsFacet(address(diamondProxy)).setTreasury(EXISTING_TREASURY_ADDRESS);
        console2.log("Treasury address set to:", EXISTING_TREASURY_ADDRESS);

        // --- 9. Configure PLUME_NATIVE Rewards ---
        address plumeNativeToken = PlumeStakingStorage.PLUME_NATIVE;
        RewardsFacet(address(diamondProxy)).addRewardToken(plumeNativeToken);
        console2.log("PLUME_NATIVE added as reward token.");

        RewardsFacet(address(diamondProxy)).setMaxRewardRate(plumeNativeToken, PLUME_MAX_REWARD_RATE);
        console2.log("Max reward rate for PLUME_NATIVE set to: %s", PLUME_MAX_REWARD_RATE);

        address[] memory plumeTokens = new address[](1);
        plumeTokens[0] = plumeNativeToken;
        uint256[] memory plumeRates = new uint256[](1);
        plumeRates[0] = PLUME_REWARD_RATE_PER_SECOND;
        RewardsFacet(address(diamondProxy)).setRewardRates(plumeTokens, plumeRates);
        console2.log("Reward rate for PLUME_NATIVE set to: %s per second", PLUME_REWARD_RATE_PER_SECOND);

        // Note: Funding the treasury with PLUME_NATIVE (ETH) needs to be done via a separate transaction sending ETH to
        // the treasury address.
        // This script cannot directly fund an existing contract with ETH from deployer's balance unless Treasury has a
        // payable deposit function.

        // --- 10. Add 15 Validators ---
        console2.log("Adding 10 validators...");
        for (uint16 i = 0; i < 10; i++) {
            uint16 validatorId = i + 1; // IDs 1 to 15
            address valAdmin = validatorAdminAddresses[i];
            string memory l1ValAddr = string(abi.encodePacked("l1val_", vm.toString(validatorId), "_placeholder"));
            string memory l1AccAddr = string(abi.encodePacked("l1acc_", vm.toString(validatorId), "_placeholder"));
            address l1AccEvmAddr = address(uint160(uint160(address(this)) + validatorId)); // semi-random

            ValidatorFacet(address(diamondProxy)).addValidator(
                validatorId,
                VALIDATOR_COMMISSION,
                valAdmin,
                valAdmin, // l2WithdrawAddress is same as l2AdminAddress
                l1ValAddr,
                l1AccAddr,
                l1AccEvmAddr,
                VALIDATOR_MAX_CAPACITY
            );
            console2.log("- Added Validator ID: %s, Admin: %s", validatorId, valAdmin);
        }
        console2.log("10 validators added.");

        console2.log("--- Plume Staking Diamond Deployment and Initial Setup Complete ---");
        console2.log("Diamond Proxy Address:", address(diamondProxy));
        console2.log(
            "Remember to fund the Treasury (%s) with PLUME (native ETH) for rewards.", EXISTING_TREASURY_ADDRESS
        );

        vm.stopBroadcast();
    }

}
