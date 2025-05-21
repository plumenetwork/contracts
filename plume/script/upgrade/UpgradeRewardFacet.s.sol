// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script, console2 } from "forge-std/Script.sol";

// Diamond Proxy & Storage
import { PlumeStaking } from "../../src/PlumeStaking.sol"; // Only for ISolidStateDiamond interface
import { PlumeStakingStorage } from "../../src/lib/PlumeStakingStorage.sol";

// Facets to be upgraded
import { RewardsFacet } from "../../src/facets/RewardsFacet.sol";
import { StakingFacet } from "../../src/facets/StakingFacet.sol";

// Interfaces
import { IERC2535DiamondCutInternal } from "@solidstate/interfaces/IERC2535DiamondCutInternal.sol";
import { ISolidStateDiamond } from "@solidstate/proxy/diamond/ISolidStateDiamond.sol";

// Libs & Others
import { PlumeRoles } from "../../src/lib/PlumeRoles.sol";

contract UpgradeRewardsAndStakingFacets is Script {

    // !!! IMPORTANT: Replace with your deployed PlumeStaking diamond proxy address !!!
    address internal constant DIAMOND_PROXY_ADDRESS = 0xCF8B97260F77c11d58542644c5fD1D5F93FdA57d; // REPLACE THIS

    function run() external {
        if (DIAMOND_PROXY_ADDRESS == address(0)) {
            console2.log("Error: DIAMOND_PROXY_ADDRESS is not set in the script.");
            revert("DIAMOND_PROXY_ADDRESS not set.");
        }

        vm.startBroadcast();

        console2.log("Upgrading RewardsFacet for Diamond at:", DIAMOND_PROXY_ADDRESS);

        // --- 1. Deploy New Facet Implementations ---
        RewardsFacet newRewardsFacet = new RewardsFacet();

        console2.log("New Facet Implementations Deployed:");
        console2.log("- New RewardsFacet:", address(newRewardsFacet));

        // --- 2. Prepare Diamond Cut for REPLACE ---
        IERC2535DiamondCutInternal.FacetCut[] memory cut = new IERC2535DiamondCutInternal.FacetCut[](1);

        // Rewards Facet Selectors (assuming no changes from initial deployment script - uses 21 selectors)
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
        rewardsSigs[11] = RewardsFacet.tokenRewardInfo.selector;
        rewardsSigs[12] = RewardsFacet.getRewardRateCheckpointCount.selector;
        rewardsSigs[13] = RewardsFacet.getValidatorRewardRateCheckpointCount.selector;
        rewardsSigs[14] = RewardsFacet.getUserLastCheckpointIndex.selector;
        rewardsSigs[15] = RewardsFacet.getRewardRateCheckpoint.selector;
        rewardsSigs[16] = RewardsFacet.getValidatorRewardRateCheckpoint.selector;
        rewardsSigs[17] = RewardsFacet.setTreasury.selector;
        rewardsSigs[18] = RewardsFacet.getTreasury.selector;
        rewardsSigs[19] = RewardsFacet.getPendingRewardForValidator.selector;
        rewardsSigs[20] = RewardsFacet.getRewardRate.selector;
        cut[0] = IERC2535DiamondCutInternal.FacetCut({
            target: address(newRewardsFacet),
            action: IERC2535DiamondCutInternal.FacetCutAction.REPLACE,
            selectors: rewardsSigs
        });
        console2.log("RewardsFacet cut prepared for REPLACE with new implementation:", address(newRewardsFacet));

        // --- 3. Execute Diamond Cut ---
        console2.log("Executing diamondCut to REPLACE StakingFacet and RewardsFacet...");
        ISolidStateDiamond(payable(DIAMOND_PROXY_ADDRESS)).diamondCut(cut, address(0), "");
        console2.log("Diamond cut executed. Facets should be upgraded.");

        vm.stopBroadcast();
    }

}
