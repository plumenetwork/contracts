// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PLUMEStaking is ReentrancyGuard, Pausable, Ownable {

    IERC20 public plumeToken;
    IERC20 public pUSDToken;

    struct StakeInfo {
        uint256 amount;
        uint256 unlockTime;
        uint256 lastRewardClaim;
    }

    mapping(address => StakeInfo) public stakes;
    uint256 public constant UNSTAKE_DELAY = 14 days;
    uint256 public totalStaked;
    uint256 public rewardRate; // pUSD per PLUME per second

    event Staked(address indexed user, uint256 amount);
    event UnstakeRequested(address indexed user, uint256 unlockTime);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);

    constructor(address _plumeToken, address _pUSDToken) {
        plumeToken = IERC20(_plumeToken);
        pUSDToken = IERC20(_pUSDToken);
        rewardRate = 1e15; // 0.001 pUSD per PLUME per second (approximately 3% APY)
    }

    function stake(
        uint256 amount
    ) external nonReentrant whenNotPaused {
        require(amount > 0, "Cannot stake 0");
        require(plumeToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        StakeInfo storage userStake = stakes[msg.sender];
        userStake.amount += amount;
        userStake.lastRewardClaim = block.timestamp;
        totalStaked += amount;

        emit Staked(msg.sender, amount);
    }

    function requestUnstake() external nonReentrant whenNotPaused {
        StakeInfo storage userStake = stakes[msg.sender];
        require(userStake.amount > 0, "No stake found");
        require(userStake.unlockTime == 0, "Unstake already requested");

        userStake.unlockTime = block.timestamp + UNSTAKE_DELAY;
        emit UnstakeRequested(msg.sender, userStake.unlockTime);
    }

    function unstake() external nonReentrant whenNotPaused {
        StakeInfo storage userStake = stakes[msg.sender];
        require(userStake.unlockTime > 0, "Must request unstake first");
        require(block.timestamp >= userStake.unlockTime, "Still in unstake delay period");

        uint256 amount = userStake.amount;
        require(amount > 0, "No stake found");

        userStake.amount = 0;
        userStake.unlockTime = 0;
        totalStaked -= amount;

        require(plumeToken.transfer(msg.sender, amount), "Transfer failed");
        emit Unstaked(msg.sender, amount);
    }

    function claimRewards() external nonReentrant whenNotPaused {
        StakeInfo storage userStake = stakes[msg.sender];
        require(userStake.amount > 0, "No stake found");

        uint256 reward = calculateReward(msg.sender);
        require(reward > 0, "No rewards to claim");

        userStake.lastRewardClaim = block.timestamp;
        require(pUSDToken.transfer(msg.sender, reward), "Reward transfer failed");

        emit RewardClaimed(msg.sender, reward);
    }

    function calculateReward(
        address user
    ) public view returns (uint256) {
        StakeInfo storage userStake = stakes[user];
        if (userStake.amount == 0) {
            return 0;
        }

        uint256 duration = block.timestamp - userStake.lastRewardClaim;
        return userStake.amount * duration * rewardRate / 1e18;
    }

}
