// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { Plume } from "./Plume.sol";

/**
 * @title PlumeStaking
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Staking contract for $PLUME
 */
contract PlumeStaking is Initializable, AccessControlUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {

    using SafeERC20 for Plume;
    using SafeERC20 for IERC20;

    // Storage

    /// @custom:storage-location erc7201:plume.storage.PlumeStaking
    struct PlumeStakingStorage {
        /// @dev Address of the $PLUME token
        Plume plume;
        /// @dev Address of the $pUSD token
        IERC20 pUSD;
        /// @dev Minimum amount of $PLUME that can be staked
        uint256 minStakeAmount;
        /// @dev Cooldown interval for unstaked assets to be unlocked and parked
        uint256 cooldownInterval;
        /// @dev Detailed active stake info for each user
        mapping(address user => StakeInfo info) stakeInfo;
        /// @dev List of reward tokens (ERC20) to be distributed as rewards
        address[] rewardTokens;
        /// @dev Mapping from reward token address to its per-second reward rate (scaled by _BASE)
        mapping(address => uint256) rewardRates;
        /// @dev Mapping from user to reward token to accumulated reward amount
        mapping(address => mapping(address => uint256)) rewardAccrued;
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.PlumeStaking")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PLUME_STAKING_STORAGE_LOCATION =
        0x40f2ca4cf3a525ed9b1b2649f0f850db77540accc558be58ba47f8638359e800;

    function _getPlumeStakingStorage() internal pure returns (PlumeStakingStorage storage $) {
        assembly {
            $.slot := PLUME_STAKING_STORAGE_LOCATION
        }
    }

    // Structs

    /// @dev Detailed active stake information for each user
    struct StakeInfo {
        /// @dev Amount of $PLUME staked
        uint256 staked;
        /// @dev Amount of $PLUME deposited but not staked by the user
        uint256 parked;
        /// @dev Amount of $PLUME that are in cooldown, i.e. unstaked but not yet withdrawable
        uint256 cooled;
        /// @dev Timestamp at which the cooldown period ends for the stake
        uint256 cooldownEnd;
        /// @dev Accumulated rewards for the stake
        uint256 accumulatedRewards;
        /// @dev Timestamp at which the stake info was last updated
        uint256 lastUpdateTimestamp;
    }

    // Constants

    /// @notice Role for the admin of PlumeStaking
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @notice Role for the upgrader of PlumeStaking
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// @notice Scaling factor for reward rates
    uint256 public constant _BASE = 1e18;

    // Events

    /**
     * @notice Emitted when the minimum stake amount is set
     * @param minStakeAmount Minimum amount of $PLUME that can be staked
     */
    event SetMinStakeAmount(uint256 minStakeAmount);

    /**
     * @notice Emitted when the cooldown interval is set
     * @param cooldownInterval Cooldown interval for staked assets to be unlocked and parked
     */
    event SetCooldownInterval(uint256 cooldownInterval);

    /**
     * @notice Emitted when the rate of $pUSD rewarded per $PLUME staked per second is set
     * @param token Address of the reward token
     * @param rewardRate Rate of token rewarded per $PLUME staked per second, scaled by _BASE
     */
    event SetRewardRate(address indexed token, uint256 rewardRate);

    /**
     * @notice Emitted when a user parks $PLUME
     * @param user Address of the user that parked $PLUME
     * @param amount Amount of $PLUME parked
     */
    event Parked(address indexed user, uint256 amount);

    /**
     * @notice Emitted when a user stakes $PLUME
     * @param user Address of the user that staked $PLUME
     * @param amount Amount of $PLUME staked
     */
    event Staked(address indexed user, uint256 amount);

    /**
     * @notice Emitted when a user unstakes $PLUME
     * @param user Address of the user that unstaked $PLUME
     * @param amount Amount of $PLUME unstaked
     */
    event Unstaked(address indexed user, uint256 amount);

    /**
     * @notice Emitted when a user unparks $PLUME
     * @param user Address of the user that unparked $PLUME
     * @param amount Amount of $PLUME unparked
     */
    event Unparked(address indexed user, uint256 amount);

    /**
     * @notice Emitted when a user claims $pUSD
     * @param user Address of the user that claimed $pUSD
     * @param amount Amount of $pUSD claimed
     */
    event ClaimedRewards(address indexed user, address indexed token, uint256 amount);

    // Errors

    /**
     * @notice Indicates a failure because the amount is invalid
     * @param amount Amount of $PLUME requested
     * @param minStakeAmount Minimum amount of $PLUME allowed
     */
    error InvalidAmount(uint256 amount, uint256 minStakeAmount);

    /**
     * @notice Indicates a failure because the user has insufficient balance
     * @param amount Amount of $PLUME requested
     * @param balance Amount of $PLUME available
     */
    error InsufficientBalance(uint256 amount, uint256 balance);

    /**
     * @notice Indicates a failure because the cooldown period has not ended
     * @dev TODO remove this restriction in the future
     * @param endTime Timestamp at which the cooldown period ends
     */
    error CooldownPeriodNotEnded(uint256 endTime);

    error NoActiveStake();

    // Initializer

    /**
     * @notice Prevent the implementation contract from being initialized or reinitialized
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize PlumeStaking
     * @dev Give all roles to the admin address passed into the constructor
     * @param owner Address of the owner of PlumeStaking
     */
    function initialize(address owner, address plume_, address pUSD_) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        $.plume = Plume(plume_);
        $.pUSD = IERC20(pUSD_);
        $.minStakeAmount = 1e18;
        $.cooldownInterval = 7 days;

        // Set initial reward tokens.
        // According to spec, rewards are initially paid out in both pUSD and PLUME.
        $.rewardTokens.push(pUSD_);
        $.rewardTokens.push(plume_);
        // Set initial reward rates (example values). Replace with the desired economics.
        // For example, both are set to 6e15 (this value can be updated by admin).
        $.rewardRates[pUSD_] = (_BASE * 5 * 12) / (100 * 100); // 6e15
        $.rewardRates[plume_] = (_BASE * 5 * 12) / (100 * 100); // 6e15

        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(ADMIN_ROLE, owner);
        _grantRole(UPGRADER_ROLE, owner);
    }

    // Override Functions

    /**
     * @notice Revert when `msg.sender` is not authorized to upgrade the contract
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER_ROLE) { }

    // Internal Functions

    /**
     * @notice Update the reward accumulated by the given user
     * @param user Address of the user
     */
    function _updateRewards(
        address user
    ) internal {
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        StakeInfo storage info = s.stakeInfo[user];
        uint256 delta = block.timestamp - info.lastUpdateTimestamp;
        if (delta > 0 && info.staked > 0) {
            // For each reward token, update the accrued reward.
            for (uint256 i = 0; i < s.rewardTokens.length; i++) {
                address token = s.rewardTokens[i];
                uint256 rate = s.rewardRates[token];
                s.rewardAccrued[user][token] += (info.staked * delta * rate) / _BASE;
            }
            info.lastUpdateTimestamp = block.timestamp;
        }
    }

    // Admin Functions

    /**
     * @notice Set the minimum amount of $PLUME that can be staked
     * @param minStakeAmount_ Minimum amount of $PLUME that can be staked
     */
    function setMinStakeAmount(
        uint256 minStakeAmount_
    ) external onlyRole(ADMIN_ROLE) nonReentrant {
        _getPlumeStakingStorage().minStakeAmount = minStakeAmount_;
        emit SetMinStakeAmount(minStakeAmount_);
    }

    /**
     * @notice Set the cooldown interval for staked assets to be unlocked and parked
     * @param cooldownInterval_ Cooldown interval for staked assets to be unlocked and parked
     */
    function setCooldownInterval(
        uint256 cooldownInterval_
    ) external onlyRole(ADMIN_ROLE) nonReentrant {
        _getPlumeStakingStorage().cooldownInterval = cooldownInterval_;
        emit SetCooldownInterval(cooldownInterval_);
    }

    /**
     * @notice Set the rate of $pUSD rewarded per $PLUME staked per second
     * @param token Address of the reward token
     * @param rewardRate_ Rate of token rewarded per $PLUME staked per second, scaled by _BASE
     */
    function setRewardRate(address token, uint256 rewardRate_) external onlyRole(ADMIN_ROLE) nonReentrant {
        _getPlumeStakingStorage().rewardRates[token] = rewardRate_;
        emit SetRewardRate(token, rewardRate_);
    }

    // User Functions

    /**
     * @notice Park $PLUME in the contract
     * @param amount Amount of $PLUME to park
     */
    function park(
        uint256 amount
    ) external nonReentrant {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        if (amount < $.minStakeAmount) {
            revert InvalidAmount(amount, $.minStakeAmount);
        }

        $.plume.safeTransferFrom(msg.sender, address(this), amount);
        $.stakeInfo[msg.sender].parked += amount;

        emit Parked(msg.sender, amount);
    }

    /**
     * @notice Stake $PLUME in the contract
     * @param amount Amount of $PLUME to stake
     */
    function stake(
        uint256 amount
    ) external nonReentrant {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        StakeInfo storage info = $.stakeInfo[msg.sender];

        if ($.stakeInfo[msg.sender].cooldownEnd > block.timestamp) {
            revert CooldownPeriodNotEnded($.stakeInfo[msg.sender].cooldownEnd);
        }
        if (amount < $.minStakeAmount) {
            revert InvalidAmount(amount, $.minStakeAmount);
        }
        if (info.parked < amount) {
            revert InsufficientBalance(amount, info.parked);
        }

        _updateRewards(msg.sender);
        info.parked -= amount;
        info.staked += amount;

        emit Staked(msg.sender, amount);
    }

    /**
     * @notice Park and stake $PLUME in the contract
     * @param amount Amount of $PLUME to park and stake
     */
    function parkAndStake(
        uint256 amount
    ) external nonReentrant {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        StakeInfo storage info = $.stakeInfo[msg.sender];

        if (info.cooldownEnd > block.timestamp) {
            revert CooldownPeriodNotEnded(info.cooldownEnd);
        }
        if (amount < $.minStakeAmount) {
            revert InvalidAmount(amount, $.minStakeAmount);
        }

        _updateRewards(msg.sender);
        $.plume.safeTransferFrom(msg.sender, address(this), amount);
        info.staked += amount;

        emit Parked(msg.sender, amount);
        emit Staked(msg.sender, amount);
    }

    /**
     * @notice Unstake $PLUME from the contract
     * @return amount Amount of $PLUME unstaked
     * @dev TODO for current prototype, the implementation is limited because:
     *   - you cannot set the amount that you unstake; it all unstakes at once
     *   - you cannot stake again until after the cooldown period ends
     */
    function unstake() external nonReentrant returns (uint256 amount) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        StakeInfo storage info = $.stakeInfo[msg.sender];

        _updateRewards(msg.sender);

        amount = info.staked;
        // Reset staked amount and move it into cooled.
        $.stakeInfo[msg.sender].staked = 0;
        $.stakeInfo[msg.sender].cooled += amount;
        $.stakeInfo[msg.sender].cooldownEnd = block.timestamp + $.cooldownInterval;

        emit Unstaked(msg.sender, amount);
    }

    /**
     * @notice Unpark $PLUME from the contract
     * @param amount Amount of $PLUME to unpark
     */
    function unpark(
        uint256 amount
    ) external nonReentrant {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        StakeInfo storage info = $.stakeInfo[msg.sender];

        _updateRewards(msg.sender);

        // If cooldown period has passed, move cooled funds to parked.
        if (info.cooled > 0 && info.cooldownEnd <= block.timestamp) {
            info.parked += info.cooled;
            info.cooled = 0;
            info.cooldownEnd = 0;
        }
        if (amount > info.parked) {
            revert InsufficientBalance(amount, info.parked);
        }
        info.parked -= amount;
        $.plume.safeTransfer(msg.sender, amount);
        emit Unparked(msg.sender, amount);
    }

    /// @notice Claim all $pUSD rewards from the contract
    function claim() external nonReentrant {
        _updateRewards(msg.sender);
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();

        for (uint256 i = 0; i < $.rewardTokens.length; i++) {
            address token = $.rewardTokens[i];
            uint256 amount = $.rewardAccrued[msg.sender][token];
            if (amount > 0) {
                $.rewardAccrued[msg.sender][token] = 0;
                IERC20(token).safeTransfer(msg.sender, amount);
                emit ClaimedRewards(msg.sender, token, amount);
            }
        }
    }

    // View Functions

    /// @notice Address of the $PLUME token
    function plume() external view returns (Plume) {
        return _getPlumeStakingStorage().plume;
    }

    /// @notice Minimum amount of $PLUME that can be staked
    function minStakeAmount() external view returns (uint256) {
        return _getPlumeStakingStorage().minStakeAmount;
    }

    /// @notice Cooldown interval for staked assets to be unlocked and parked
    function cooldownInterval() external view returns (uint256) {
        return _getPlumeStakingStorage().cooldownInterval;
    }

    /// @notice Rate of $pUSD rewarded per $PLUME staked per second, scaled by _BASE
    function rewardRate(
        address token
    ) external view returns (uint256) {
        return _getPlumeStakingStorage().rewardRates[token];
    }

    /**
     * @notice Detailed active stake information for a user
     * @param user Address of the user
     * @return info Detailed active stake information for the user
     */
    function stakeInfo(
        address user
    ) external view returns (StakeInfo memory info) {
        info = _getPlumeStakingStorage().stakeInfo[user];
    }

    /**
     * @notice Withdrawable balance of a user
     * @param user Address of the user
     * @return amount Amount of $PLUME available to unpark
     */
    function withdrawableBalance(
        address user
    ) external view returns (uint256 amount) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        StakeInfo storage info = $.stakeInfo[user];
        amount = info.parked;
        if (info.cooled > 0 && info.cooldownEnd >= block.timestamp) {
            amount += info.cooled;
        }
    }

    /**
     * @notice Returns the claimable reward for a user for a given reward token.
     * @param user Address of the user.
     * @param token Address of the reward token.
     * @return amount Claimable reward amount.
     */
    function getClaimableReward(address user, address token) external view returns (uint256 amount) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        StakeInfo storage info = $.stakeInfo[user];
        uint256 pending = 0;
        if (info.staked > 0 && block.timestamp > info.lastUpdateTimestamp) {
            pending = (info.staked * (block.timestamp - info.lastUpdateTimestamp) * $.rewardRates[token]) / _BASE;
        }
        amount = $.rewardAccrued[user][token] + pending;
    }

    /**
     * @notice Claimable $pUSD rewards of a user
     * @param user Address of the user
     * @return amount Amount of $pUSD available to claim
     */
    function claimableBalance(
        address user
    ) public view returns (uint256 amount) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        StakeInfo storage info = $.stakeInfo[user];

        uint256 pending = 0;
        if (info.staked > 0 && block.timestamp > info.lastUpdateTimestamp) {
            pending =
                (info.staked * (block.timestamp - info.lastUpdateTimestamp) * $.rewardRates[address($.pUSD)]) / _BASE;
        }
        amount = $.rewardAccrued[user][address($.pUSD)] + pending;
    }

}
