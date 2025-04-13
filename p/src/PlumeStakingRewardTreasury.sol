// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IPlumeStakingRewardTreasury } from "./interfaces/IPlumeStakingRewardTreasury.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title PlumeStakingRewardTreasury
 * @notice Contract responsible for holding and distributing reward tokens for the PlumeStaking system
 * @dev This contract is used by the RewardsFacet to distribute rewards to validators and delegators
 */
contract PlumeStakingRewardTreasury is IPlumeStakingRewardTreasury, AccessControl, ReentrancyGuard {

    using SafeERC20 for IERC20;

    // Events
    event RewardTokenAdded(address indexed token);
    event RewardDistributed(address indexed token, uint256 amount, address indexed recipient);
    event ETHReceived(address indexed sender, uint256 amount);

    // Role constants
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // State variables
    address[] private _rewardTokens;
    mapping(address => bool) private _isRewardToken;

    /**
     * @dev Constructor that sets up roles
     * @param admin The address that will have the admin role
     * @param distributor The address that will have the distributor role (usually the diamond proxy)
     */
    constructor(address admin, address distributor) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(DISTRIBUTOR_ROLE, distributor);

        // Set ADMIN_ROLE as the admin for DISTRIBUTOR_ROLE
        _setRoleAdmin(DISTRIBUTOR_ROLE, ADMIN_ROLE);
    }

    /**
     * @notice Add a token to the list of reward tokens
     * @dev Only callable by ADMIN_ROLE
     * @param token The token address to add
     */
    function addRewardToken(
        address token
    ) external onlyRole(ADMIN_ROLE) {
        require(token != address(0), "Cannot add zero address as token");
        require(!_isRewardToken[token], "Token already added");

        _rewardTokens.push(token);
        _isRewardToken[token] = true;

        emit RewardTokenAdded(token);
    }

    /**
     * @notice Check if the treasury has enough balance of a token
     * @param token The token address (use address(0) or 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE for native ETH)
     * @param amount The amount to check
     * @return Whether the treasury has enough balance
     */
    function hasEnoughBalance(address token, uint256 amount) external view override returns (bool) {
        // Check both address(0) and the canonical ETH placeholder address
        if (token == address(0) || token == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            return address(this).balance >= amount;
        } else {
            return IERC20(token).balanceOf(address(this)) >= amount;
        }
    }

    /**
     * @notice Distribute reward to a recipient
     * @dev Can only be called by an address with DISTRIBUTOR_ROLE
     * @param token The token address (use address(0) or 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE for native ETH)
     * @param amount The amount to distribute
     * @param recipient The recipient address
     */
    function distributeReward(
        address token,
        uint256 amount,
        address recipient
    ) external override nonReentrant onlyRole(DISTRIBUTOR_ROLE) {
        require(recipient != address(0), "Cannot distribute to zero address");
        require(amount > 0, "Amount must be greater than 0");

        // Check both address(0) and the canonical ETH placeholder address
        if (token == address(0) || token == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            // ETH distribution
            require(address(this).balance >= amount, "Insufficient ETH balance");
            (bool success,) = recipient.call{ value: amount }("");
            require(success, "ETH transfer failed");
        } else {
            // ERC20 token distribution
            require(_isRewardToken[token], "Token not registered");
            uint256 balance = IERC20(token).balanceOf(address(this));
            require(balance >= amount, "Insufficient token balance");
            IERC20(token).safeTransfer(recipient, amount);
        }

        emit RewardDistributed(token, amount, recipient);
    }

    /**
     * @notice Get all reward tokens managed by the treasury
     * @return An array of token addresses
     */
    function getRewardTokens() external view override returns (address[] memory) {
        return _rewardTokens;
    }

    /**
     * @notice Get the balance of a token in the treasury
     * @param token The token address (use address(0) or 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE for native ETH)
     * @return The balance
     */
    function getBalance(
        address token
    ) external view override returns (uint256) {
        if (token == address(0) || token == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            return address(this).balance;
        } else {
            return IERC20(token).balanceOf(address(this));
        }
    }

    /**
     * @notice Check if a token is registered as a reward token
     * @param token The token address
     * @return Whether the token is registered
     */
    function isRewardToken(
        address token
    ) external view returns (bool) {
        return _isRewardToken[token];
    }

    /**
     * @notice Allows the treasury to receive ETH
     */
    receive() external payable {
        emit ETHReceived(msg.sender, msg.value);
    }

}
