// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IPlumeStakingRewardTreasury } from "./interfaces/IPlumeStakingRewardTreasury.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// Import Plume errors and events
import {
    InsufficientBalance,
    InsufficientPlumeBalance,
    InsufficientTokenBalance,
    InvalidToken,
    PlumeTransferFailed,
    TokenAlreadyAdded,
    TokenNotRegistered,
    TokenTransferFailed,
    ZeroAddressToken,
    ZeroAmount,
    ZeroRecipientAddress
} from "./lib/PlumeErrors.sol";
import { PlumeReceived, RewardDistributed, RewardTokenAdded, TokenReceived } from "./lib/PlumeEvents.sol";

/**
 * @title PlumeStakingRewardTreasury
 * @notice Contract responsible for holding and distributing reward tokens for the PlumeStaking system
 * @dev This contract is used by the RewardsFacet to distribute rewards to validators and delegators
 */
contract PlumeStakingRewardTreasury is IPlumeStakingRewardTreasury, AccessControl, ReentrancyGuard {

    using SafeERC20 for IERC20;

    // Constants
    address public constant PLUME_NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

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
        if (admin == address(0)) {
            revert ZeroAddressToken();
        }
        if (distributor == address(0)) {
            revert ZeroAddressToken();
        }

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
        if (token == address(0)) {
            revert ZeroAddressToken();
        }
        if (_isRewardToken[token]) {
            revert TokenAlreadyAdded(token);
        }

        _rewardTokens.push(token);
        _isRewardToken[token] = true;

        emit RewardTokenAdded(token);
    }

    /**
     * @notice Check if the treasury has enough balance of a token
     * @param token The token address (use PLUME_NATIVE for native PLUME)
     * @param amount The amount to check
     * @return Whether the treasury has enough balance
     */
    function hasEnoughBalance(address token, uint256 amount) external view override returns (bool) {
        if (amount == 0) {
            return true;
        }

        if (token == PLUME_NATIVE) {
            return address(this).balance >= amount;
        } else {
            if (!_isRewardToken[token]) {
                revert TokenNotRegistered(token);
            }
            return IERC20(token).balanceOf(address(this)) >= amount;
        }
    }

    /**
     * @notice Distribute reward to a recipient
     * @dev Can only be called by an address with DISTRIBUTOR_ROLE
     * @param token The token address (use PLUME_NATIVE for native PLUME)
     * @param amount The amount to distribute
     * @param recipient The recipient address
     */
    function distributeReward(
        address token,
        uint256 amount,
        address recipient
    ) external override nonReentrant onlyRole(DISTRIBUTOR_ROLE) {
        if (recipient == address(0)) {
            revert ZeroRecipientAddress();
        }
        if (amount == 0) {
            revert ZeroAmount();
        }

        if (token == PLUME_NATIVE) {
            // PLUME distribution
            uint256 balance = address(this).balance;
            if (balance < amount) {
                revert InsufficientPlumeBalance(amount, balance);
            }

            (bool success,) = recipient.call{ value: amount }("");
            if (!success) {
                revert PlumeTransferFailed(recipient, amount);
            }
        } else {
            // ERC20 token distribution
            if (!_isRewardToken[token]) {
                revert TokenNotRegistered(token);
            }

            uint256 balance = IERC20(token).balanceOf(address(this));
            if (balance < amount) {
                revert InsufficientTokenBalance(token, amount, balance);
            }

            // Use SafeERC20 to safely transfer tokens
            SafeERC20.safeTransfer(IERC20(token), recipient, amount);
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
     * @param token The token address (use PLUME_NATIVE for native PLUME)
     * @return The balance
     */
    function getBalance(
        address token
    ) external view override returns (uint256) {
        if (token == PLUME_NATIVE) {
            return address(this).balance;
        } else {
            if (!_isRewardToken[token]) {
                revert TokenNotRegistered(token);
            }
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
     * @notice Allows the treasury to receive PLUME
     */
    receive() external payable {
        emit PlumeReceived(msg.sender, msg.value);
    }

}
