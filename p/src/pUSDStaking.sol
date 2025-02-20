// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { Plume } from "./Plume.sol";
import { console2 } from "forge-std/console2.sol";
/**
 * @title PlumeStaking
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Staking contract for $PLUME
 */

contract pUSDStaking is Initializable, AccessControlUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {

    using SafeERC20 for Plume;
    using SafeERC20 for IERC20;

    // Storage

    /// @dev Source of stake
    enum StakeSource {
        WALLET, // Direct stake from wallet
        PARKED, // Stake from parked balance
        COOLING, // Stake from cooling balance
        CLAIM // Claim rewards and stake them

    }

    event DebugClaim(
        address token,
        uint256 amount,
        uint256 contractBalance,
        uint256 userAccruedReward,
        uint256 userStaked,
        uint256 lastUpdateTime
    );

    /// @custom:storage-location erc7201:plume.storage.PlumeStaking
    struct PlumeStakingStorage {
        /// @dev Address of the $PLUME token
        Plume plume;
        /// @dev Address of the $pUSD token
        IERC20 pUSD;
        /// @notice Array of all staker addresses
        address[] stakers;
        /// @dev Minimum amount of $PLUME that can be staked
        uint256 minStakeAmount;
        /// @dev Cooldown interval for unstaked assets to be unlocked and parked
        uint256 cooldownInterval;
        /// @dev List of reward tokens (ERC20) to be distributed as rewards
        address[] rewardTokens;
        /// @dev Total amount of PLUME currently staked
        uint256 totalStaked;
        /// @dev Total amount of PLUME in cooling period
        uint256 totalCooling;
        /// @dev Total amount of PLUME that's withdrawable (parked)
        uint256 totalWithdrawable;
        /// @dev Detailed active stake info for each user
        mapping(address user => StakeInfo info) stakeInfo;
        /// @dev Total claimable rewards per token
        mapping(address => uint256) totalClaimableByToken;
        /// @dev Mapping from reward token address to its per-second reward rate (scaled by _BASE)
        mapping(address => uint256) rewardRates;
        /// @dev Mapping from user to reward token to accumulated reward amount
        mapping(address => mapping(address => uint256)) rewardAccrued;
        /// @dev Mapping from reward token address to its maximum reward rate (scaled by _BASE)
        mapping(address => uint256) maxRewardRates;
        /// @notice Mapping to track if an address is already in stakers array
        mapping(address => bool) isStaker;
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.pUSDStaking")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PLUME_STAKING_STORAGE_LOCATION =
        0xda2caf89f03a29ad7273c0a945481ed190f879ad9205f9cad4997c75b7fee100;

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
     * @notice Emitted when a user stakes PLUME
     * @param user Address of the user that staked PLUME
     * @param amount Amount of PLUME staked
     * @param fromCooling Amount taken from cooling balance
     * @param fromParked Amount taken from parked balance
     * @param fromWallet Amount taken from wallet
     */
    event Staked(address indexed user, uint256 amount, uint256 fromCooling, uint256 fromParked, uint256 fromWallet);

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

    /**
     * @notice Emitted when a user withdraws $PLUME
     * @param user Address of the user that withdrew $PLUME
     * @param amount Amount of $PLUME withdrawn
     */
    event Withdrawn(address indexed user, uint256 amount);

    /**
     * @notice Emitted when admin manually adds a staker
     * @param staker Address of the staker that was added
     */
    event StakerAdded(address indexed staker);
    /**
     * @notice Emitted when total amounts are updated by admin
     * @param totalStaked New total staked amount
     * @param totalCooling New total cooling amount
     * @param totalWithdrawable New total withdrawable amount
     */
    event TotalAmountsUpdated(uint256 totalStaked, uint256 totalCooling, uint256 totalWithdrawable);

    /**
     * @notice Emitted when admin updates a user's stake info
     * @param user Address of the user
     * @param staked New staked amount
     * @param cooled New cooling amount
     * @param parked New parked amount
     * @param cooldownEnd New cooldown end timestamp
     * @param lastUpdateTimestamp New last update timestamp
     */
    event StakeInfoUpdated(
        address indexed user,
        uint256 staked,
        uint256 cooled,
        uint256 parked,
        uint256 cooldownEnd,
        uint256 lastUpdateTimestamp
    );

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
     * @notice Thrown when the length of tokens array does not match the length of rates array
     * @dev This error occurs in setRewardRates when tokens.length != rewardRates_.length
     */
    error ArrayLengthMismatch();

    /**
     * @notice Thrown when attempting to set reward rates with empty arrays
     * @dev This error occurs in setRewardRates when tokens.length == 0
     */
    error EmptyArray();

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
     * @notice Helper function to add a new staker if not already tracked
     * @param staker Address of the staker to add
     */
    function _addStakerIfNew(
        address staker
    ) internal {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        if (!$.isStaker[staker]) {
            $.stakers.push(staker);
            $.isStaker[staker] = true;
        }
    }

    /**
     * @notice Get the total number of stakers
     * @return count Number of unique stakers
     */
    function getStakerCount() external view returns (uint256) {
        return _getPlumeStakingStorage().stakers.length;
    }

    /**
     * @notice Get staker address at specific index
     * @param index Index in the stakers array
     * @return staker Address of the staker
     */
    function getStakerAtIndex(
        uint256 index
    ) external view returns (address) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        require(index < $.stakers.length, "Index out of bounds");
        return $.stakers[index];
    }

    /**
     * @notice Check if an address is a staker
     * @param account Address to check
     * @return bool True if the address is a staker
     */
    function isStaker(
        address account
    ) external view returns (bool) {
        return _getPlumeStakingStorage().isStaker[account];
    }

    /**
     * @notice Update the reward accumulated by the given user
     * @param user Address of the user
     */
    function _updateRewards(
        address user
    ) internal {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        StakeInfo storage info = $.stakeInfo[user];

        /*
        if (info.lastUpdateTimestamp == 0) {
            info.lastUpdateTimestamp = block.timestamp;
        }
        */
        uint256 delta = block.timestamp - info.lastUpdateTimestamp;
        if (delta > 0 && info.staked > 0) {
            for (uint256 i = 0; i < $.rewardTokens.length; i++) {
                address token = $.rewardTokens[i];
                uint256 rate = $.rewardRates[token];

                uint256 newRewards = (info.staked * delta * rate) / _BASE;
                $.rewardAccrued[user][token] += newRewards;
                $.totalClaimableByToken[token] += newRewards;
            }
            info.lastUpdateTimestamp = block.timestamp;
        }
    }

    // Admin Functions

    /**
     * @notice Admin function to set a user's stake info
     * @param user Address of the user
     * @param staked Amount staked
     * @param cooled Amount in cooling
     * @param parked Amount parked (withdrawable)
     * @param cooldownEnd Timestamp when cooldown ends
     * @param lastUpdateTimestamp Last reward update timestamp
     */
    function setStakeInfo(
        address user,
        uint256 staked,
        uint256 cooled,
        uint256 parked,
        uint256 cooldownEnd,
        uint256 lastUpdateTimestamp
    ) external onlyRole(ADMIN_ROLE) nonReentrant {
        if (user == address(0)) {
            revert ZeroAddress("user");
        }

        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        StakeInfo storage info = $.stakeInfo[user];

        info.staked = staked;
        info.cooled = cooled;
        info.parked = parked;
        info.cooldownEnd = cooldownEnd;
        info.lastUpdateTimestamp = lastUpdateTimestamp;

        // Add user to stakers list if they have any funds
        if (staked > 0 || cooled > 0 || parked > 0) {
            _addStakerIfNew(user);
        }

        emit StakeInfoUpdated(user, staked, cooled, parked, cooldownEnd, lastUpdateTimestamp);
    }

    /**
     * @notice Admin function to manually add a staker to tracking
     * @param staker Address of the staker to add
     * @dev Will revert if address is zero or already a staker
     */
    function addStaker(
        address staker
    ) external onlyRole(ADMIN_ROLE) nonReentrant {
        if (staker == address(0)) {
            revert ZeroAddress("staker");
        }

        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        if ($.isStaker[staker]) {
            revert("Already a staker");
        }

        $.stakers.push(staker);
        $.isStaker[staker] = true;

        emit StakerAdded(staker);
    }

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
     * @notice Set reward rates for one or multiple tokens
     * @param tokens Array of reward token addresses
     * @param rewardRates_ Array of reward rates for corresponding tokens
     * @dev Arrays must be the same length
     */
    function setRewardRates(
        address[] calldata tokens,
        uint256[] calldata rewardRates_
    ) external onlyRole(ADMIN_ROLE) nonReentrant {
        if (tokens.length != rewardRates_.length) {
            revert ArrayLengthMismatch();
        }
        if (tokens.length == 0) {
            revert EmptyArray();
        }

        PlumeStakingStorage storage $ = _getPlumeStakingStorage();

        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 rate = rewardRates_[i];

            if (!_rewardTokenExists(token)) {
                revert TokenDoesNotExist(token);
            }

            uint256 maxRate = $.maxRewardRates[token];
            if (maxRate == 0) {
                maxRate = 1e20; // Default max rate if not set
            }
            if (rate > maxRate) {
                revert RewardRateExceedsMax(rate, maxRate);
            }

            $.rewardRates[token] = rate;
            emit SetRewardRate(token, rate);
        }
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
     * @notice Admin function to recalculate and update total amounts
     * @dev Updates totalStaked, totalCooling, totalWithdrawable, and individual cooling amounts
     */
    function updateTotalAmounts() external onlyRole(ADMIN_ROLE) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        uint256 newTotalStaked = 0;
        uint256 newTotalCooling = 0;
        uint256 newTotalWithdrawable = 0;

        // Iterate through all stakers and recalculate totals
        for (uint256 i = 0; i < $.stakers.length; i++) {
            address staker = $.stakers[i];
            StakeInfo storage info = $.stakeInfo[staker];

            // Add to staked total
            newTotalStaked += info.staked;

            // Check and update cooling amounts
            if (info.cooled > 0) {
                if (info.cooldownEnd != 0 && block.timestamp >= info.cooldownEnd) {
                    // Cooldown period has ended, move to parked
                    info.parked += info.cooled;
                    info.cooled = 0;
                    info.cooldownEnd = 0;
                } else {
                    // Still in cooling period
                    newTotalCooling += info.cooled;
                }
            }

            // Add to withdrawable total
            newTotalWithdrawable += info.parked;
        }

        // Update storage with new totals
        $.totalStaked = newTotalStaked;
        $.totalCooling = newTotalCooling;
        $.totalWithdrawable = newTotalWithdrawable;

        emit TotalAmountsUpdated(newTotalStaked, newTotalCooling, newTotalWithdrawable);
    }

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

    function stake(
        uint256 amount
    ) external nonReentrant {
        console2.log("Staking pUSD");
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        StakeInfo storage info = $.stakeInfo[msg.sender];

        if (amount < $.minStakeAmount) {
            revert InvalidAmount(amount, $.minStakeAmount);
        }

        _updateRewards(msg.sender);

        // Check if any cooling funds should be moved to parked
        if (info.cooled > 0 && info.cooldownEnd <= block.timestamp) {
            info.parked += info.cooled;
            $.totalWithdrawable += info.cooled;
            $.totalCooling -= info.cooled;
            info.cooled = 0;
            info.cooldownEnd = 0;
        }

        uint256 remainingToStake = amount;
        uint256 fromCooling;
        uint256 fromParked;
        uint256 fromWallet;

        // First: Use cooling tokens if available
        if (info.cooled > 0) {
            fromCooling = remainingToStake > info.cooled ? info.cooled : remainingToStake;
            info.cooled -= fromCooling;
            remainingToStake -= fromCooling;
        }

        // Second: Use parked (withdrawable) tokens if needed
        if (remainingToStake > 0 && info.parked > 0) {
            fromParked = remainingToStake > info.parked ? info.parked : remainingToStake;
            info.parked -= fromParked;
            remainingToStake -= fromParked;
        }

        // Last: Take remaining from wallet if needed
        if (remainingToStake > 0) {
            fromWallet = remainingToStake;
            $.pUSD.safeTransferFrom(msg.sender, address(this), fromWallet);
        }

        // Update total staked amount
        info.staked += amount;
        $.totalStaked += amount;
        $.totalCooling -= fromCooling;
        $.totalWithdrawable -= fromParked;

        _updateRewards(msg.sender);
        _addStakerIfNew(msg.sender);

        emit Staked(msg.sender, amount, fromCooling, fromParked, fromWallet);
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

        _updateRewards(msg.sender); // Capture rewards at current stake amount

        amount = info.staked;
        info.staked = 0;
        $.totalStaked -= amount;
        info.cooled += amount;
        $.totalCooling += amount; // Added this
        info.cooldownEnd = block.timestamp + $.cooldownInterval;

        _updateRewards(msg.sender); // Update rewards after stake amount changes

        emit Unstaked(msg.sender, amount);
        return amount;
    }

    /**
     * @notice Unpark $PLUME from the contract
     * @param amount Amount of $PLUME to unpark
     */
    function withdraw(
        uint256 amount
    ) external nonReentrant {
        if (amount == 0) {
            revert InvalidAmount(0, 1);
        }

        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        StakeInfo storage info = $.stakeInfo[msg.sender];

        _updateRewards(msg.sender);

        // If cooldown period has passed, move cooled funds to parked.
        if (info.cooled > 0 && info.cooldownEnd <= block.timestamp) {
            info.parked += info.cooled;
            $.totalWithdrawable += info.cooled;
            $.totalCooling -= info.cooled;
            info.cooled = 0;
            info.cooldownEnd = 0;
        }
        if (amount > info.parked) {
            revert InsufficientBalance(amount, info.parked);
        }

        info.parked -= amount;
        $.totalWithdrawable -= amount; // Update total withdrawable after deducting from parked
        _updateRewards(msg.sender);

        $.pUSD.safeTransfer(msg.sender, amount); // Changed from plume to pUSD
        emit Withdrawn(msg.sender, amount); // Renamed event
    }

    /// @notice Claim all $pUSD rewards from the contract
    function claim() external {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        StakeInfo storage info = $.stakeInfo[msg.sender];

        // Cache all amounts first using getClaimableReward
        uint256[] memory amounts = new uint256[]($.rewardTokens.length);
        uint256 nonZeroRewards = 0;

        for (uint256 i = 0; i < $.rewardTokens.length; i++) {
            address token = $.rewardTokens[i];
            amounts[i] = this.getClaimableReward(msg.sender, token);
            if (amounts[i] > 0) {
                nonZeroRewards++;
            }
        }

        if (nonZeroRewards > 0) {
            _updateRewards(msg.sender);

            // Reset all accrued rewards and transfer tokens
            for (uint256 i = 0; i < $.rewardTokens.length; i++) {
                if (amounts[i] > 0) {
                    address token = $.rewardTokens[i];

                    // Emit debug info before transfer
                    emit DebugClaim(
                        token,
                        amounts[i],
                        IERC20(token).balanceOf(address(this)),
                        $.rewardAccrued[msg.sender][token],
                        info.staked,
                        info.lastUpdateTimestamp
                    );

                    $.rewardAccrued[msg.sender][token] = 0;

                    // Scale down the amount for 6 decimal token
                    uint256 scaledAmount = amounts[i];
                    if (token == address($.pUSD)) {
                        scaledAmount = amounts[i] / 1e12; // Convert from 18 to 6 decimals
                    }

                    try IERC20(token).transfer(msg.sender, scaledAmount) returns (bool success) {
                        require(success, "Transfer returned false");
                        emit ClaimedRewards(msg.sender, token, scaledAmount);
                    } catch Error(string memory reason) {
                        revert(string.concat("Transfer failed: ", reason));
                    } catch Panic(uint256 errorCode) {
                        string memory panicReason;
                        if (errorCode == 0x01) {
                            panicReason = "assertion failed";
                        } else if (errorCode == 0x11) {
                            panicReason = "arithmetic overflow";
                        } else if (errorCode == 0x12) {
                            panicReason = "division by zero";
                        } else {
                            panicReason = "unknown panic";
                        }
                        revert(string.concat("Transfer panic: ", panicReason));
                    } catch (bytes memory errorData) {
                        revert(string.concat("Transfer failed with raw error: ", string(errorData)));
                    }
                }
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
            pending = (info.staked * 1e12 * (block.timestamp - info.lastUpdateTimestamp) * $.rewardRates[token]) / _BASE;
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
        return _getPlumeStakingStorage().totalClaimableByToken[token];
    }

    /**
     * @notice Returns the amount of PLUME currently in cooling period for the caller
     * @return amount Amount of PLUME in cooling period, returns 0 if cooldown period has passed
     */
    function amountCooling() external view returns (uint256 amount) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        StakeInfo storage info = $.stakeInfo[msg.sender];

        // If cooldown has ended, return 0
        if (info.cooldownEnd != 0 && block.timestamp >= info.cooldownEnd) {
            return 0;
        }

        return info.cooled;
    }

    /**
     * @notice Returns the total amount of PLUME in cooling period across all users
     * @return total Total amount of PLUME in cooling period
     */
    function totalAmountCooling() external view returns (uint256 total) {
        return _getPlumeStakingStorage().totalCooling;
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
        return _getPlumeStakingStorage().totalWithdrawable;
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
        return _getPlumeStakingStorage().totalStaked;
    }

}
