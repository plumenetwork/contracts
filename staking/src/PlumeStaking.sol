// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Import OpenZeppelin upgradeable modules.
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol"; 
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol"; 
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol"; 
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol"; 
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol"; 
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

/* ======================================================================
   CONSTANTS & STRUCTS
   ====================================================================== */

// Maximum lock duration is defined as 4 years.
uint256 constant MAX_LOCK_DURATION = 4 * 365 days; 

/**
 * @dev The following struct is used to “package” all state variables.
 * The custom storage tag ensures that the layout is fixed between upgrades.
 *
 * @custom:storage-location erc7201:plume.storage.PlumeStaking
 */
struct PlumeStakingStorage {
    // Token references.
    IERC20Upgradeable plumeToken;
    IERC20Upgradeable pUSDToken;
    // Global staking parameters.
    uint256 totalStaked;
    uint256 coolDownPeriod;
    uint256 minStakeAmount;
    uint256 withdrawalPenaltyRate; // in basis points (e.g. 500 means 5%)
    address feeRecipient;
    // Allowed lockup options. (Each option defines a lock duration and its APY in basis points.)
    LockupOption[] lockupOptions;
    // Mapping from user address to their staking data.
    mapping(address => UserInfo) userInfo;
}

/**
 * @dev Use a fixed storage slot so that upgrades do not affect the layout.
 * (The constant below is arbitrarily chosen but must be unique for your project.)
 */
bytes32 private constant PLUME_STAKING_STORAGE_LOCATION =
    0xa6cbc7710058576a270f67161d5bf15d0a5b41a0e20b4574e4fb07768a4d0c01;

/**
 * @dev Returns a pointer to the storage struct.
 */
function _getPlumeStakingStorage() private pure returns (PlumeStakingStorage storage s) {
    assembly {
        s.slot := PLUME_STAKING_STORAGE_LOCATION
    }
}

/**
 * @dev Each allowed lockup option defines a duration (in seconds) and an APY (in basis points).
 * For example, one option might be 180 days with an APY of 300 (i.e. 3% per year).
 */
struct LockupOption {
    uint256 duration; // in seconds
    uint256 apy;      // in basis points (e.g., 300 means 3% APY)
}

/**
 * @dev A user’s active stake.
 */
struct Stake {
    uint256 amount;
    uint256 startTime;
    uint256 lockDuration;
    uint256 rewardRate;     // computed from the chosen option’s APY (scaled by 1e18)
    uint256 lastRewardClaim;
}

/**
 * @dev Represents a pending (requested) withdrawal.
 */
struct PendingWithdrawal {
    uint256 amount;
    uint256 penalty;
    uint256 readyTime;
}

/**
 * @dev Data for each user.
 */
struct UserInfo {
    uint256 parked;              // tokens “parked” (withdrawable, not earning rewards)
    Stake activeStake;           // current active (locked) stake (if any)
    bool hasActiveStake;
    PendingWithdrawal pendingWithdrawal; // if an unstake request is in progress
    bool hasPendingWithdrawal;
    uint256 rewardAccumulated;   // rewards accrued (in 1e18 fixed–point units)
    // For auto‑compounding, the user chooses a compounding period (in seconds).
    // If autoCompoundPeriod == 0 then auto‑compounding is disabled.
    uint256 autoCompoundPeriod;
}

/* ======================================================================
   CONTRACT
   ====================================================================== */
contract PlumeStaking is Initializable, UUPSUpgradeable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* ===== EVENTS ===== */
    event Parked(address indexed user, uint256 amount);
    event WithdrawnParked(address indexed user, uint256 amount);
    event Staked(address indexed user, uint256 amount, uint256 lockDuration, uint256 autoCompoundPeriod);
    event ExtendedTime(address indexed user, uint256 newLockDuration);
    event ExtendedAmount(address indexed user, uint256 amountAdded);
    event UnstakeRequested(address indexed user, uint256 amount, uint256 penalty, uint256 readyTime);
    event Unstaked(address indexed user, uint256 netAmount, uint256 penalty);
    event RewardsClaimed(address indexed user, uint256 reward, string rewardToken);
    event RewardsCompounded(address indexed user, uint256 compoundedAmount);
    event StakeMaturedReleased(address indexed user, uint256 amountReleased);
    event AutoCompoundPeriodSet(address indexed user, uint256 autoCompoundPeriod);

    /* ===== INITIALIZER ===== */
    function initialize(address _plumeToken, address _pUSDToken) public initializer {
        __UUPSUpgradeable_init();
        __OwnableUpgradeable_init();
        __PausableUpgradeable_init();
        __ReentrancyGuardUpgradeable_init();

        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        s.plumeToken = IERC20Upgradeable(_plumeToken);
        s.pUSDToken = IERC20Upgradeable(_pUSDToken);
        s.coolDownPeriod = 7 days;
        s.minStakeAmount = 1 * 1e18; // example minimum
        s.withdrawalPenaltyRate = 500; // 5% penalty by default
        s.feeRecipient = address(0);

        // Set up default lockup options.
        // For example:
        // • 90 days: 2% APY
        // • 180 days: 3% APY
        // • 270 days: 4% APY
        // • 365 days: 5% APY
        // • MAX_LOCK_DURATION (4 years): 9% APY (for auto‑extend)
        s.lockupOptions.push(LockupOption({duration: 90 days, apy: 200}));
        s.lockupOptions.push(LockupOption({duration: 180 days, apy: 300}));
        s.lockupOptions.push(LockupOption({duration: 270 days, apy: 400}));
        s.lockupOptions.push(LockupOption({duration: 365 days, apy: 500}));
        s.lockupOptions.push(LockupOption({duration: MAX_LOCK_DURATION, apy: 900}));
    }

    // UUPS upgrade authorization.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /* ===== INTERNAL HELPERS ===== */

    /**
     * @dev Computes the per–second reward rate (scaled by 1e18) from an APY expressed in basis points.
     * For example, if apyBasisPoints == 300 (3%), then:
     *   rewardRate = (300 * 1e18) / (10000 * 31536000)
     */
    function _computeRewardRate(uint256 apyBasisPoints) internal pure returns (uint256) {
        return (apyBasisPoints * 1e18) / (10000 * 31536000);
    }

    /**
     * @dev Returns the LockupOption corresponding to a given duration.
     * Reverts if no matching option is found.
     */
    function _getLockupOption(uint256 duration) internal view returns (LockupOption memory option) {
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        for (uint256 i = 0; i < s.lockupOptions.length; i++) {
            if (s.lockupOptions[i].duration == duration) {
                return s.lockupOptions[i];
            }
        }
        revert("Lockup duration not allowed");
    }

    /**
     * @dev Returns the maximum lockup option (which should correspond to MAX_LOCK_DURATION).
     */
    function _getMaxLockupOption() internal view returns (LockupOption memory option) {
        return _getLockupOption(MAX_LOCK_DURATION);
    }

    /**
     * @dev Updates the rewards for a given user.
     *
     * - If auto‑compounding is enabled (i.e. autoCompoundPeriod > 0) and at least that much time has passed
     *   since the last reward claim, the rewards are immediately added to the staked amount.
     * - Otherwise, rewards accumulate in rewardAccumulated.
     *
     * Also, if the stake’s lock period has expired (and is not the auto‑extend option), the stake is released.
     */
    function _updateReward(address _user) internal {
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        UserInfo storage user = s.userInfo[_user];
        if (user.hasActiveStake && user.activeStake.amount > 0) {
            uint256 maturity = user.activeStake.startTime + user.activeStake.lockDuration;
            if (block.timestamp >= maturity && user.activeStake.lockDuration < MAX_LOCK_DURATION) {
                _releaseIfMatured(_user);
                return;
            }
            uint256 elapsed = block.timestamp - user.activeStake.lastRewardClaim;
            if (elapsed > 0) {
                uint256 reward = (user.activeStake.amount * elapsed * user.activeStake.rewardRate) / 1e18;
                if (user.autoCompoundPeriod > 0 && elapsed >= user.autoCompoundPeriod) {
                    // Auto‑compound: add rewards directly into the stake.
                    user.activeStake.amount += reward;
                    s.totalStaked += reward;
                    emit RewardsCompounded(_user, reward);
                } else {
                    // Otherwise, accumulate rewards for later claiming or manual compounding.
                    user.rewardAccumulated += reward;
                }
                user.activeStake.lastRewardClaim = block.timestamp;
            }
        }
    }

    /**
     * @dev If an active stake has matured (its lock period expired) and was not auto‑extended,
     * it is “released” by moving the staked amount to the parked (withdrawable) balance.
     */
    function _releaseIfMatured(address _user) internal {
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        UserInfo storage user = s.userInfo[_user];
        if (user.hasActiveStake) {
            uint256 maturity = user.activeStake.startTime + user.activeStake.lockDuration;
            if (block.timestamp >= maturity && user.activeStake.lockDuration < MAX_LOCK_DURATION) {
                _updateReward(_user);
                uint256 amountToRelease = user.activeStake.amount;
                user.parked += amountToRelease;
                user.hasActiveStake = false;
                delete user.activeStake;
                emit StakeMaturedReleased(_user, amountToRelease);
            }
        }
    }

    /* ===== USER FUNCTIONS ===== */

    /**
     * @notice Deposit tokens to your “parked” balance.
     * Parked tokens are available for immediate withdrawal but do not earn rewards.
     */
    function park(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Cannot park 0");
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        s.plumeToken.safeTransferFrom(msg.sender, address(this), amount);
        s.userInfo[msg.sender].parked += amount;
        emit Parked(msg.sender, amount);
    }

    /**
     * @notice Withdraw tokens from your parked balance.
     */
    function withdrawParked(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be > 0");
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        UserInfo storage user = s.userInfo[msg.sender];
        require(user.parked >= amount, "Insufficient parked balance");
        user.parked -= amount;
        s.plumeToken.safeTransfer(msg.sender, amount);
        emit WithdrawnParked(msg.sender, amount);
    }

    /**
     * @notice Stake tokens directly from your wallet.
     *
     * @param lockDuration The desired lockup duration (in seconds). Must equal one of the allowed options—
     *        or pass 0 for auto‑extension (which uses the maximum lock, MAX_LOCK_DURATION).
     * @param amount The amount to stake (must be at least minStakeAmount).
     * @param autoCompoundPeriod The auto‑compounding period (in seconds). Must be either 0 (to disable auto‑compounding)
     *        or a multiple of 90 days (3 months) and not exceed the chosen lock duration.
     */
    function stake(uint256 lockDuration, uint256 amount, uint256 autoCompoundPeriod) external nonReentrant whenNotPaused {
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        require(amount >= s.minStakeAmount, "Amount below minimum");
        UserInfo storage user = s.userInfo[msg.sender];
        require(!user.hasActiveStake, "Active stake exists");

        uint256 effectiveLock;
        LockupOption memory option;
        if (lockDuration == 0) {
            effectiveLock = MAX_LOCK_DURATION;
            option = _getMaxLockupOption();
        } else {
            effectiveLock = lockDuration;
            option = _getLockupOption(lockDuration);
        }
        if (autoCompoundPeriod > 0) {
            require(autoCompoundPeriod % (90 days) == 0, "Auto-compound period must be multiple of 90 days");
            require(autoCompoundPeriod <= effectiveLock, "Auto-compound period must be <= lock duration");
        }
        s.plumeToken.safeTransferFrom(msg.sender, address(this), amount);
        user.activeStake = Stake({
            amount: amount,
            startTime: block.timestamp,
            lockDuration: effectiveLock,
            rewardRate: _computeRewardRate(option.apy),
            lastRewardClaim: block.timestamp
        });
        user.hasActiveStake = true;
        user.autoCompoundPeriod = autoCompoundPeriod;
        s.totalStaked += amount;
        emit Staked(msg.sender, amount, effectiveLock, autoCompoundPeriod);
    }

    /**
     * @notice If your active stake has matured (lock period ended) and was not auto‑extended,
     *         call this function to release your stake into your parked (withdrawable) balance.
     */
    function releaseMaturedStake() external nonReentrant whenNotPaused {
        _releaseIfMatured(msg.sender);
    }

    /**
     * @notice Extend (or re-lock) your active stake’s lockup period.
     *
     * @param newLockDuration The new desired lock duration (in seconds). Must be one of the allowed options
     *        or 0 for auto‑extension.
     */
    function extendTime(uint256 newLockDuration) external nonReentrant whenNotPaused {
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        UserInfo storage user = s.userInfo[msg.sender];
        require(user.hasActiveStake, "No active stake");
        _updateReward(msg.sender);
        uint256 currentMaturity = user.activeStake.startTime + user.activeStake.lockDuration;
        uint256 remaining = currentMaturity > block.timestamp ? currentMaturity - block.timestamp : 0;
        uint256 effectiveNewLock;
        LockupOption memory option;
        if (newLockDuration == 0) {
            effectiveNewLock = MAX_LOCK_DURATION;
            option = _getMaxLockupOption();
        } else {
            effectiveNewLock = newLockDuration;
            option = _getLockupOption(newLockDuration);
        }
        require(effectiveNewLock >= remaining, "New lock must be >= remaining time");
        require(effectiveNewLock <= MAX_LOCK_DURATION, "Lock duration too long");
        user.activeStake.startTime = block.timestamp;
        user.activeStake.lockDuration = effectiveNewLock;
        user.activeStake.lastRewardClaim = block.timestamp;
        user.activeStake.rewardRate = _computeRewardRate(option.apy);
        emit ExtendedTime(msg.sender, effectiveNewLock);
    }

    /**
     * @notice Add more tokens (from your parked balance) into your active stake.
     */
    function extendAmount(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be > 0");
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        UserInfo storage user = s.userInfo[msg.sender];
        require(user.hasActiveStake, "No active stake");
        require(user.parked >= amount, "Insufficient parked balance");
        _updateReward(msg.sender);
        user.parked -= amount;
        user.activeStake.amount += amount;
        s.totalStaked += amount;
        emit ExtendedAmount(msg.sender, amount);
    }

    /**
     * @notice Request to unstake part of your active stake.
     *         This begins a two-transaction process: first a request (which incurs a cool-down and penalty),
     *         then the eventual withdrawal.
     *
     * @param amount The amount to unstake.
     */
    function requestUnstake(uint256 amount) external nonReentrant whenNotPaused {
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        UserInfo storage user = s.userInfo[msg.sender];
        require(user.hasActiveStake, "No active stake");
        require(!user.hasPendingWithdrawal, "Pending withdrawal exists");
        require(amount > 0 && amount <= user.activeStake.amount, "Invalid amount");
        _updateReward(msg.sender);
        uint256 maturity = user.activeStake.startTime + user.activeStake.lockDuration;
        uint256 remaining = maturity > block.timestamp ? maturity - block.timestamp : 0;
        uint256 penalty = 0;
        if (remaining > 0) {
            penalty = (amount * s.withdrawalPenaltyRate * remaining) / (user.activeStake.lockDuration * 10000);
        }
        user.activeStake.amount -= amount;
        s.totalStaked -= amount;
        if (user.activeStake.amount == 0) {
            user.hasActiveStake = false;
            delete user.activeStake;
        }
        user.pendingWithdrawal = PendingWithdrawal({
            amount: amount,
            penalty: penalty,
            readyTime: block.timestamp + s.coolDownPeriod
        });
        user.hasPendingWithdrawal = true;
        emit UnstakeRequested(msg.sender, amount, penalty, user.pendingWithdrawal.readyTime);
    }

    /**
     * @notice After the cool-down period has elapsed, execute your unstake request.
     * Transfers the net amount (after penalty) to your wallet.
     */
    function unstake() external nonReentrant whenNotPaused {
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        UserInfo storage user = s.userInfo[msg.sender];
        require(user.hasPendingWithdrawal, "No pending withdrawal");
        require(block.timestamp >= user.pendingWithdrawal.readyTime, "Cooldown period not over");
        uint256 gross = user.pendingWithdrawal.amount;
        uint256 penaltyAmount = user.pendingWithdrawal.penalty;
        uint256 netAmount = gross > penaltyAmount ? gross - penaltyAmount : 0;
        delete user.pendingWithdrawal;
        user.hasPendingWithdrawal = false;
        s.plumeToken.safeTransfer(msg.sender, netAmount);
        if (s.feeRecipient != address(0) && penaltyAmount > 0) {
            s.plumeToken.safeTransfer(s.feeRecipient, penaltyAmount);
        }
        emit Unstaked(msg.sender, netAmount, penaltyAmount);
    }

    /**
     * @notice Claim your accumulated rewards.
     *
     * Rewards are paid first in pUSD. If there isn’t enough pUSD available, the remainder is paid in PLUME.
     * This function only applies when auto‑compounding is disabled.
     */
    function claimRewards() external nonReentrant whenNotPaused {
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        UserInfo storage user = s.userInfo[msg.sender];
        require(user.autoCompoundPeriod == 0, "Auto-compound enabled; cannot claim rewards");
        _updateReward(msg.sender);
        uint256 reward = user.rewardAccumulated;
        require(reward > 0, "No rewards to claim");
        user.rewardAccumulated = 0;
        uint256 pUSDPool = s.pUSDToken.balanceOf(address(this));
        if (pUSDPool >= reward) {
            s.pUSDToken.safeTransfer(msg.sender, reward);
            emit RewardsClaimed(msg.sender, reward, "pUSD");
        } else {
            uint256 pUSDPortion = pUSDPool;
            uint256 remaining = reward - pUSDPortion;
            if (pUSDPortion > 0) {
                s.pUSDToken.safeTransfer(msg.sender, pUSDPortion);
            }
            uint256 availablePlume = s.plumeToken.balanceOf(address(this)) > s.totalStaked
                ? s.plumeToken.balanceOf(address(this)) - s.totalStaked
                : 0;
            require(availablePlume >= remaining, "Insufficient reward funds");
            s.plumeToken.safeTransfer(msg.sender, remaining);
            emit RewardsClaimed(msg.sender, reward, "Mixed (pUSD+PLUME)");
        }
    }

    /**
     * @notice Manually compound your accumulated rewards into your active stake.
     * Only applicable when auto‑compounding is disabled.
     */
    function compoundRewards() external nonReentrant whenNotPaused {
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        UserInfo storage user = s.userInfo[msg.sender];
        require(user.hasActiveStake, "No active stake");
        require(user.autoCompoundPeriod == 0, "Already auto-compounding");
        _updateReward(msg.sender);
        uint256 reward = user.rewardAccumulated;
        require(reward > 0, "No rewards to compound");
        user.rewardAccumulated = 0;
        user.activeStake.amount += reward;
        s.totalStaked += reward;
        emit RewardsCompounded(msg.sender, reward);
    }

    /**
     * @notice Set (or change) the auto‑compounding period for your active stake.
     *
     * @param autoCompoundPeriod The new auto‑compound period in seconds. Must be either 0 (to disable)
     *        or a multiple of 90 days (3 months) and not exceed your current lock duration.
     */
    function setAutoCompoundPeriod(uint256 autoCompoundPeriod) external nonReentrant whenNotPaused {
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        UserInfo storage user = s.userInfo[msg.sender];
        require(user.hasActiveStake, "No active stake");
        if (autoCompoundPeriod > 0) {
            require(autoCompoundPeriod % (90 days) == 0, "Auto-compound period must be multiple of 90 days");
            require(autoCompoundPeriod <= user.activeStake.lockDuration, "Auto-compound period must be <= lock duration");
        }
        _updateReward(msg.sender);
        user.autoCompoundPeriod = autoCompoundPeriod;
        emit AutoCompoundPeriodSet(msg.sender, autoCompoundPeriod);
    }

    /* ===== OWNER / ADMIN FUNCTIONS ===== */

    function setCoolDownPeriod(uint256 _coolDownPeriod) external onlyOwner {
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        s.coolDownPeriod = _coolDownPeriod;
    }

    function setMinStakeAmount(uint256 _minStakeAmount) external onlyOwner {
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        s.minStakeAmount = _minStakeAmount;
    }

    function setWithdrawalPenaltyRate(uint256 _withdrawalPenaltyRate) external onlyOwner {
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        s.withdrawalPenaltyRate = _withdrawalPenaltyRate;
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        s.feeRecipient = _feeRecipient;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
