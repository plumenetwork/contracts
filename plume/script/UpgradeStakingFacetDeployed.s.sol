// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script, console2 } from "forge-std/Script.sol";
// import { stdJson } from "forge-std/StdJson.sol"; // Not needed if not reading .env for proxy address

// Diamond Proxy & Storage
import { PlumeStaking } from "../src/PlumeStaking.sol";

// Facets
// Only StakingFacet is needed for this specific upgrade script
import { StakingFacet } from "../src/facets/StakingFacet.sol";

// Interfaces
import { IERC2535DiamondCutInternal } from "@solidstate/interfaces/IERC2535DiamondCutInternal.sol";
import { ISolidStateDiamond } from "@solidstate/proxy/diamond/ISolidStateDiamond.sol";

// Libs & Others
// import { PlumeRoles } from "../src/lib/PlumeRoles.sol"; // Not directly used in this script

contract UpgradeStakingFacetDeployed is Script {

    // using stdJson for string; // Not needed

    address internal constant DIAMOND_PROXY_ADDRESS = 0xCF8B97260F77c11d58542644c5fD1D5F93FdA57d;
    address internal constant STAKING_ADDRESS = 0x956C9CF41F2965a590213DAeB829CDC97F06894E;

    function setUp() public {
        if (DIAMOND_PROXY_ADDRESS == address(0)) {
            console2.log("Error: DIAMOND_PROXY_ADDRESS is address(0). Please set it correctly in the script.");
            revert("DIAMOND_PROXY_ADDRESS not set");
        }
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console2.log("--- Starting Upgrade Script for StakingFacet ---");
        console2.log("Using Diamond Proxy Address:", DIAMOND_PROXY_ADDRESS);
        console2.log("Upgrader Address (from PRIVATE_KEY):", deployerAddress);

        console2.log("Deploying new StakingFacet implementation...");
        //StakingFacet newStakingFacet = new StakingFacet();
        //console2.log("New StakingFacet Deployed:", address(newStakingFacet));

        console2.log("Preparing diamond cut for StakingFacet...");
        IERC2535DiamondCutInternal.FacetCut[] memory cut = new IERC2535DiamondCutInternal.FacetCut[](1);

        // Staking Facet Selectors - Use REPLACE
        bytes4[] memory stakingSigs = new bytes4[](17);
        stakingSigs[0] = StakingFacet.stake.selector;
        stakingSigs[1] = StakingFacet.restake.selector;
        stakingSigs[2] = bytes4(keccak256(bytes("unstake(uint16)")));
        stakingSigs[3] = bytes4(keccak256(bytes("unstake(uint16,uint256)")));
        stakingSigs[4] = StakingFacet.withdraw.selector;
        stakingSigs[5] = StakingFacet.stakeOnBehalf.selector;
        stakingSigs[6] = StakingFacet.stakeInfo.selector;
        stakingSigs[7] = StakingFacet.amountStaked.selector;
        stakingSigs[8] = StakingFacet.amountCooling.selector;
        stakingSigs[9] = StakingFacet.amountWithdrawable.selector;
        stakingSigs[10] = StakingFacet.getUserCooldowns.selector;
        stakingSigs[11] = StakingFacet.getUserValidatorStake.selector;
        stakingSigs[12] = StakingFacet.restakeRewards.selector;
        stakingSigs[13] = StakingFacet.totalAmountStaked.selector;
        stakingSigs[14] = StakingFacet.totalAmountCooling.selector;
        stakingSigs[15] = StakingFacet.totalAmountWithdrawable.selector;
        stakingSigs[16] = StakingFacet.totalAmountClaimable.selector;

        cut[0] = IERC2535DiamondCutInternal.FacetCut({
            target: STAKING_ADDRESS,
            action: IERC2535DiamondCutInternal.FacetCutAction.REPLACE,
            selectors: stakingSigs
        });

        console2.log("Diamond cut prepared for StakingFacet REPLACE action.");

        // --- 3. Execute Diamond Cut ---
        console2.log("Executing diamond cut on proxy:", DIAMOND_PROXY_ADDRESS);
        ISolidStateDiamond(payable(DIAMOND_PROXY_ADDRESS)).diamondCut(cut, address(0), "");
        console2.log("Diamond cut executed successfully. StakingFacet should be upgraded.");

        console2.log("--- StakingFacet Upgrade Script Complete ---");
        vm.stopBroadcast();
    }

}
