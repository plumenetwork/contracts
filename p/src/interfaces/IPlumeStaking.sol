// File: contracts/IPlumeStaking.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { PlumeStakingStorage } from "../lib/PlumeStakingStorage.sol";

/**
 * @title IPlumeStaking
 * @author Based on work by Eugene Y. Q. Shen, Alp Guneysel
 * @notice Interface for the PlumeStaking system
 */
interface IPlumeStaking {

    // Constants that will be shared across all implementations
    /// @notice Role for administrators of PlumeStaking
    function ADMIN_ROLE() external pure returns (bytes32);

    /// @notice Role for upgraders of PlumeStaking
    function UPGRADER_ROLE() external pure returns (bytes32);

    /// @notice Maximum reward rate: ~100% APY (3171 nanotoken per second per token)
    function MAX_REWARD_RATE() external pure returns (uint256);

    /// @notice Scaling factor for reward calculations
    function REWARD_PRECISION() external pure returns (uint256);

    /// @notice Base unit for calculations (equivalent to REWARD_PRECISION)
    function BASE() external pure returns (uint256);

    /// @notice Address constant used to represent the native PLUME token
    function PLUME() external pure returns (address);

    // Core functions all implementations must support
    function initialize(address owner, address pUSD_) external;

    // Staking functions
    function stake() external payable returns (uint256);
    function unstake() external returns (uint256 amount);
    function withdraw() external returns (uint256 amount);

    // Reward functions
    function claim(
        address token
    ) external returns (uint256 amount);
    function claimAll() external returns (uint256[] memory amounts);

    // View functions
    function stakingInfo()
        external
        view
        returns (
            uint256 totalStaked,
            uint256 totalCooling,
            uint256 totalWithdrawable,
            uint256 minStakeAmount,
            address[] memory rewardTokens
        );

    function stakeInfo(
        address user
    ) external view returns (PlumeStakingStorage.StakeInfo memory);
    function amountStaked() external view returns (uint256 amount);
    function amountCooling() external view returns (uint256 amount);
    function amountWithdrawable() external view returns (uint256 amount);

}
