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
        /// @dev Maximum reward rate that can be set (scaled by _BASE)
        //uint256 maxRewardRate;
        /// @dev Mapping from reward token address to its maximum reward rate (scaled by _BASE)
        mapping(address => uint256) maxRewardRates;
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

    /**
     * @notice Emitted when the maximum reward rate is updated
     * @param newMaxRewardRate The new maximum reward rate
     */
    event MaxRewardRateUpdated(uint256 newMaxRewardRate);

    /**
     * @notice Emitted when admin withdraws tokens from the contract
     * @param token Address of the token withdrawn
     * @param amount Amount of tokens withdrawn
     * @param recipient Address that received the tokens
     */
    event AdminWithdraw(address indexed token, uint256 amount, address indexed recipient);

    /**
     * @notice Emitted when the maximum reward rate for a token is updated
     * @param token The token whose max rate was updated
     * @param newMaxRate The new maximum reward rate
     */
    event MaxRewardRateUpdated(address indexed token, uint256 newMaxRate);

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

    /**
     * @notice Thrown when trying to perform an operation that requires an active stake, but user has none
     */
    error NoActiveStake();

    /**
     * @notice Thrown when a zero address is provided for a parameter that requires a valid address
     * @param parameter The name of the parameter that was zero
     */
    error ZeroAddress(string parameter);

    /**
     * @notice Thrown when attempting to add a token that is already in the rewards list
     * @param token The address of the token that already exists
     */
    error TokenAlreadyExists(address token);

    /**
     * @notice Thrown when attempting to interact with a token that is not in the rewards list
     * @param token The address of the non-existent reward token
     */
    error TokenDoesNotExist(address token);

    /**
     * @notice Thrown when attempting to set a reward rate higher than the maximum allowed
     * @param rate The proposed reward rate
     * @param maxRate The maximum allowed reward rate
     */
    error RewardRateExceedsMax(uint256 rate, uint256 maxRate);

    /**
     * @notice Emitted when a new token is added to the rewards list
     * @param token The address of the newly added reward token
     */
    event RewardTokenAdded(address indexed token);

    /**
     * @notice Emitted when a token is removed from the rewards list
     * @param token The address of the removed reward token
     */
    event RewardTokenRemoved(address indexed token);

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
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        StakeInfo storage info = $.stakeInfo[user];
        if (info.lastUpdateTimestamp == 0) {
            info.lastUpdateTimestamp = block.timestamp;
            return;
        }
        uint256 delta = block.timestamp - info.lastUpdateTimestamp;
        if (delta > 0 && info.staked > 0) {
            for (uint256 i = 0; i < $.rewardTokens.length; i++) {
                address token = $.rewardTokens[i];
                uint256 rate = $.rewardRates[token];
                $.rewardAccrued[user][token] += (info.staked * delta * rate) / _BASE;
            }
            info.lastUpdateTimestamp = block.timestamp;
        }
    }

    // Admin Functions

    /**
     * @notice Adds a new token to the list of reward tokens
     * @dev Only callable by admin role
     * @param token The address of the token to add as a reward
     * @custom:reverts ZeroAddress if token address is zero
     * @custom:reverts TokenAlreadyExists if token is already in rewards list
     */
    function addRewardToken(
        address token
    ) external onlyRole(ADMIN_ROLE) {
        if (token == address(0)) {
            revert ZeroAddress("token");
        }
        if (_rewardTokenExists(token)) {
            revert TokenAlreadyExists(token);
        }
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        $.rewardTokens.push(token);
        emit RewardTokenAdded(token);
    }

    /**
     * @notice Removes a token from the list of reward tokens
     * @dev Only callable by admin role. Sets reward rate to 0 and removes token from list.
     * @param token The address of the token to remove from rewards
     * @custom:reverts TokenDoesNotExist if token is not in rewards list
     */
    function removeRewardToken(
        address token
    ) external onlyRole(ADMIN_ROLE) {
        if (!_rewardTokenExists(token)) {
            revert TokenDoesNotExist(token);
        }
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        for (uint256 i = 0; i < $.rewardTokens.length; i++) {
            if ($.rewardTokens[i] == token) {
                $.rewardTokens[i] = $.rewardTokens[$.rewardTokens.length - 1];
                $.rewardTokens.pop();
                $.rewardRates[token] = 0;
                emit RewardTokenRemoved(token);
                break;
            }
        }
    }

    /**
     * @notice Check if a token exists in the reward tokens array
     * @param token Address of the token to check
     * @return bool True if the token exists in the reward tokens array
     */
    function _rewardTokenExists(
        address token
    ) internal view returns (bool) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        for (uint256 i = 0; i < $.rewardTokens.length; i++) {
            if ($.rewardTokens[i] == token) {
                return true;
            }
        }
        return false;
    }

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
        if (!_rewardTokenExists(token)) {
            revert TokenDoesNotExist(token);
        }
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        uint256 maxRate = $.maxRewardRates[token];
        if (maxRate == 0) {
            maxRate = 1e20; // Default max rate if not set
        }
        if (rewardRate_ > maxRate) {
            revert RewardRateExceedsMax(rewardRate_, maxRate);
        }
        $.rewardRates[token] = rewardRate_;
        emit SetRewardRate(token, rewardRate_);
    }

    /**
     * @notice Set the maximum reward rate for a specific token
     * @param token The token to set the max rate for
     * @param newMaxRate The new maximum reward rate
     */
    function setMaxRewardRate(address token, uint256 newMaxRate) external onlyRole(ADMIN_ROLE) nonReentrant {
        if (!_rewardTokenExists(token)) {
            revert TokenDoesNotExist(token);
        }
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        $.maxRewardRates[token] = newMaxRate;
        emit MaxRewardRateUpdated(token, newMaxRate);
    }

    /**
     * @notice Get the maximum reward rate for a specific token
     * @param token The token to get the max rate for
     * @return The maximum reward rate for the token
     */
    function getMaxRewardRate(
        address token
    ) external view returns (uint256) {
        return _getPlumeStakingStorage().maxRewardRates[token];
    }

    // Modify the setRewardRate function to use token-specific max rate

    /**
     * @notice Allows admin to withdraw any token from the contract
     * @param token Address of the token to withdraw
     * @param amount Amount of tokens to withdraw
     * @param recipient Address to receive the tokens
     */
    function adminWithdraw(
        address token,
        uint256 amount,
        address recipient
    ) external onlyRole(ADMIN_ROLE) nonReentrant {
        if (token == address(0)) {
            revert ZeroAddress("token");
        }
        if (recipient == address(0)) {
            revert ZeroAddress("recipient");
        }
        if (amount == 0) {
            revert InvalidAmount(0, 1);
        }

        if (token == address(_getPlumeStakingStorage().plume)) {
            // For PLUME, ensure we don't withdraw staked or cooling tokens
            uint256 totalLocked = this.totalAmountStaked() + this.totalAmountCooling();
            uint256 balance = IERC20(token).balanceOf(address(this));
            require(balance - amount >= totalLocked, "Cannot withdraw staked/cooling tokens");
        }

        IERC20(token).safeTransfer(recipient, amount);
        emit AdminWithdraw(token, amount, recipient);
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
    function restake(
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
    function stake(
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
    function withdraw(
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

    /**
     * @notice Returns the list of reward token addresses and their reward rates.
     * @return tokens An array of reward token addresses.
     * @return rates An array of reward rates corresponding to each token.
     */
    function getRewardTokens() external view returns (address[] memory tokens, uint256[] memory rates) {
        PlumeStakingStorage storage s = _getPlumeStakingStorage();
        uint256 length = s.rewardTokens.length;
        tokens = new address[](length);
        rates = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            tokens[i] = s.rewardTokens[i];
            rates[i] = s.rewardRates[s.rewardTokens[i]];
        }
    }

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

    /**
     * @notice Returns the timestamp when the cooldown period ends for the caller
     * @return timestamp The Unix timestamp when the cooldown ends (0 if no active cooldown)
     */
    function cooldownEndDate() external view returns (uint256) {
        return _getPlumeStakingStorage().stakeInfo[msg.sender].cooldownEnd;
    }

    /**
     * @notice Returns the timestamp when the cooldown period ends for a specific user
     * @param user The address of the user to check
     * @return timestamp The Unix timestamp when the cooldown ends (0 if no active cooldown)
     */
    function cooldownEndDateOf(
        address user
    ) external view returns (uint256) {
        return _getPlumeStakingStorage().stakeInfo[user].cooldownEnd;
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
        if (info.cooled > 0 && info.cooldownEnd <= block.timestamp) {
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

    // TODO: Refactor these functions
    // Simplest implementation

    /**
     * @notice Returns the claimable amount for a specific token for the caller
     * @param token Address of the reward token
     * @return amount Claimable reward amount for the caller
     */
    function amountClaimable(
        address token
    ) external view returns (uint256 amount) {
        return this.getClaimableReward(msg.sender, token);
    }

    /**
     * @notice Returns the total claimable amount across all users for a specific token
     * @param token Address of the reward token
     * @return total Total claimable reward amount across all users
     */
    function totalAmountClaimable(
        address token
    ) external view returns (uint256 total) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        // Get all users who have ever staked
        address[] memory users = _getStakers();

        // Sum up claimable amounts for all users
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            StakeInfo storage info = $.stakeInfo[user];

            // Add accrued rewards
            total += $.rewardAccrued[user][token];

            // Add pending rewards
            if (info.staked > 0 && block.timestamp > info.lastUpdateTimestamp) {
                total += (info.staked * (block.timestamp - info.lastUpdateTimestamp) * $.rewardRates[token]) / _BASE;
            }
        }
    }

    /**
     * @dev Internal helper to get list of all stakers
     * @return users Array of addresses that have staked
     */
    function _getStakers() internal view returns (address[] memory) {
        // Note: This is a simplified implementation.
        // In production, you would want to maintain a list of stakers
        // or use an enumerable set to track them efficiently.
        return _getPlumeStakingStorage().rewardTokens;
    }

    /**
     * @notice Returns the amount of PLUME currently in cooling period for the caller
     * @return amount Amount of PLUME in cooling period
     */
    function amountCooling() external view returns (uint256 amount) {
        return _getPlumeStakingStorage().stakeInfo[msg.sender].cooled;
    }

    /**
     * @notice Returns the total amount of PLUME in cooling period across all users
     * @return total Total amount of PLUME in cooling period
     */
    function totalAmountCooling() external view returns (uint256 total) {
        address[] memory users = _getStakers();
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();

        for (uint256 i = 0; i < users.length; i++) {
            total += $.stakeInfo[users[i]].cooled;
        }
    }

    /**
     * @notice Returns the amount of PLUME that is withdrawable for the caller
     * @return amount Amount of PLUME available to withdraw
     */
    function amountWithdrawable() external view returns (uint256 amount) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        StakeInfo storage info = $.stakeInfo[msg.sender];

        amount = info.parked;
        if (info.cooled > 0 && info.cooldownEnd <= block.timestamp) {
            amount += info.cooled;
        }
    }

    /**
     * @notice Returns the total amount of PLUME that is withdrawable across all users
     * @return total Total amount of PLUME available to withdraw
     */
    function totalAmountWithdrawable() external view returns (uint256 total) {
        address[] memory users = _getStakers();
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();

        for (uint256 i = 0; i < users.length; i++) {
            StakeInfo storage info = $.stakeInfo[users[i]];
            total += info.parked;
            if (info.cooled > 0 && info.cooldownEnd <= block.timestamp) {
                total += info.cooled;
            }
        }
    }

    /**
     * @notice Returns the amount of PLUME currently staked by the caller
     * @return amount Amount of PLUME staked
     */
    function amountStaked() external view returns (uint256 amount) {
        return _getPlumeStakingStorage().stakeInfo[msg.sender].staked;
    }

    /**
     * @notice Returns the total amount of PLUME staked across all users
     * @return total Total amount of PLUME staked
     */
    function totalAmountStaked() external view returns (uint256 total) {
        address[] memory users = _getStakers();
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();

        for (uint256 i = 0; i < users.length; i++) {
            total += $.stakeInfo[users[i]].staked;
        }
    }

}
