// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title BVPlumeDistributor
 * @author Alp Guneysel
 * @notice Distributor contract for integration with BoringVaults on Plume
 */
contract BVPlumeDistributor is AccessControlUpgradeable, ReentrancyGuardUpgradeable {

    using SafeERC20 for IERC20;

    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    event TokensDistributed(IERC20 indexed token, address indexed user, uint256 amount);

    error Unauthorized(address sender);
    error InsufficientBalance(uint256 available, uint256 required);

    constructor(address admin, address distributor) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(DISTRIBUTOR_ROLE, distributor);
    }

    /// @notice Distributes tokens to users after they bridge from Ethereum
    /// @dev Only callable by accounts with DISTRIBUTOR_ROLE (off-chain service)
    /// @param token The token to distribute
    /// @param users Array of user addresses to receive tokens
    /// @param amounts Array of token amounts to distribute
    function distributeTokens(
        IERC20 token,
        address[] calldata users,
        uint256[] calldata amounts
    ) external nonReentrant onlyRole(DISTRIBUTOR_ROLE) {
        require(users.length == amounts.length, "Length mismatch");

        uint256 totalAmount;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }

        if (token.balanceOf(address(this)) < totalAmount) {
            revert InsufficientBalance(token.balanceOf(address(this)), totalAmount);
        }

        for (uint256 i = 0; i < users.length; i++) {
            token.safeTransfer(users[i], amounts[i]);
            emit TokensDistributed(token, users[i], amounts[i]);
        }
    }

    /// @notice Allows admin to recover any tokens sent to this contract
    /// @param token Token to recover
    /// @param amount Amount to recover
    function recoverTokens(IERC20 token, uint256 amount) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        token.safeTransfer(msg.sender, amount);
    }

}
