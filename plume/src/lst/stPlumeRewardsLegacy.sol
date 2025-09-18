// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

// ====================================================================
// |                      Plume stPlumeRewards                        |
// ====================================================================
// Reward management for stPlumeMinter

import { IPlumeStaking } from "./interfaces/IPlumeStaking.sol";
import { IstPlumeRewardsLegacy as IstPlumeRewards } from "./interfaces/IstPlumeRewardsLegacy.sol";
import { IstPlumeMinter } from "./interfaces/IstPlumeMinter.sol";
import { frxETH } from "./frxETH.sol";
import { AccessControlUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";

/// @title stPlumeRewards - Reward system for the stPlumeMinter contract
/// @notice Handles all reward-related functionality for frxETH token holders
contract stPlumeRewardsLegacy is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, IstPlumeRewards {
    // Role definitions
    bytes32 public constant CLAIMER_ROLE = keccak256("CLAIMER_ROLE");
    bytes32 public constant HANDLER_ROLE = keccak256("HANDLER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    
    // Fees
    uint256 public YIELD_FEE; // 10%
    uint256 public constant RATIO_PRECISION = 1e6;
    
    // Reward state
    uint256 public yieldEth; // reward accrued + future next rewards
    uint256 public rewardsEth; // current rewards across cycles
    uint32 public rewardsCycleLength; // reward cycle length
    uint32 public lastSync;
    uint32 public rewardsCycleEnd;
    uint256 public lastRewardAmount; // reward in this unfinished cycle
    uint256[50] private __gap;
    
    CycleRewards[] public cycleRewards;
    mapping(address => UserRewards) public userRewards;
    
    // Contract references
    frxETH public frxETHToken;
    address public stPlumeMinter;
    
    // Events
    event RewardClaimed(address indexed user, address indexed token, uint256 amount);
    event AllRewardsClaimed(address indexed user, uint256[] totalAmount);
    event ValidatorRewardClaimed(address indexed user, address indexed token, uint16 indexed validatorId, uint256 amount);
    
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
        rewardsCycleEnd = uint32(block.timestamp + rewardsCycleLength);
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
    
    /// @notice Load rewards from external sources
    function loadRewards() external payable onlyMinter returns (uint256 amount) {
        amount = msg.value;
        _loadRewards(amount);
        return amount;
    }
    
    /// @notice Internal function to distribute rewards
    function _loadRewards(uint256 amount) internal {
        if (amount > 0) {
            uint256 yieldAmount = amount * YIELD_FEE / RATIO_PRECISION;
            yieldEth += amount - yieldAmount;
            // Return the fee amount to the minter
            if (amount > 0) {
                IstPlumeMinter(stPlumeMinter).addWithHoldFee{value: yieldAmount}(); //send fee to protocol
                (bool success,) = stPlumeMinter.call{value: amount - yieldAmount}(""); // send rewards to be staked to earn more rewards
                require(success, "Rewards transfer failed");
            }
        }
        
        if (block.timestamp >= rewardsCycleEnd) {syncRewards();}
    }
    
    /// @notice Handle token transfer to track user rewards
    function handleTokenTransfer(address user) external onlyRole(HANDLER_ROLE) {
        uint256 balance = frxETHToken.balanceOf(user);
        (uint256 accruedRewards, uint256 currentRewards) = _getSplitYield();
        userRewards[user].rewardsAccrued += _getCurrentUserYield(user, balance); // accrue reward to avoid reward loss
        userRewards[user].rewardsBefore = accruedRewards + currentRewards;
        userRewards[user].rewardInCycle = currentRewards;
        userRewards[user].lastCycleClaimed = cycleRewards.length;
    }
    
    /// @notice Get current rewards for a user
    function getUserRewards(address user) public view returns (uint256 yield) {
        uint256 balance = frxETHToken.balanceOf(user);
        uint256 normalizedAmount = balance + userRewards[user].rewardsAccrued + _getCurrentUserYield(user, balance);
        yield = normalizedAmount - balance;
    }
    
    /// @notice Reset user rewards after claim
    function resetUserRewardsAfterClaim(address user) external onlyMinter {
        (uint256 accruedRewards, uint256 currentRewards) = _getSplitYield();
        userRewards[user].rewardsAccrued = 0;
        userRewards[user].rewardsBefore = accruedRewards + currentRewards;
        userRewards[user].rewardInCycle = currentRewards;
        userRewards[user].lastCycleClaimed = cycleRewards.length;
    }
    
    /// @notice Split the yield between accrued and current rewards
    function _getSplitYield() internal view returns (uint256, uint256) {
        if (block.timestamp >= rewardsCycleEnd) {
            return (rewardsEth - lastRewardAmount, lastRewardAmount);
        }
        
        uint256 maxTime = rewardsCycleEnd > block.timestamp ? block.timestamp : rewardsCycleEnd;
        uint256 unlockedRewards = (lastRewardAmount * (maxTime - lastSync)) / (rewardsCycleEnd - lastSync);
        return (rewardsEth - lastRewardAmount, unlockedRewards);
    }
    
    /// @notice Calculate current yield for a user
    function _getCurrentUserYield(address user, uint256 amount) internal view returns (uint256) {
        uint256 totalYield = 0;
        uint256 userLastCycle = userRewards[user].lastCycleClaimed;
        (, uint256 currentRewards) = _getSplitYield();
        uint256 totalSupply = frxETHToken.totalSupply();
        uint256 eligibleRewards = currentRewards > userRewards[user].rewardInCycle ? currentRewards - userRewards[user].rewardInCycle : 0;

        if (totalSupply == 0) return 0;
        if (amount == 0) return 0;
        if (userLastCycle == 0) return 0;
        
        for (uint256 i = userLastCycle; i < cycleRewards.length; i++) {
            if (amount > 0) {
                CycleRewards memory cycle = cycleRewards[i];
                if (cycle.totalSupply > 0) {
                    totalYield += (amount * cycle.rewards) / cycle.totalSupply;
                }
            }
        }

        return totalYield + (eligibleRewards * amount / totalSupply);
    }
    
    /// @notice Sync rewards at the end of a cycle
    function syncRewards() nonReentrant public {
        uint256 timestamp = block.timestamp;
        require(timestamp >= rewardsCycleEnd, "Not in rewards cycle");
        require(yieldEth >= rewardsEth, "Negative rewards");
    
        uint256 nextRewards = yieldEth - rewardsEth;
        rewardsEth += nextRewards;
        cycleRewards.push(CycleRewards({
            rewards: lastRewardAmount,
            totalSupply: frxETHToken.totalSupply(),
            cycleEnd: rewardsCycleEnd
        }));
        
        uint256 end = timestamp + rewardsCycleLength;

        lastRewardAmount = nextRewards;
        lastSync = uint32(timestamp);
        rewardsCycleEnd = uint32(end);
    }
    
    /// @notice Set yield fee percentage
    function setYieldFee(uint256 newYieldFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newYieldFee <= 500000, "Fees too high");
        YIELD_FEE = newYieldFee;
    }
    
    /// @notice Set rewards cycle length
    function setRewardsCycleLength(uint32 newLength) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newLength >= 1 days && newLength <= 365 days, "Invalid cycle length");
        rewardsCycleLength = newLength;
    }
    
    /// @notice Get current total yield
    function getYield() public view returns (uint256) {
        if (block.timestamp >= rewardsCycleEnd) {
            return rewardsEth;
        }
        
        uint256 maxTime = rewardsCycleEnd > block.timestamp ? block.timestamp : rewardsCycleEnd;
        uint256 unlockedRewards = (lastRewardAmount * (maxTime - lastSync)) / (rewardsCycleEnd - lastSync);
        return rewardsEth - lastRewardAmount + unlockedRewards;
    }
    
    receive() external payable {
        // Only accept ETH from the minter
        require(
            msg.sender == stPlumeMinter,
            "Unauthorized sender"
        );
    }
}
