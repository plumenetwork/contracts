// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

/// @title IstPlumeRewards - Interface for stPlumeRewards contract
/// @notice Interface for the reward management of frxETH token holders
interface IstPlumeRewardsLegacy {
    // Structs
    struct CycleRewards {
        uint256 rewards;
        uint256 totalSupply;
        uint32 cycleEnd;
    }

    struct UserRewards {
        uint256 rewardInCycle;
        uint256 rewardsBefore;
        uint256 rewardsAccrued;
        uint256 lastCycleClaimed;
    }
    
    // View functions
    function YIELD_FEE() external view returns (uint256);
    function yieldEth() external view returns (uint256);
    function rewardsEth() external view returns (uint256);
    function rewardsCycleLength() external view returns (uint32);
    function lastSync() external view returns (uint32);
    function rewardsCycleEnd() external view returns (uint32);
    function lastRewardAmount() external view returns (uint256);
    function cycleRewards(uint256 index) external view returns (uint256 rewards, uint256 totalSupply, uint32 cycleEnd);
    function userRewards(address user) external view returns (uint256 rewardInCycle, uint256 rewardsBefore, uint256 rewardsAccrued, uint256 lastCycleClaimed);
    // function getClaimableReward() external view returns (uint256 amount);
    function getUserRewards(address user) external view returns (uint256 yield);
    function getYield() external view returns (uint256);
    
    // Mutative functions
    function loadRewards() external payable returns (uint256);
    // function claim(uint16 validatorId) external returns (uint256 amount);
    // function claimAll() external returns (uint256[] memory amounts);
    function handleTokenTransfer(address user) external;
    function resetUserRewardsAfterClaim(address user) external;
    function syncRewards() external;
    
    // Admin functions
    function setYieldFee(uint256 newYieldFee) external;
    function setRewardsCycleLength(uint32 newLength) external;
}
