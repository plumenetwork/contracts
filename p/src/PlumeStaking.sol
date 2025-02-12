// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Plume } from "./Plume.sol";

/**
 * @title PlumeStaking
 * @author Eugene Y. Q. Shen
 * @notice Staking contract for $PLUME
 */
contract PlumeStaking is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{

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
        /// @dev Cooldown interval for staked assets to be unlocked and parked
        uint256 cooldownInterval;
        /// @dev Amount of $PLUME staked by each user
        mapping(address user => uint256 amount) staked;
        /// @dev Amount of $PLUME parked by each user
        mapping(address user => uint256 amount) parked;
        /// @dev Amount of $PLUME awaiting cooldown by each user
        mapping(address user => uint256 amount) cooled;
        /// @dev Timestamp at which the assets at stake unlock for each user
        mapping(address user => uint256 timestamp) unlockTime;
        /// @dev Timestamp at which the cooldown period ends when the user is unstaking
        mapping(address user => uint256 timestamp) cooldownEnd;
        /// @dev Amount of $PLUME available to claim by each user
        mapping(address user => uint256 amount) claimablePlume;
        /// @dev Amount of $pUSD available to claim by each user
        mapping(address user => uint256 amount) claimableStable;
        /// @dev Array of allowed lockup options, each with a duration and an APY (in basis points)
        LockupOption[] lockupOptions;
        /// @dev Mapping of user address to their detailed stake info
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
        uint256 apy;      // in basis points (e.g., 300 means 3% APY)
    }

    /**
     * @dev Struct storing detailed information about a user's active stake.
     */
    struct StakeInfo {
        uint256 amount;           // Amount of $PLUME staked
        uint256 startTime;        // Timestamp when the stake was initiated
        uint256 lockDuration;     // Duration for which the stake is locked (in seconds)
        uint256 rewardRate;       // Per-second reward rate (scaled by 1e18)
        uint256 lastRewardClaim;  // Timestamp of the last reward update
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
    function initialize(
        address owner,
        address plume_,
        address pUSD
    ) public initializer {
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
    function _computeRewardRate(uint256 apyBasisPoints)
        internal
        pure
        returns (uint256 rewardRate)
    {
        rewardRate = (apyBasisPoints * 1e18) / (10000 * 31536000);
    }

    /**
     * @notice Updates the rewards for a user's active stake.
     * @dev If auto-compounding is enabled and the elapsed time exceeds the auto-compounding period, rewards are compounded.
     *      Otherwise, rewards accumulate for manual claiming or compounding.
     * @param user Address of the user
     */
    function _updateReward(address user) internal {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        StakeInfo storage info = $.stakeInfo[user];
        if (info.amount == 0) {
            return;
        }
        uint256 elapsed = block.timestamp - info.lastRewardClaim;
        if (elapsed > 0) {
            uint256 reward = (info.amount * elapsed * info.rewardRate) / 1e18;
            if (info.autoCompoundPeriod > 0 && elapsed >= info.autoCompoundPeriod) {
                // Auto-compound rewards: add rewards directly to the staked amount
                info.amount += reward;
                emit RewardsCompounded(user, reward);
            } else {
                // Accumulate rewards for manual claiming/compounding
                info.accumulatedRewards += reward;
            }
            info.lastRewardClaim = block.timestamp;
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
    function _totalReward(address user) internal view returns (uint256 totalReward) {
        PlumeStakingStorage storage s = _getPlumeStakingStorage();

        // Stored reward from previous updates in claimablePlume mapping.
        uint256 storedReward = s.claimablePlume[user];
        uint256 pendingReward = 0;
        StakeInfo storage info = s.stakeInfo[user];

        // Only add pending rewards if the user has an active stake and auto-compounding is disabled.
        if (info.amount > 0 && info.autoCompoundPeriod == 0) {
            uint256 elapsed = block.timestamp - info.lastRewardClaim;
            pendingReward = info.accumulatedRewards + ((info.amount * elapsed * info.rewardRate) / 1e18);
        }
        totalReward = storedReward + pendingReward;
    }



    // Admin Setters

    function setMinStakeAmount(uint256 newMinStakeAmount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonReentrant
    {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        $.minStakeAmount = newMinStakeAmount;
        emit MinStakeAmountUpdated(newMinStakeAmount);
    }

    function setMaxStakeInterval(uint256 newMaxStakeInterval)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonReentrant
    {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        $.maxStakeInterval = newMaxStakeInterval;
        emit MaxStakeIntervalUpdated(newMaxStakeInterval);
    }

    function setCooldownInterval(uint256 newCooldownInterval)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonReentrant
    {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        $.cooldownInterval = newCooldownInterval;
        emit CooldownIntervalUpdated(newCooldownInterval);
    }

    function setDefaultAutoCompoundPeriod(uint256 newDefaultAutoCompoundPeriod)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonReentrant
    {
        // Optionally, you might check that newDefaultAutoCompoundPeriod is a multiple of 90 days.
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        $.defaultAutoCompoundPeriod = newDefaultAutoCompoundPeriod;
        emit DefaultAutoCompoundPeriodUpdated(newDefaultAutoCompoundPeriod);
    }

    function addLockupOption(uint256 duration, uint256 apy)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonReentrant
    {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        $.lockupOptions.push(LockupOption({ duration: duration, apy: apy }));
        emit LockupOptionAdded($.lockupOptions.length - 1, duration, apy);
    }

    function updateLockupOption(uint256 index, uint256 duration, uint256 apy)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonReentrant
    {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        require(index < $.lockupOptions.length, "Invalid index");
        $.lockupOptions[index] = LockupOption({ duration: duration, apy: apy });
        emit LockupOptionUpdated(index, duration, apy);
    }

    function removeLockupOption(uint256 index)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonReentrant
    {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        require(index < $.lockupOptions.length, "Invalid index");
        // Swap with last and pop.
        $.lockupOptions[index] = $.lockupOptions[$.lockupOptions.length - 1];
        $.lockupOptions.pop();
        emit LockupOptionRemoved(index);
    }

    function fundRewardPool(uint256 amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonReentrant
    {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        SafeERC20.safeTransferFrom($.pUSD, msg.sender, address(this), amount);
        emit RewardPoolFunded(amount);
    }

    // User Functions

    /**
     * @notice Set the auto–compounding period for the active stake.
     * @dev The period must be 0 (to disable auto-compounding) or a multiple of 90 days and not exceed the stake's lock duration.
     * @param period The auto-compounding period in seconds.
     */
    function setAutoCompoundPeriod(uint256 period) external nonReentrant {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        StakeInfo storage info = $.stakeInfo[msg.sender];
        if (info.amount == 0) {
            revert NoActiveStake();
        }
        if (period > 0) {
            // Check that period is a multiple of 90 days and does not exceed the lock duration.
            if (period % (90 days) != 0 || period > info.lockDuration) {
                revert InvalidUnlockTime();
            }
        }
        info.autoCompoundPeriod = period;
        emit AutoCompoundPeriodSet(msg.sender, period);
    }


    /**
     * @notice Park $PLUME in the contract
     * @param amount Amount of $PLUME to park
     */
    function park(uint256 amount) external {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        if (amount < $.minStakeAmount) {
            revert InvalidAmount(amount, $.minStakeAmount);
        }

        SafeERC20.safeTransferFrom($.plume, msg.sender, address(this), amount);
        $.parked[msg.sender] += amount;

        emit Parked(msg.sender, amount);
    }
    
    /**
     * @notice Stake $PLUME in the contract using parked funds.
     * @dev TODO: unlockTime == 0 for auto-extending staking.
     * @param amount Amount of $PLUME to stake.
     * @param timestamp Timestamp at which the assets at stake unlock.
     */
    function stake(uint256 amount, uint256 timestamp) external nonReentrant {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        if ($.cooldownEnd[msg.sender] > block.timestamp) {
            revert CooldownPeriodNotEnded($.cooldownEnd[msg.sender]);
        }
        if (amount < $.minStakeAmount) {
            revert InvalidAmount(amount, $.minStakeAmount);
        }
        if (
            ($.unlockTime[msg.sender] != 0 && timestamp != $.unlockTime[msg.sender])
            || timestamp <= block.timestamp 
            || timestamp > block.timestamp + $.maxStakeInterval
        ) {
            revert InvalidUnlockTime();
        }
        if ($.parked[msg.sender] < amount) {
            revert InsufficientBalance(amount, $.parked[msg.sender]);
        }

        $.parked[msg.sender] -= amount;
        $.staked[msg.sender] += amount;
        if ($.unlockTime[msg.sender] == 0) {
            $.unlockTime[msg.sender] = timestamp;
        }

        // Initialize the user's detailed stake info.
        uint256 lockDuration = timestamp - block.timestamp;
        bool found = false;
        LockupOption memory option;
        for (uint256 i = 0; i < $.lockupOptions.length; i++) {
            if ($.lockupOptions[i].duration == lockDuration) {
                option = $.lockupOptions[i];
                found = true;
                break;
            }
        }
        if (!found) {
            revert InvalidUnlockTime();
        }
        $.stakeInfo[msg.sender] = StakeInfo({
            amount: amount,
            startTime: block.timestamp,
            lockDuration: lockDuration,
            rewardRate: _computeRewardRate(option.apy),
            lastRewardClaim: block.timestamp,
            autoCompoundPeriod: 0,
            accumulatedRewards: 0
        });

        emit Staked(msg.sender, amount, timestamp);
    }

    /**
     * @notice Park and stake $PLUME in the contract
     * @dev TODO unlockTime == 0 for auto-extending staking
     * @param amount Amount of $PLUME to park and stake
     * @param timestamp Timestamp at which the assets at stake unlock
     */
function parkAndStake(uint256 amount, uint256 timestamp) external nonReentrant {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        if ($.cooldownEnd[msg.sender] > block.timestamp) {
            revert CooldownPeriodNotEnded($.cooldownEnd[msg.sender]);
        }
        if (amount < $.minStakeAmount) {
            revert InvalidAmount(amount, $.minStakeAmount);
        }
        if (
            ($.unlockTime[msg.sender] != 0 && timestamp != $.unlockTime[msg.sender])
            || timestamp <= block.timestamp 
            || timestamp > block.timestamp + $.maxStakeInterval
        ) {
            revert InvalidUnlockTime();
        }

        SafeERC20.safeTransferFrom($.plume, msg.sender, address(this), amount);
        $.staked[msg.sender] += amount;
        if ($.unlockTime[msg.sender] == 0) {
            $.unlockTime[msg.sender] = timestamp;
        }

        // Initialize detailed stake info.
        uint256 lockDuration = timestamp - block.timestamp;
        bool found = false;
        LockupOption memory option;
        for (uint256 i = 0; i < $.lockupOptions.length; i++) {
            if ($.lockupOptions[i].duration == lockDuration) {
                option = $.lockupOptions[i];
                found = true;
                break;
            }
        }
        if (!found) {
            revert InvalidUnlockTime();
        }
        $.stakeInfo[msg.sender] = StakeInfo({
            amount: amount,
            startTime: block.timestamp,
            lockDuration: lockDuration,
            rewardRate: _computeRewardRate(option.apy),
            lastRewardClaim: block.timestamp,
            autoCompoundPeriod: $.defaultAutoCompoundPeriod,
            accumulatedRewards: 0
        });

        emit Parked(msg.sender, amount);
        emit Staked(msg.sender, amount, timestamp);
    }

    /**
     * @notice Extend the unlock time for the staked assets
     * @param timestamp New timestamp at which the assets at stake unlock
     */
 function extendTime(uint256 timestamp) external nonReentrant {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        if ($.cooldownEnd[msg.sender] > block.timestamp) {
            revert CooldownPeriodNotEnded($.cooldownEnd[msg.sender]);
        }
        uint256 currentUnlock = $.unlockTime[msg.sender];
        if (timestamp <= currentUnlock || timestamp > currentUnlock + $.maxStakeInterval) {
            revert InvalidUnlockTime();
        }
        uint256 newLockDuration = timestamp - block.timestamp;
        $.unlockTime[msg.sender] = timestamp;
        // Update detailed stake info.
        StakeInfo storage info = $.stakeInfo[msg.sender];
        if (info.amount == 0) {
            revert NoActiveStake();
        }
        bool found = false;
        LockupOption memory option;
        for (uint256 i = 0; i < $.lockupOptions.length; i++) {
            if ($.lockupOptions[i].duration == newLockDuration) {
                option = $.lockupOptions[i];
                found = true;
                break;
            }
        }
        if (!found) {
            revert InvalidUnlockTime();
        }
        info.lockDuration = newLockDuration;
        info.rewardRate = _computeRewardRate(option.apy);
        info.lastRewardClaim = block.timestamp;
        emit ExtendedTime(msg.sender, timestamp);
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
        if ($.unlockTime[msg.sender] > block.timestamp) {
            revert NotUnlocked();
        }

        amount = $.staked[msg.sender];
        $.staked[msg.sender] = 0;
        $.cooled[msg.sender] += amount;
        $.unlockTime[msg.sender] = 0;
        $.cooldownEnd[msg.sender] = block.timestamp + $.cooldownInterval;

        // Clear the detailed stake info for the user.
        delete $.stakeInfo[msg.sender];

        emit Unstaked(msg.sender, amount);
    }

    /**
     * @notice Unpark $PLUME from the contract
     * @param amount Amount of $PLUME to unpark
     */
   function unpark(uint256 amount) external nonReentrant {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        if ($.cooled[msg.sender] > 0 && $.cooldownEnd[msg.sender] >= block.timestamp) {
            $.parked[msg.sender] += $.cooled[msg.sender];
            $.cooled[msg.sender] = 0;
        }

        if (amount > $.parked[msg.sender]) {
            revert InsufficientBalance(amount, $.parked[msg.sender]);
        }
        $.parked[msg.sender] -= amount;
        SafeERC20.safeTransfer($.plume, msg.sender, amount);
        emit Unparked(msg.sender, amount);
    }

    /**
     * @notice Claim $PLUME
     * @param amount Amount of $PLUME to claim
     */
    function claimPlume(uint256 amount) external {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        $.claimablePlume[msg.sender] = claimablePlumeBalance(msg.sender);
        if (amount > $.claimablePlume[msg.sender]) {
            revert InsufficientBalance(amount, $.claimablePlume[msg.sender]);
        }

        $.claimablePlume[msg.sender] -= amount;
        SafeERC20.safeTransfer($.plume, msg.sender, amount);

        emit ClaimedPlume(msg.sender, amount);
    }

    /**
     * @notice Claim $pUSD
     * @param amount Amount of $pUSD to claim
     */
    function claimStable(uint256 amount) external {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        $.claimableStable[msg.sender] = claimableStableBalance(msg.sender);
        if (amount > $.claimableStable[msg.sender]) {
            revert InsufficientBalance(amount, $.claimableStable[msg.sender]);
        }

        $.claimableStable[msg.sender] -= amount;
        SafeERC20.safeTransfer($.pUSD, msg.sender, amount);

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

    /**
     * @notice Amount of $PLUME staked by a user
     * @param user Address of the user
     * @return amount Amount of $PLUME staked by the user
     */
    function staked(address user) external view returns (uint256) {
        return _getPlumeStakingStorage().staked[user];
    }

    /**
     * @notice Amount of $PLUME parked by a user
     * @param user Address of the user
     * @return amount Amount of $PLUME parked by the user
     */
    function parked(address user) external view returns (uint256) {
        return _getPlumeStakingStorage().parked[user];
    }

    /**
     * @notice Amount of $PLUME awaiting cooldown by a user
     * @param user Address of the user
     * @return amount Amount of $PLUME awaiting cooldown by the user
     */
    function cooled(address user) external view returns (uint256) {
        return _getPlumeStakingStorage().cooled[user];
    }

    /**
     * @notice Timestamp at which the assets at stake unlock for a user
     * @param user Address of the user
     * @return timestamp Timestamp at which the assets at stake unlock
     */
    function unlockTime(address user) external view returns (uint256) {
        return _getPlumeStakingStorage().unlockTime[user];
    }

    /**
     * @notice Timestamp at which the cooldown period ends when the user is unstaking
     * @param user Address of the user
     * @return timestamp Timestamp at which the cooldown period ends
     */
    function cooldownEnd(address user) external view returns (uint256) {
        return _getPlumeStakingStorage().cooldownEnd[user];
    }

    /**
     * @notice Withdrawable balance of a user
     * @param user Address of the user
     * @return amount Amount of $PLUME available to unpark
     */
    function withdrawableBalance(address user) external view returns (uint256 amount) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        amount = $.parked[user];
        if ($.cooled[user] > 0 && $.cooldownEnd[user] >= block.timestamp) {
            amount += $.cooled[user];
        }
    }

    /**
     * @notice Claimable $PLUME balance of a user
     * @param user Address of the user
     * @return amount Amount of $PLUME available to claim
     */
    function claimablePlumeBalance(address user)
        public
        view
        returns (uint256 amount)
    {
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
     function claimableStableBalance(address user)
        public
        view
        returns (uint256 amount)
    {
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
    function getStakeInfo(address user)
        external
        view
        returns (StakeInfo memory info)
    {
        return _getPlumeStakingStorage().stakeInfo[user];
    }
}
