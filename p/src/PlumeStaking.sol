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
        /// @dev Maximum interval for which assets can be staked for
        uint256 maxStakeInterval;
        /// @dev Cooldown interval for unstaked tokens to be unlocked and parked
        uint256 cooldownInterval;
        /// @dev Default auto-compounding period for new stakes (in seconds; 0 = disabled)
        uint256 defaultAutoCompoundPeriod;
        /// @dev Amount of $PLUME deposited but not staked
        mapping(address => uint256) parked;
        /// @dev Amount of $PLUME that are in cooldown (unstaked but not yet withdrawable)
        mapping(address => uint256) cooldownAmount;
        /// @dev Timestamp at which the cooldown period ends for a user
        mapping(address => uint256) cooldownEnd;
        /// @dev Array of allowed lockup options, each with a duration and an APY (in basis points)
        LockupOption[] lockupOptions;
        /// @dev Mapping of user address to their detailed active stake info
        mapping(address => StakeInfo) stakeInfo;
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

    /**
     * @dev Struct defining a lockup option with a duration and an APY in basis points.
     */
    struct LockupOption {
        uint256 duration; // in seconds
        uint256 apy; // in basis points (e.g., 300 means 3% APY)
    }

    /**
     * @dev Struct storing detailed information about a user's active stake.
     */
    struct StakeInfo {
        uint256 amount; // Amount of $PLUME staked
        uint256 startTime; // Timestamp when the stake was initiated
        uint256 lockDuration; // Duration for which the stake is locked (in seconds)
        uint256 rewardRate; // Per-second reward rate (scaled by 1e18)
        uint256 lastRewardClaim; // Timestamp of the last reward update
        uint256 autoCompoundPeriod; // Auto-compounding period in seconds (0 to disable)
        uint256 accumulatedRewards; // Accumulated rewards not yet claimed or compounded
    }

    // Constants

    /// @notice Role for the upgrader of PlumeStaking
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // Events

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
     * @param timestamp Timestamp at which the assets at stake unlock
     */
    event Staked(address indexed user, uint256 amount, uint256 timestamp);

    /**
     * @notice Emitted when a user extends the time of their stake
     * @param user Address of the user that extended the time of their stake
     * @param timestamp Timestamp at which the assets at stake unlock
     */
    event ExtendedTime(address indexed user, uint256 timestamp);

    /**
     * @notice Emitted when a user unstakes $PLUME
     * @param user Address of the user that unstaked $PLUME
     * @param amount Amount of $PLUME unstaked
     */
    event Unstaked(address indexed user, uint256 amount);

    event PartialUnstaked(address indexed user, uint256 amount);

    /**
     * @notice Emitted when a user unparks $PLUME
     * @param user Address of the user that unparked $PLUME
     * @param amount Amount of $PLUME unparked
     */
    event Unparked(address indexed user, uint256 amount);

    /**
     * @notice Emitted when a user claims $PLUME
     * @param user Address of the user that claimed $PLUME
     * @param amount Amount of $PLUME claimed
     */
    event ClaimedPlume(address indexed user, uint256 amount);

    /**
     * @notice Emitted when a user claims $pUSD
     * @param user Address of the user that claimed $pUSD
     * @param amount Amount of $pUSD claimed
     */
    event ClaimedStable(address indexed user, uint256 amount);

    /**
     * @notice Emitted when rewards are compounded for a user
     * @param user Address of the user
     * @param amount Amount of rewards compounded
     */
    event RewardsCompounded(address indexed user, uint256 amount);

    /**
     * @notice Emitted when a user sets their auto-compounding period
     * @param user Address of the user
     * @param period The auto-compounding period set (in seconds)
     */
    event AutoCompoundPeriodSet(address indexed user, uint256 period);

    // --- Admin Parameter Update Events ---
    event MinStakeAmountUpdated(uint256 newMinStakeAmount);
    event MaxStakeIntervalUpdated(uint256 newMaxStakeInterval);
    event CooldownIntervalUpdated(uint256 newCooldownInterval);
    event DefaultAutoCompoundPeriodUpdated(uint256 newDefaultAutoCompoundPeriod);
    event LockupOptionAdded(uint256 index, uint256 duration, uint256 apy);
    event LockupOptionUpdated(uint256 index, uint256 duration, uint256 apy);
    event LockupOptionRemoved(uint256 index);
    event RewardPoolFunded(uint256 amount);

    // Errors

    /**
     * @notice Indicates a failure because the amount is invalid
     * @param amount Amount of $PLUME requested
     * @param minStakeAmount Minimum amount of $PLUME allowed
     */
    error InvalidAmount(uint256 amount, uint256 minStakeAmount);

    /// @notice Indicates a failure because the unlock time is invalid
    error InvalidUnlockTime();

    /// @notice Indicates a failure because the assets at stake are not unlocked
    error NotUnlocked();

    /**
     * @notice Indicates a failure because the user has insufficient balance
     * @param amount Amount of $PLUME requested
     * @param balance Amount of $PLUME available
     */
    error InsufficientBalance(uint256 amount, uint256 balance);

    /**
     * @notice Indicates a failure because the user has insufficient stablecoin balance
     * @param amount Amount of $pUSD requested
     * @param balance Amount of $pUSD available
     */
    error InsufficientStableBalance(uint256 amount, uint256 balance);

    /**
     * @notice Indicates a failure because the cooldown period has not ended
     * @dev TODO remove this restriction in the future
     * @param endTime Timestamp at which the cooldown period ends
     */
    error CooldownPeriodNotEnded(uint256 endTime);

    /// @notice Indicates that a user already has an active stake
    error ActiveStakeExists();

    /// @notice Indicates that a user does not have an active stake
    error NoActiveStake();

    error InvalidAutoCompoundPeriod();
    error InvalidIndex();

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
    function initialize(address owner, address plume_, address pUSD) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        $.plume = Plume(plume_);
        $.pUSD = IERC20(pUSD);
        $.minStakeAmount = 1e18;
        $.maxStakeInterval = 365 * 4 + 1 days;
        $.cooldownInterval = 7 days;

        // Initialize default lockup options with corresponding APY values (in basis points)
        // For example:
        // 6 months (approx. 180 days) => 300 (3% APY)
        // 12 months (approx. 365 days) => 500 (5% APY)
        // 4 years (max) => 900 (9% APY)
        $.lockupOptions.push(LockupOption({ duration: 180 days, apy: 300 }));
        $.lockupOptions.push(LockupOption({ duration: 365 days, apy: 500 }));
        $.lockupOptions.push(LockupOption({ duration: $.maxStakeInterval, apy: 900 }));

        _grantRole(DEFAULT_ADMIN_ROLE, owner);
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

    // ================================================
    // INTERNAL HELPER FUNCTIONS
    // ================================================

    /**
     * @notice Computes the per-second reward rate (scaled by 1e18) from an APY expressed in basis points.
     * @param apyBasisPoints APY in basis points (e.g., 300 for 3%)
     * @return rewardRate The computed per-second reward rate
     */
    function _computeRewardRate(
        uint256 apyBasisPoints
    ) internal pure returns (uint256 rewardRate) {
        // Calculate the per-second reward rate (scaled by 1e18).
        // The APY is given in basis points, so dividing by 10000 converts it to a decimal percentage.
        // Then, dividing by 31,536,000 (the number of seconds in a year) converts the annual rate into a per-second
        // rate.
        // Multiplying by 1e18 ensures that the result is stored in fixed-point format for precision.
        //rewardRate = (apyBasisPoints * 1e18) / (10_000 * 31_536_000);
        rewardRate = (apyBasisPoints * 1e27) / 10_000; // Scale up first division
        rewardRate = rewardRate / 31_536_000; // Apply second division
        rewardRate = rewardRate / 1e9; // Scale back down to 1e18
    }

    /**
     * @notice Returns the allowed lockup option that has the largest duration not exceeding 'remaining'.
     * @dev If none exists, returns the option with the minimum duration.
     */
    function _findBestOption(
        uint256 remaining
    ) internal view returns (LockupOption memory option) {
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        uint256 optionsLength = s.lockupOptions.length;
        bool found = false;
        uint256 bestDuration = 0;
        uint256 bestAPY = 0;
        for (uint256 i = 0; i < optionsLength; i++) {
            if (s.lockupOptions[i].duration <= remaining && s.lockupOptions[i].duration > bestDuration) {
                bestDuration = s.lockupOptions[i].duration;
                bestAPY = s.lockupOptions[i].apy;
                found = true;
            }
        }
        if (!found) {
            // If no option fits, choose the option with the minimum duration.
            option = s.lockupOptions[0];
            for (uint256 i = 1; i < optionsLength; i++) {
                if (s.lockupOptions[i].duration < option.duration) {
                    option = s.lockupOptions[i];
                }
            }
        } else {
            option = LockupOption({ duration: bestDuration, apy: bestAPY });
        }
    }

    /**
     * @notice Updates the rewards for a user's active stake.
     * @dev If auto-compounding is enabled and the elapsed time exceeds the auto-compounding period, rewards are
     * compounded.
     *      Otherwise, rewards accumulate for manual claiming or compounding.
     * @param user Address of the user
     */
    function _updateReward(
        address user
    ) internal {
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        StakeInfo storage info = s.stakeInfo[user];
        if (info.amount == 0) {
            return;
        }
        uint256 elapsed = block.timestamp - info.lastRewardClaim;
        if (elapsed == 0) {
            return;
        }

        if (info.autoCompoundPeriod > 0) {
            uint256 completePeriods = elapsed / info.autoCompoundPeriod;
            uint256 remainder = elapsed % info.autoCompoundPeriod;
            if (completePeriods > 0) {
                // Calculate the multiplier for the complete auto-compound periods.
                // The per-period multiplier is (1 + rewardRate)^(autoCompoundPeriod)
                uint256 periodMultiplier = _fixedExp(1e18 + info.rewardRate, info.autoCompoundPeriod);
                // For multiple periods, raise the per-period multiplier to the completePeriods power.
                uint256 multiplier = _fixedExp(periodMultiplier, completePeriods);
                uint256 newAmount = (info.amount * multiplier) / 1e18;
                uint256 compoundedReward = newAmount - info.amount;
                info.amount = newAmount;
                emit RewardsCompounded(user, compoundedReward);
            }
            if (remainder > 0) {
                uint256 remainderReward = (info.amount * remainder * info.rewardRate) / 1e18;
                info.accumulatedRewards += remainderReward;
            }
        } else {
            uint256 reward = (info.amount * elapsed * info.rewardRate) / 1e18;
            info.accumulatedRewards += reward;
        }
        info.lastRewardClaim = block.timestamp;
    }

    /**
     * @notice Computes the effective per-second reward rate for a given staking duration.
     * @dev Decomposes the requested duration into segments corresponding to allowed lockup options
     *      (using _findBestOption) and calculates a weighted-average APY.
     * @param duration The requested staking duration in seconds.
     * @return rewardRate The computed per-second reward rate.
     */
    function _computeEffectiveRewardRate(
        uint256 duration
    ) internal view returns (uint256 rewardRate) {
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        uint256 totalWeightedAPY = 0;
        uint256 remaining = duration;
        uint256 composedDuration = 0;
        uint256 optionsLength = s.lockupOptions.length;
        require(optionsLength > 0, "No lockup options available");

        while (remaining > 0) {
            LockupOption memory opt = _findBestOption(remaining);
            uint256 count = remaining / opt.duration;
            if (count == 0) {
                break;
            } // safety
            uint256 segment = count * opt.duration;
            totalWeightedAPY += segment * opt.apy;
            composedDuration += segment;
            remaining -= segment;
        }
        // For any remainder, use the option with the smallest duration.
        if (remaining > 0) {
            LockupOption memory smallest = s.lockupOptions[0];
            for (uint256 i = 1; i < optionsLength; i++) {
                if (s.lockupOptions[i].duration < smallest.duration) {
                    smallest = s.lockupOptions[i];
                }
            }
            totalWeightedAPY += remaining * smallest.apy;
            composedDuration += remaining;
            remaining = 0;
        }
        require(composedDuration >= duration - 1 && composedDuration <= duration + 1, "Duration mismatch");
        uint256 effectiveAPY = totalWeightedAPY / duration;
        rewardRate = _computeRewardRate(effectiveAPY);
    }

    /**
     * @notice Fixed-point exponentiation.
     * @dev Computes base^exp where base is fixed-point with 1e18 scale.
     *      Uses exponentiation by squaring.
     */
    function _fixedExp(uint256 base, uint256 exp) internal pure returns (uint256 result) {
        result = 1e18; // 1 in fixed-point
        while (exp > 0) {
            if (exp % 2 == 1) {
                result = (result * base) / 1e18;
            }
            base = (base * base) / 1e18;
            exp /= 2;
        }
    }

    /**
     * @notice Internal view function to calculate the total pending reward for a user.
     * @dev Combines the stored reward (from previous updates) with pending rewards accrued from the active stake.
     *      Rewards accrue continuously according to:
     *          reward = (stakedAmount * elapsedTime * rewardRate) / 1e18
     *      Note that if auto-compounding is enabled (autoCompoundPeriod > 0), rewards are compounded immediately
     *      and therefore no manual reward accrual is available.
     * @param user Address of the user.
     * @return totalReward The total reward accrued (in 1e18 fixed–point units).
     */
    function _totalReward(
        address user
    ) internal view returns (uint256 totalReward) {
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        uint256 pendingReward = 0;
        StakeInfo storage info = s.stakeInfo[user];
        if (info.amount > 0 && info.autoCompoundPeriod == 0) {
            uint256 elapsed = block.timestamp - info.lastRewardClaim;
            pendingReward = info.accumulatedRewards + ((info.amount * elapsed * info.rewardRate) / 1e18);
        }
        totalReward = pendingReward;
    }

    // Admin Setters

    function setMinStakeAmount(
        uint256 newMinStakeAmount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        $.minStakeAmount = newMinStakeAmount;
        emit MinStakeAmountUpdated(newMinStakeAmount);
    }

    function setMaxStakeInterval(
        uint256 newMaxStakeInterval
    ) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        $.maxStakeInterval = newMaxStakeInterval;
        emit MaxStakeIntervalUpdated(newMaxStakeInterval);
    }

    function setCooldownInterval(
        uint256 newCooldownInterval
    ) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        $.cooldownInterval = newCooldownInterval;
        emit CooldownIntervalUpdated(newCooldownInterval);
    }

    function setDefaultAutoCompoundPeriod(
        uint256 newDefaultAutoCompoundPeriod
    ) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        $.defaultAutoCompoundPeriod = newDefaultAutoCompoundPeriod;
        emit DefaultAutoCompoundPeriodUpdated(newDefaultAutoCompoundPeriod);
    }

    function addLockupOption(uint256 duration, uint256 apy) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        $.lockupOptions.push(LockupOption({ duration: duration, apy: apy }));
        emit LockupOptionAdded($.lockupOptions.length - 1, duration, apy);
    }

    function updateLockupOption(
        uint256 index,
        uint256 duration,
        uint256 apy
    ) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        if (index >= s.lockupOptions.length) {
            revert InvalidIndex();
        }
        s.lockupOptions[index] = LockupOption({ duration: duration, apy: apy });
        emit LockupOptionUpdated(index, duration, apy);
    }

    function removeLockupOption(
        uint256 index
    ) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        if (index >= s.lockupOptions.length) {
            revert InvalidIndex();
        }
        s.lockupOptions[index] = s.lockupOptions[s.lockupOptions.length - 1];
        s.lockupOptions.pop();
        emit LockupOptionRemoved(index);
    }

    function fundRewardPool(
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        SafeERC20.safeTransferFrom($.pUSD, msg.sender, address(this), amount);
        emit RewardPoolFunded(amount);
    }

    // User Functions

    /**
     * @notice Set the auto–compounding period for the active stake.
     * @dev The period must be 0 (to disable auto-compounding) or a multiple of 90 days and not exceed the stake's lock
     * duration.
     * @param period The auto-compounding period in seconds.
     */
    function setAutoCompoundPeriod(
        uint256 period
    ) external nonReentrant {
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        StakeInfo storage info = s.stakeInfo[msg.sender];
        if (info.amount == 0) {
            revert NoActiveStake();
        }
        if (period > 0 && (period % (90 days) != 0 || period > info.lockDuration)) {
            revert InvalidAutoCompoundPeriod();
        }
        info.autoCompoundPeriod = period;
        emit AutoCompoundPeriodSet(msg.sender, period);
    }

    /**
     * @notice Park $PLUME in the contract
     * @param amount Amount of $PLUME to park
     */
    function park(
        uint256 amount
    ) external {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        if (amount < $.minStakeAmount) {
            revert InvalidAmount(amount, $.minStakeAmount);
        }

        SafeERC20.safeTransferFrom($.plume, msg.sender, address(this), amount);
        $.parked[msg.sender] += amount;

        emit Parked(msg.sender, amount);
    }

    /**
     * @notice Stake PLUME using parked funds.
     * @param amount Amount to stake.
     * @param timestamp Unlock timestamp.
     */
    function stake(uint256 amount, uint256 timestamp) external nonReentrant {
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        if (amount < s.minStakeAmount) {
            revert InvalidAmount(amount, s.minStakeAmount);
        }
        if (timestamp <= block.timestamp || timestamp > block.timestamp + s.maxStakeInterval) {
            revert InvalidUnlockTime();
        }
        if (s.parked[msg.sender] < amount) {
            revert InsufficientBalance(amount, s.parked[msg.sender]);
        }
        s.parked[msg.sender] -= amount;
        uint256 lockDuration = timestamp - block.timestamp;
        uint256 computedRewardRate = _computeEffectiveRewardRate(lockDuration);
        s.stakeInfo[msg.sender] = StakeInfo({
            amount: amount,
            startTime: block.timestamp,
            lockDuration: lockDuration,
            rewardRate: computedRewardRate,
            lastRewardClaim: block.timestamp,
            autoCompoundPeriod: s.defaultAutoCompoundPeriod,
            accumulatedRewards: 0
        });
        emit Staked(msg.sender, amount, timestamp);
    }

    /**
     * @notice Park and stake PLUME in one transaction.
     * @param amount Amount to stake.
     * @param timestamp Unlock timestamp.
     */
    function parkAndStake(uint256 amount, uint256 timestamp) external nonReentrant {
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        if (amount < s.minStakeAmount) {
            revert InvalidAmount(amount, s.minStakeAmount);
        }
        if (timestamp <= block.timestamp || timestamp > block.timestamp + s.maxStakeInterval) {
            revert InvalidUnlockTime();
        }
        SafeERC20.safeTransferFrom(s.plume, msg.sender, address(this), amount);
        uint256 lockDuration = timestamp - block.timestamp;
        uint256 computedRewardRate = _computeEffectiveRewardRate(lockDuration);
        s.stakeInfo[msg.sender] = StakeInfo({
            amount: amount,
            startTime: block.timestamp,
            lockDuration: lockDuration,
            rewardRate: computedRewardRate,
            lastRewardClaim: block.timestamp,
            autoCompoundPeriod: s.defaultAutoCompoundPeriod,
            accumulatedRewards: 0
        });
        emit Parked(msg.sender, amount);
        emit Staked(msg.sender, amount, timestamp);
    }

    /**
     * @notice Extend the unlock time for the staked assets
     * @param timestamp New timestamp at which the assets at stake unlock
     */
    /**
     * @notice Extend the unlock time for the active stake.
     * @param timestamp New unlock timestamp.
     */
    function extendTime(
        uint256 timestamp
    ) external nonReentrant {
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        StakeInfo storage info = s.stakeInfo[msg.sender];
        uint256 currentUnlock = info.startTime + info.lockDuration;
        if (timestamp <= currentUnlock || timestamp > currentUnlock + s.maxStakeInterval) {
            revert InvalidUnlockTime();
        }
        uint256 newLockDuration = timestamp - block.timestamp;
        info.lockDuration = newLockDuration;
        info.rewardRate = _computeEffectiveRewardRate(newLockDuration);
        info.lastRewardClaim = block.timestamp;
        emit ExtendedTime(msg.sender, timestamp);
    }

    /**
     * @notice Unstake a portion of the active stake.
     * @param amount Amount to unstake.
     * @return unstakedAmount Amount that was unstaked.
     */
    function partialUnstake(
        uint256 amount
    ) external nonReentrant returns (uint256 unstakedAmount) {
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        StakeInfo storage info = s.stakeInfo[msg.sender];
        if (block.timestamp < info.startTime + info.lockDuration) {
            revert NotUnlocked();
        }
        if (amount == 0 || amount > info.amount) {
            revert InsufficientBalance(amount, info.amount);
        }
        _updateReward(msg.sender);
        info.amount -= amount;
        unstakedAmount = amount;
        s.cooldownAmount[msg.sender] += amount;
        s.cooldownEnd[msg.sender] = block.timestamp + s.cooldownInterval;
        emit PartialUnstaked(msg.sender, amount);
    }

    /**
     * @notice Unstake $PLUME from the contract
     * @return unstakedAmount amount Amount of $PLUME unstaked
     */
    function unstake() external nonReentrant returns (uint256 unstakedAmount) {
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        StakeInfo storage info = s.stakeInfo[msg.sender];
        uint256 unlockTimeUser = info.startTime + info.lockDuration;
        if (block.timestamp < unlockTimeUser) {
            revert NotUnlocked();
        }
        unstakedAmount = info.amount;
        delete s.stakeInfo[msg.sender];
        s.cooldownAmount[msg.sender] += unstakedAmount;
        s.cooldownEnd[msg.sender] = block.timestamp + s.cooldownInterval;
        emit Unstaked(msg.sender, unstakedAmount);
    }

    /**
     * @notice Unpark $PLUME from the contract
     * @param amount Amount of $PLUME to unpark
     */
    function unpark(
        uint256 amount
    ) external nonReentrant {
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        if (s.cooldownEnd[msg.sender] <= block.timestamp && s.cooldownAmount[msg.sender] > 0) {
            s.parked[msg.sender] += s.cooldownAmount[msg.sender];
            s.cooldownAmount[msg.sender] = 0;
        }
        if (amount > s.parked[msg.sender]) {
            revert InsufficientBalance(amount, s.parked[msg.sender]);
        }
        s.parked[msg.sender] -= amount;
        SafeERC20.safeTransfer(s.plume, msg.sender, amount);
        emit Unparked(msg.sender, amount);
    }

    /**
     * @notice Claim $PLUME
     * @param amount Amount of $PLUME to claim
     */
    function claimPlume(
        uint256 amount
    ) external nonReentrant {
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        uint256 totalReward = _totalReward(msg.sender);
        uint256 availableStable = s.pUSD.balanceOf(address(this));
        // Rewards are distributed primarily in pUSD; any shortfall is paid in PLUME.
        uint256 plumeReward = (availableStable >= totalReward) ? 0 : totalReward - availableStable;
        if (amount > plumeReward) {
            revert InsufficientBalance(amount, plumeReward);
        }
        // For simplicity, we assume that internal accounting is updated off-chain or via further logic.
        SafeERC20.safeTransfer(s.plume, msg.sender, amount);
        emit ClaimedPlume(msg.sender, amount);
    }

    /**
     * @notice Claim $pUSD
     * @param amount Amount of $pUSD to claim
     */
    function claimStable(
        uint256 amount
    ) external nonReentrant {
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        uint256 totalReward = _totalReward(msg.sender);
        uint256 availableStable = s.pUSD.balanceOf(address(this));
        uint256 stableReward = (availableStable >= totalReward) ? totalReward : availableStable;
        if (amount > stableReward) {
            revert InsufficientBalance(amount, stableReward);
        }
        SafeERC20.safeTransfer(s.pUSD, msg.sender, amount);
        emit ClaimedStable(msg.sender, amount);
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

    /// @notice Maximum interval for which assets can be staked for
    function maxStakeInterval() external view returns (uint256) {
        return _getPlumeStakingStorage().maxStakeInterval;
    }

    /// @notice Cooldown interval for staked assets to be unlocked and parked
    function cooldownInterval() external view returns (uint256) {
        return _getPlumeStakingStorage().cooldownInterval;
    }

    function cooldownAmount(
        address user
    ) external view returns (uint256) {
        return _getPlumeStakingStorage().cooldownAmount[user];
    }

    /**
     * @notice Returns the unlock timestamp for a user's active stake.
     */
    function stakeUnlockTime(
        address user
    ) external view returns (uint256) {
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        StakeInfo storage info = s.stakeInfo[user];
        return info.startTime + info.lockDuration;
    }

    /**
     * @notice Amount of $PLUME parked by a user
     * @param user Address of the user
     * @return amount Amount of $PLUME parked by the user
     */
    function parked(
        address user
    ) external view returns (uint256) {
        return _getPlumeStakingStorage().parked[user];
    }

    /**
     * @notice Timestamp at which the cooldown period ends when the user is unstaking
     * @param user Address of the user
     * @return timestamp Timestamp at which the cooldown period ends
     */
    function cooldownEnd(
        address user
    ) external view returns (uint256) {
        return _getPlumeStakingStorage().cooldownEnd[user];
    }

    /**
     * @notice Claimable $PLUME balance of a user
     * @param user Address of the user
     * @return amount Amount of $PLUME available to claim
     */
    function claimablePlumeBalance(
        address user
    ) public view returns (uint256 amount) {
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        uint256 total = _totalReward(user);
        uint256 availableStable = s.pUSD.balanceOf(address(this));
        // If available pUSD is enough to cover the total reward, then no PLUME payout is needed.
        if (availableStable >= total) {
            amount = 0;
        } else {
            amount = total - availableStable;
        }
    }

    /**
     * @notice Claimable $pUSD balance of a user
     * @param user Address of the user
     * @return amount Amount of $pUSD available to claim
     */
    function claimableStableBalance(
        address user
    ) public view returns (uint256 amount) {
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        uint256 total = _totalReward(user);
        uint256 availableStable = s.pUSD.balanceOf(address(this));
        if (availableStable >= total) {
            amount = total;
        } else {
            amount = availableStable;
        }
    }

    /**
     * @notice Retrieve the detailed stake info for a user.
     * @param user Address of the user.
     * @return info The StakeInfo struct for the user.
     */
    function getStakeInfo(
        address user
    ) external view returns (StakeInfo memory info) {
        return _getPlumeStakingStorage().stakeInfo[user];
    }

}
