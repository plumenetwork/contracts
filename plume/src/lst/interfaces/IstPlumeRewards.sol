// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

/// @title IstPlumeRewards - Interface for the stPlumeRewards contract
/// @notice Interface for reward management functionality in the stPlumeMinter system
interface IstPlumeRewards {
    
    // ========== EVENTS ==========
    
    event RewardClaimed(address indexed user, address indexed token, uint256 amount);
    event AllRewardsClaimed(address indexed user, uint256[] totalAmount);
    event ValidatorRewardClaimed(address indexed user, address indexed token, uint16 indexed validatorId, uint256 amount);
    event NewRewardsCycle(uint32 indexed cycleEnd, uint256 rewardAmount);
    
    // ========== VIEW FUNCTIONS ==========
    
    /// @notice Get the last time rewards are applicable
    /// @return timestamp The last applicable reward timestamp
    function lastTimeRewardApplicable() external view returns (uint256);
    
    /// @notice Get the current reward per token
    /// @return rewardPerToken The current reward per token value
    function rewardPerToken() external view returns (uint256);
    
    /// @notice Get current rewards for a user
    /// @param user The user address
    /// @return yield The amount of rewards the user has earned
    function getUserRewards(address user) external view returns (uint256 yield);
    
    /// @notice Get the total reward for the full duration
    /// @return reward The total reward amount for the duration
    function getRewardForDuration() external view returns (uint256);
    
    /// @notice Get current total yield (legacy compatibility)
    /// @return yield The current yield rate
    function getYield() external view returns (uint256);

    function rewardPerTokenStored() external view returns (uint256);

    function YIELD_FEE() external view returns (uint256);

    function RATIO_PRECISION() external view returns (uint256);
    
    
    // ========== MUTATIVE FUNCTIONS ==========
    
    /// @notice Load rewards from external sources
    /// @return amount The amount of rewards loaded
    function loadRewards() external payable returns (uint256 amount);
    
    /// @notice Handle token transfer to track user rewards
    /// @param user The user whose tokens are being transferred
    function handleTokenTransfer(address user) external;
    
    /// @notice Reset user rewards after claim
    /// @param user The user whose rewards are being reset
    function resetUserRewardsAfterClaim(address user) external;
    
    /// @notice Sync rewards manually
    function syncRewards() external;

    function syncUser(address user) external;
    
    // ========== ADMIN FUNCTIONS ==========
    
    /// @notice Set yield fee percentage
    /// @param newYieldFee The new yield fee percentage
    function setYieldFee(uint256 newYieldFee) external;
    
    /// @notice Set rewards cycle length
    /// @param newLength The new cycle length in seconds
    function setRewardsCycleLength(uint256 newLength) external;
}