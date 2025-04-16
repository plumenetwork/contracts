// File: contracts/IPlumeStaking.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { PlumeStakingStorage } from "../lib/PlumeStakingStorage.sol";

/**
 * @title IPlumeStaking
 * @author Eugene Y. Q. Shen, Alp Guneysel
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
    function initialize(
        address owner
    ) external;

    // Staking functions
    /**
     * @notice Stake PLUME to a specific validator using only wallet funds
     * @param validatorId ID of the validator to stake to
     */
    function stake(
        uint16 validatorId
    ) external payable returns (uint256);

    /**
     * @notice Restake PLUME to a specific validator, using funds only from cooling and parked balances
     * @param validatorId ID of the validator to stake to
     * @param amount Amount of tokens to restake (can be 0 to use all available cooling/parked funds)
     */
    function restake(uint16 validatorId, uint256 amount) external returns (uint256);
    function stakeOnBehalf(uint16 validatorId, address staker) external payable returns (uint256);
    function unstake(
        uint16 validatorId
    ) external returns (uint256 amount);
    function unstake(uint16 validatorId, uint256 amount) external returns (uint256 amountUnstaked);
    function withdraw() external returns (uint256 amount);

    // Reward functions
    function claim(
        address token
    ) external returns (uint256 amount);
    function claim(address token, uint16 validatorId) external returns (uint256 amount);
    function claimAll() external returns (uint256 totalAmount);

    /**
     * @notice Update validator settings
     * @param validatorId ID of the validator
     * @param updateType Type of update (0=commission, 1=admin address, 2=withdraw address)
     * @param data Encoded update data (uint256 for commission, address for admin/withdraw)
     */
    function updateValidator(uint16 validatorId, uint8 updateType, bytes calldata data) external;

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

    /**
     * @notice Get the total amount of PLUME staked in the contract
     * @return amount Total amount of PLUME staked
     */
    function totalAmountStaked() external view returns (uint256 amount);

    /**
     * @notice Get the total amount of PLUME cooling in the contract
     * @return amount Total amount of PLUME cooling
     */
    function totalAmountCooling() external view returns (uint256 amount);

    /**
     * @notice Get the total amount of PLUME withdrawable in the contract
     * @return amount Total amount of PLUME withdrawable
     */
    function totalAmountWithdrawable() external view returns (uint256 amount);

    /**
     * @notice Get the total amount of token claimable across all users
     * @param token Address of the token to check
     * @return amount Total amount of token claimable
     */
    function totalAmountClaimable(
        address token
    ) external view returns (uint256 amount);

    /**
     * @notice Get the cooldown end date for the caller
     * @return timestamp Time when the cooldown period ends
     */
    function cooldownEndDate() external view returns (uint256 timestamp);

    /**
     * @notice Get the reward rate for a specific token
     * @param token Address of the token to check
     * @return rate Current reward rate for the token
     */
    function getRewardRate(
        address token
    ) external view returns (uint256 rate);

    /**
     * @notice Get the claimable reward amount for a user and token
     * @param user Address of the user to check
     * @param token Address of the reward token
     * @return amount Amount of reward token claimable
     */
    function getClaimableReward(address user, address token) external view returns (uint256 amount);

    /**
     * @notice Get the list of validators a user has staked with
     * @param user Address of the user to check
     * @return validatorIds Array of validator IDs the user has staked with
     */
    function getUserValidators(
        address user
    ) external view returns (uint16[] memory validatorIds);

    /**
     * @notice Get information about a validator including total staked amount
     * @param validatorId ID of the validator to check
     * @return info Validator information
     * @return totalStaked Total PLUME staked to this validator
     * @return stakersCount Number of stakers delegating to this validator
     */
    function getValidatorInfo(
        uint16 validatorId
    )
        external
        view
        returns (PlumeStakingStorage.ValidatorInfo memory info, uint256 totalStaked, uint256 stakersCount);

    /**
     * @notice Get essential statistics about a validator
     * @param validatorId ID of the validator to check
     * @return active Whether the validator is active
     * @return commission Validator's commission rate
     * @return totalStaked Total PLUME staked to this validator
     * @return stakersCount Number of stakers delegating to this validator
     */
    function getValidatorStats(
        uint16 validatorId
    ) external view returns (bool active, uint256 commission, uint256 totalStaked, uint256 stakersCount);

}
