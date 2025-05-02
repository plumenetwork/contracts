// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title IPlumeStakingRewardTreasury
 * @notice Interface for the PlumeStakingRewardTreasury contract
 * @dev Used by the RewardsFacet to interact with the treasury
 */
interface IPlumeStakingRewardTreasury {

    /**
     * @notice Distribute reward to a recipient
     * @dev Can only be called by an address with DISTRIBUTOR_ROLE
     * @param token The token address (use address(0) for native ETH)
     * @param amount The amount to distribute
     * @param recipient The recipient address
     */
    function distributeReward(address token, uint256 amount, address recipient) external;

    /**
     * @notice Get all reward tokens managed by the treasury
     * @return An array of token addresses
     */
    function getRewardTokens() external view returns (address[] memory);

    /**
     * @notice Get the balance of a token in the treasury
     * @param token The token address (use address(0) for native ETH)
     * @return The balance
     */
    function getBalance(
        address token
    ) external view returns (uint256);

}
