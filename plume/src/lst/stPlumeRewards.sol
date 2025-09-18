// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

// ====================================================================
// |                      Plume stPlumeRewards                        |
// ====================================================================
// Reward management for stPlumeMinter - Based on Synthetix StakingRewards

import { IPlumeStaking } from "./interfaces/IPlumeStaking.sol";
import { IstPlumeRewards } from "./interfaces/IstPlumeRewards.sol";
import { IstPlumeMinter } from "./interfaces/IstPlumeMinter.sol";
import { frxETH } from "./frxETH.sol";
import { AccessControlUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "solmate/utils/SafeCastLib.sol";

/// @title stPlumeRewards - Reward system for the stPlumeMinter contract
/// @notice Handles all reward-related functionality for frxETH token holders using Synthetix rewards logic
contract stPlumeRewards is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, IstPlumeRewards {
    // Role definitions
    bytes32 public constant CLAIMER_ROLE = keccak256("CLAIMER_ROLE");
    bytes32 public constant HANDLER_ROLE = keccak256("HANDLER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    
    // Fees
    uint256 public YIELD_FEE; // 10%
    uint256 public constant RATIO_PRECISION = 1e6;
    
    // Synthetix StakingRewards state variables (adapted)
    uint256 public rewardsCycleEnd = 0; // periodFinish equivalent
    uint256 public rewardRate = 0;
    uint256 public rewardsCycleLength = 7 days; // rewardsDuration equivalent
    uint256 public lastSync; // lastUpdateTime equivalent
    uint256 public rewardPerTokenStored;
    uint256[50] private __gap;
    
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public userRewards; // rewards mapping
        
    // Contract references
    frxETH public frxETHToken;
    address public stPlumeMinter;
    
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _frxETHToken,
        address _stPlumeMinter,
        address _admin
    ) public initializer{
        __ReentrancyGuard_init();
        frxETHToken = frxETH(_frxETHToken);
        stPlumeMinter = _stPlumeMinter;
        
        rewardsCycleLength = 7 days;
        YIELD_FEE = 100000;
        
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(MINTER_ROLE, _admin);
        _setupRole(MINTER_ROLE, _stPlumeMinter);
        _setupRole(HANDLER_ROLE, _frxETHToken);
    }
    
    modifier onlyMinter() {
        require(hasRole(MINTER_ROLE, msg.sender), "Caller is not a minter");
        _;
    }
    
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastSync = lastTimeRewardApplicable();
        if (account != address(0)) {
            userRewards[account] = getUserRewards(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }
    
    // ========== VIEWS (Synthetix Logic) ==========
    
    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < rewardsCycleEnd ? block.timestamp : rewardsCycleEnd;
    }
    
    function rewardPerToken() public view returns (uint256) {
        uint256 totalSupply = frxETHToken.totalSupply();
        if (totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored + (
            ((lastTimeRewardApplicable() - lastSync) * rewardRate * 1e18) / totalSupply
        );
    }
    
    /// @notice Get current rewards for a user (Synthetix earned() logic)
    function getUserRewards(address user) public view returns (uint256 yield) {
        uint256 balance = frxETHToken.balanceOf(user);
        return ((balance * (rewardPerToken() - userRewardPerTokenPaid[user])) / 1e18) + userRewards[user];
    }
    
    function getRewardForDuration() external view returns (uint256) {
        return rewardRate * rewardsCycleLength;
    }
    
    // ========== MUTATIVE FUNCTIONS ==========
    
    /// @notice Load rewards from external sources (adapted notifyRewardAmount)
    function loadRewards() external payable onlyMinter nonReentrant updateReward(address(0)) returns (uint256 amount) {
        amount = msg.value;
        _loadRewards(amount);
        return amount;
    }
    
    /// @notice Internal function to distribute rewards (Synthetix notifyRewardAmount logic)
    function _loadRewards(uint256 reward) internal {
        if (reward > 0) {
            uint256 yieldAmount = (reward * YIELD_FEE) / RATIO_PRECISION;
            uint256 netReward = reward - yieldAmount;
            
            // Send fee to protocol
            if (yieldAmount > 0) {
                IstPlumeMinter(stPlumeMinter).addWithHoldFee{value: yieldAmount}();
            }

            if (netReward > 0) {
                (bool success,) = stPlumeMinter.call{value: netReward}(""); // send rewards to be staked to earn more rewards
                require(success, "Rewards transfer failed");
            }
            
            // Process net reward using Synthetix logic
            if (block.timestamp >= rewardsCycleEnd) {
                rewardRate = netReward / rewardsCycleLength;
            } else {
                uint256 remaining = rewardsCycleEnd - block.timestamp;
                uint256 leftover = remaining * rewardRate;
                rewardRate = (netReward + leftover) / rewardsCycleLength;
            }
            
            // Ensure reward rate is not too high
            // require(rewardRate <= frxETHToken.totalSupply() / rewardsCycleLength, "Provided reward too high");
            
            lastSync = block.timestamp;
            rewardsCycleEnd = block.timestamp + rewardsCycleLength;
            
            emit NewRewardsCycle(uint32(rewardsCycleEnd), netReward);
        }
    }
    
    /// @notice Handle token transfer to track user rewards
    function handleTokenTransfer(address user) external onlyRole(HANDLER_ROLE) updateReward(user) {}
    
    /// @notice Reset user rewards after claim (adapted getReward logic)
    function resetUserRewardsAfterClaim(address user) external onlyMinter updateReward(user) {
        uint256 reward = userRewards[user];
        if (reward > 0) {
            userRewards[user] = 0;
        }
    }
    
    /// @notice Sync rewards manually (similar to notifyRewardAmount with 0)
    function syncRewards() nonReentrant onlyMinter public updateReward(address(0)) {}

    function syncUser(address user) nonReentrant onlyMinter public updateReward(user) {}
    
    // ========== ADMIN FUNCTIONS ==========
    
    /// @notice Set yield fee percentage
    function setYieldFee(uint256 newYieldFee) nonReentrant external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newYieldFee <= 500000, "Fees too high");
        YIELD_FEE = newYieldFee;
    }
    
    /// @notice Set rewards cycle length (adapted setRewardsDuration)
    function setRewardsCycleLength(uint256 newLength) nonReentrant external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            block.timestamp > rewardsCycleEnd,
            "Previous rewards period must be complete before changing the duration"
        );
        require(newLength >= 1 days && newLength <= 365 days, "Invalid cycle length");
        rewardsCycleLength = newLength;
    }
        
    /// @notice Get current total yield (for compatibility)
    function getYield() public view returns (uint256) {
        // Return current reward per token for compatibility
        return rewardPerToken();
    }
    
    receive() external payable {
        // Only accept ETH from the minter
        require(
            msg.sender == stPlumeMinter,
            "Unauthorized sender"
        );
    }
}