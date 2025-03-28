// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IPlumeStaking } from "../interfaces/IPlumeStaking.sol";

import {
    CooldownPeriodNotEnded,
    InvalidAmount,
    NoActiveStake,
    TokenDoesNotExist,
    TokensInCoolingPeriod
} from "../lib/PlumeErrors.sol";
import { CoolingCompleted, RewardClaimed, Staked, Unstaked, Withdrawn } from "../lib/PlumeEvents.sol";
import { PlumeStakingStorage } from "../lib/PlumeStakingStorage.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title PlumeStakingBase
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Base contract for the PlumeStaking system with core functionality
 */
abstract contract PlumeStakingBase is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    IPlumeStaking
{

    using SafeERC20 for IERC20;
    using Address for address payable;

    // Constants
    /// @notice Role for administrators of PlumeStaking
    bytes32 public constant override ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @notice Role for upgraders of PlumeStaking
    bytes32 public constant override UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    /// @notice Maximum reward rate: ~100% APY (3171 nanotoken per second per token)
    uint256 public constant override MAX_REWARD_RATE = 3171 * 1e9;
    /// @notice Scaling factor for reward calculations
    uint256 public constant override REWARD_PRECISION = 1e18;
    /// @notice Base unit for calculations (equivalent to REWARD_PRECISION)
    uint256 public constant override BASE = 1e18;
    /// @notice Address constant used to represent the native PLUME token
    address public constant override PLUME = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /**
     * @notice Initialize PlumeStaking
     * @param owner Address of the owner of PlumeStaking
     * @param pUSD_ Address of the pUSD token
     */
    function initialize(address owner, address pUSD_) public virtual override initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        $.pUSD = IERC20(pUSD_);
        $.minStakeAmount = 1e18;
        $.cooldownInterval = 7 days;

        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(ADMIN_ROLE, owner);
        _grantRole(UPGRADER_ROLE, owner);
    }

    /**
     * @notice Authorize upgrade by role
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER_ROLE) { }

    /**
     * @notice Stake PLUME into the contract
     */
    function stake() external payable virtual override nonReentrant returns (uint256) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        PlumeStakingStorage.StakeInfo storage info = $.stakeInfo[msg.sender];

        uint256 amount = msg.value;

        if (amount < $.minStakeAmount) {
            revert InvalidAmount(amount, $.minStakeAmount);
        }

        _updateRewards(msg.sender);

        // Update total staked amount - simple direct stake
        info.staked += amount;
        $.totalStaked += amount;

        _updateRewards(msg.sender);
        _addStakerIfNew(msg.sender);

        // Only from wallet - no other sources
        emit Staked(msg.sender, amount, 0, 0, amount);
        return amount;
    }

    /**
     * @notice Unstake PLUME from the contract
     * @return amount Amount of PLUME unstaked
     */
    function unstake() external virtual override nonReentrant returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        PlumeStakingStorage.StakeInfo storage info = $.stakeInfo[msg.sender];

        if (info.staked == 0) {
            revert NoActiveStake();
        }

        _updateRewards(msg.sender);

        // Get unstaked amount
        amount = info.staked;

        // Update user's staked amount
        info.staked = 0;
        $.totalStaked -= amount;

        // Move tokens to cooling period
        info.cooled += amount;
        $.totalCooling += amount;
        info.cooldownEnd = block.timestamp + $.cooldownInterval;

        emit Unstaked(msg.sender, amount);
        return amount;
    }

    /**
     * @notice Withdraw PLUME that has completed the cooldown period
     * @return amount Amount of PLUME withdrawn
     */
    function withdraw() external virtual override nonReentrant returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        PlumeStakingStorage.StakeInfo storage info = $.stakeInfo[msg.sender];

        // Move cooled tokens to parked if cooldown has ended
        if (info.cooled > 0 && info.cooldownEnd <= block.timestamp) {
            info.parked += info.cooled;
            $.totalWithdrawable += info.cooled;
            $.totalCooling -= info.cooled;
            info.cooled = 0;
            info.cooldownEnd = 0;
        }

        // Withdraw all parked tokens
        amount = info.parked;
        if (amount == 0) {
            revert InvalidAmount(amount, 1);
        }

        // Clear user's parked amount
        info.parked = 0;
        $.totalWithdrawable -= amount;

        // Transfer native tokens to the user
        (bool success,) = payable(msg.sender).call{ value: amount }("");
        require(success, "Native token transfer failed");

        emit Withdrawn(msg.sender, amount);
        return amount;
    }

    /**
     * @notice Claim all accumulated rewards from a single token
     * @param token Address of the reward token to claim
     * @return amount Amount of reward token claimed
     */
    function claim(
        address token
    ) external virtual override nonReentrant returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        if (!_isRewardToken(token)) {
            revert TokenDoesNotExist(token);
        }

        _updateRewards(msg.sender);

        amount = $.rewards[msg.sender][token];
        if (amount > 0) {
            $.rewards[msg.sender][token] = 0;

            // Update total claimable
            if ($.totalClaimableByToken[token] >= amount) {
                $.totalClaimableByToken[token] -= amount;
            } else {
                $.totalClaimableByToken[token] = 0;
            }

            // Transfer ERC20 tokens
            if (token != PLUME) {
                IERC20(token).safeTransfer(msg.sender, amount);
            } else {
                // For native token rewards
                (bool success,) = payable(msg.sender).call{ value: amount }("");
                require(success, "Native token transfer failed");
            }

            emit RewardClaimed(msg.sender, token, amount);
        }

        return amount;
    }

    /**
     * @notice Claim all accumulated rewards from all tokens
     * @return amounts Array of amounts claimed for each token
     */
    function claimAll() external virtual override nonReentrant returns (uint256[] memory amounts) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        address[] memory tokens = $.rewardTokens;
        amounts = new uint256[](tokens.length);

        _updateRewards(msg.sender);

        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 amount = $.rewards[msg.sender][token];

            if (amount > 0) {
                $.rewards[msg.sender][token] = 0;
                amounts[i] = amount;

                // Update total claimable
                if ($.totalClaimableByToken[token] >= amount) {
                    $.totalClaimableByToken[token] -= amount;
                } else {
                    $.totalClaimableByToken[token] = 0;
                }

                // Transfer ERC20 tokens
                if (token != PLUME) {
                    IERC20(token).safeTransfer(msg.sender, amount);
                } else {
                    // For native token rewards
                    (bool success,) = payable(msg.sender).call{ value: amount }("");
                    require(success, "Native token transfer failed");
                }

                emit RewardClaimed(msg.sender, token, amount);
            }
        }

        return amounts;
    }

    /**
     * @notice Get information about the staking contract
     */
    function stakingInfo()
        external
        view
        virtual
        override
        returns (
            uint256 totalStaked,
            uint256 totalCooling,
            uint256 totalWithdrawable,
            uint256 minStakeAmount,
            address[] memory rewardTokens
        )
    {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        return ($.totalStaked, $.totalCooling, $.totalWithdrawable, $.minStakeAmount, $.rewardTokens);
    }

    /**
     * @notice Get staking information for a user
     */
    function stakeInfo(
        address user
    ) external view virtual override returns (PlumeStakingStorage.StakeInfo memory) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        return $.stakeInfo[user];
    }

    /**
     * @notice Returns the amount of PLUME currently staked by the caller
     */
    function amountStaked() external view virtual override returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        return $.stakeInfo[msg.sender].staked;
    }

    /**
     * @notice Returns the amount of PLUME currently in cooling period for the caller
     */
    function amountCooling() external view virtual override returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        PlumeStakingStorage.StakeInfo storage info = $.stakeInfo[msg.sender];

        // If cooldown has ended, return 0
        if (info.cooldownEnd != 0 && block.timestamp >= info.cooldownEnd) {
            return 0;
        }

        return info.cooled;
    }

    /**
     * @notice Returns the amount of PLUME that is withdrawable for the caller
     */
    function amountWithdrawable() external view virtual override returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        PlumeStakingStorage.StakeInfo storage info = $.stakeInfo[msg.sender];

        amount = info.parked;
        if (info.cooled > 0 && info.cooldownEnd <= block.timestamp) {
            amount += info.cooled;
        }

        return amount;
    }

    /**
     * @notice Get the claimable reward amount for a user and token
     * @param user Address of the user to check
     * @param token Address of the reward token
     * @return amount Amount of reward token claimable
     */
    function getClaimableReward(address user, address token) external view virtual override returns (uint256 amount) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        if (!_isRewardToken(token)) {
            return 0;
        }

        return _earned(user, token, $.stakeInfo[user].staked);
    }

    // Internal utility functions
    /**
     * @notice Add a staker to the list if they are not already in it
     */
    function _addStakerIfNew(
        address staker
    ) internal {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        if ($.stakeInfo[staker].staked > 0 && !$.isStaker[staker]) {
            $.stakers.push(staker);
            $.isStaker[staker] = true;
        }
    }

    /**
     * @notice Update rewards for a user
     */
    function _updateRewards(
        address user
    ) internal {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        address[] memory rewardTokens = $.rewardTokens;

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            _updateRewardPerToken(token);

            if (user != address(0)) {
                uint256 oldReward = $.rewards[user][token];
                uint256 newReward = _earned(user, token, $.stakeInfo[user].staked);

                // Update total claimable tracking
                if (newReward > oldReward) {
                    $.totalClaimableByToken[token] += (newReward - oldReward);
                } else if (oldReward > newReward) {
                    // This shouldn't happen in normal operation, but we handle it to be safe
                    uint256 decrease = oldReward - newReward;
                    if ($.totalClaimableByToken[token] >= decrease) {
                        $.totalClaimableByToken[token] -= decrease;
                    } else {
                        $.totalClaimableByToken[token] = 0;
                    }
                }

                $.rewards[user][token] = newReward;
                $.userRewardPerTokenPaid[user][token] = $.rewardPerTokenCumulative[token];
            }
        }
    }

    /**
     * @notice Update the reward per token value
     */
    function _updateRewardPerToken(
        address token
    ) internal {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        if ($.totalStaked > 0) {
            uint256 timeDelta = block.timestamp - $.lastUpdateTimes[token];
            if (timeDelta > 0 && $.rewardRates[token] > 0) {
                uint256 reward = (timeDelta * $.rewardRates[token] * REWARD_PRECISION) / $.totalStaked;
                $.rewardPerTokenCumulative[token] += reward;
            }
        }

        $.lastUpdateTimes[token] = block.timestamp;
    }

    /**
     * @notice Calculate the earned rewards for a user
     */
    function _earned(address user, address token, uint256 userStakedAmount) internal view returns (uint256 rewards) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        uint256 rewardPerToken = $.rewardPerTokenCumulative[token];

        // If there are currently staked tokens, add the rewards that have accumulated since last update
        if ($.totalStaked > 0) {
            uint256 timeDelta = block.timestamp - $.lastUpdateTimes[token];
            if (timeDelta > 0 && $.rewardRates[token] > 0) {
                rewardPerToken += (timeDelta * $.rewardRates[token] * REWARD_PRECISION) / $.totalStaked;
            }
        }

        return $.rewards[user][token]
            + ((userStakedAmount * (rewardPerToken - $.userRewardPerTokenPaid[user][token])) / REWARD_PRECISION);
    }

    /**
     * @notice Check if a token is in the rewards list
     */
    function _isRewardToken(
        address token
    ) internal view returns (bool) {
        return _getTokenIndex(token) < PlumeStakingStorage.layout().rewardTokens.length;
    }

    /**
     * @notice Get the index of a token in the rewards list
     */
    function _getTokenIndex(
        address token
    ) internal view returns (uint256) {
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();
        address[] memory tokens = $.rewardTokens;

        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token) {
                return i;
            }
        }

        return tokens.length;
    }

}
