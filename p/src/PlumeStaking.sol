// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title PlumeStaking
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Staking contract for native PLUME token
 */
contract PlumeStaking is Initializable, AccessControlUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {

    using SafeERC20 for IERC20;
    using Address for address payable;

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
        /// @dev Address of the $pUSD token
        IERC20 pUSD;
        /// @notice Array of all staker addresses
        address[] stakers;
        /// @notice Array of all reward token addresses
        address[] rewardTokens;
        /// @notice Maps a token address to its reward rate in tokens per second per staked token
        mapping(address => uint256) rewardRates;
        /// @notice Maps a token address to its maximum allowed reward rate
        mapping(address => uint256) maxRewardRates;
        /// @notice Maps a token address to the last time its reward was globally updated
        mapping(address => uint256) lastUpdateTimes;
        /// @notice Maps a token address to the reward per token accumulated so far
        mapping(address => uint256) rewardPerTokenCumulative;
        /// @notice Maps a token address to the amount of rewards still to be distributed
        mapping(address => uint256) rewardsAvailable;
        /// @notice Maps a token address to the total amount claimable for that token
        mapping(address => uint256) totalClaimableByToken;
        /// @notice Total $PLUME staked in the contract
        uint256 totalStaked;
        /// @notice Total $PLUME in cooling period
        uint256 totalCooling;
        /// @notice Total $PLUME that is withdrawable (parked)
        uint256 totalWithdrawable;
        /// @notice Minimum staking amount
        uint256 minStakeAmount;
        /// @notice Duration of the cooldown period
        uint256 cooldownInterval;
        /// @notice Maps an address to its staking info
        mapping(address => StakeInfo) stakeInfo;
        /// @notice Maps a (user, token) pair to the reward per token paid to that user for that token
        mapping(address => mapping(address => uint256)) userRewardPerTokenPaid;
        /// @notice Maps a (user, token) pair to the reward of that token for that user
        mapping(address => mapping(address => uint256)) rewards;
        /// @notice Mapping to track if an address is already in stakers array
        mapping(address => bool) isStaker;
    }

    // Modified StakeInfo struct to reflect changes
    struct StakeInfo {
        uint256 staked; // Amount of PLUME staked
        uint256 parked; // Amount of PLUME ready to be withdrawn
        uint256 cooled; // Amount of PLUME in cooling period
        uint256 cooldownEnd; // Timestamp when cooling period ends
    }

    // Constants

    /// @notice Role for administrators of PlumeStaking
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @notice Role for upgraders of PlumeStaking
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    /// @notice Maximum reward rate: ~100% APY (3171 nanotoken per second per token)
    uint256 public constant MAX_REWARD_RATE = 3171 * 1e9;
    /// @notice Scaling factor for reward calculations
    uint256 public constant REWARD_PRECISION = 1e18;

    // Events

    /**
     * @notice Emitted when a user stakes PLUME
     * @param user Address of the user
     * @param amount Amount of $PLUME staked
     * @param fromCooling Amount taken from cooling
     * @param fromParked Amount taken from parked
     * @param fromWallet Amount taken from wallet
     */
    event Staked(address indexed user, uint256 amount, uint256 fromCooling, uint256 fromParked, uint256 fromWallet);

    /**
     * @notice Emitted when a user unstakes PLUME
     * @param user Address of the user
     * @param amount Amount of PLUME unstaked
     */
    event Unstaked(address indexed user, uint256 amount);

    /**
     * @notice Emitted when a user withdraws their cooled-down PLUME
     * @param user Address of the user
     * @param amount Amount of PLUME withdrawn
     */
    event Withdrawn(address indexed user, uint256 amount);

    /**
     * @notice Emitted when a user claims a reward
     * @param user Address of the user
     * @param token Address of the reward token
     * @param amount Amount of reward token claimed
     */
    event RewardClaimed(address indexed user, address indexed token, uint256 amount);

    /**
     * @notice Emitted when the minimum stake amount is set
     * @param amount New minimum stake amount
     */
    event MinStakeAmountSet(uint256 amount);

    /**
     * @notice Emitted when the cooldown interval is set
     * @param interval New cooldown interval
     */
    event CooldownIntervalSet(uint256 interval);

    /**
     * @notice Emitted when reward rates are updated
     * @param tokens Array of token addresses
     * @param rates Array of reward rates
     */
    event RewardRatesSet(address[] tokens, uint256[] rates);

    /**
     * @notice Emitted when rewards are added to the rewards pool
     * @param token Address of the token
     * @param amount Amount of tokens added
     */
    event RewardsAdded(address indexed token, uint256 amount);

    // Errors

    /**
     * @notice Thrown for an invalid amount
     * @param amount The amount that was provided
     * @param minAmount The minimum amount required
     */
    error InvalidAmount(uint256 amount, uint256 minAmount);

    /**
     * @notice Thrown when a user with cooling tokens tries to stake again
     * @dev TODO remove this restriction in the future
     * @param amount Amount of tokens in cooling period
     */
    error TokensInCoolingPeriod(uint256 amount);

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
    function initialize(address owner, address pUSD_) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
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

    // Storage Functions

    /// @dev Returns the current storage struct
    function _getPlumeStakingStorage() private pure returns (PlumeStakingStorage storage $) {
        bytes32 position = keccak256("plume.storage.PlumeStaking");
        assembly {
            $.slot := position
        }
    }

    // External Functions

    // Modified to accept native tokens
    /**
     * @notice Stake PLUME into the contract
     */
    function stake() external payable nonReentrant {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        StakeInfo storage info = $.stakeInfo[msg.sender];

        uint256 amount = msg.value;

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

        // Last: Take remaining from wallet (already received via msg.value)
        if (remainingToStake > 0) {
            fromWallet = remainingToStake;
            // No need to transfer - we already have the tokens via msg.value
        }

        // Update total staked amount
        info.staked += amount;
        $.totalStaked += amount;
        $.totalCooling -= fromCooling;
        $.totalWithdrawable -= fromParked;

        _updateRewards(msg.sender);
        _addStakerIfNew(msg.sender);

        // Single event with all source information
        emit Staked(msg.sender, amount, fromCooling, fromParked, fromWallet);
    }

    /**
     * @notice Unstake PLUME from the contract
     * @return amount Amount of PLUME unstaked
     */
    function unstake() external nonReentrant returns (uint256 amount) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        StakeInfo storage info = $.stakeInfo[msg.sender];

        _updateRewards(msg.sender); // Capture rewards at current stake amount

        amount = info.staked;
        info.staked = 0;
        $.totalStaked -= amount;

        // Send tokens to cooling period
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
    function withdraw() external nonReentrant returns (uint256 amount) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        StakeInfo storage info = $.stakeInfo[msg.sender];

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
        payable(msg.sender).sendValue(amount);

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
    ) external nonReentrant returns (uint256 amount) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();

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
            if (token != address(0)) {
                IERC20(token).safeTransfer(msg.sender, amount);
            } else {
                // For native token rewards
                payable(msg.sender).sendValue(amount);
            }

            emit RewardClaimed(msg.sender, token, amount);
        }

        return amount;
    }

    /**
     * @notice Claim all accumulated rewards from all tokens
     * @return amounts Array of amounts claimed for each token
     */
    function claimAll() external nonReentrant returns (uint256[] memory amounts) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
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
                if (token != address(0)) {
                    IERC20(token).safeTransfer(msg.sender, amount);
                } else {
                    // For native token rewards
                    payable(msg.sender).sendValue(amount);
                }

                emit RewardClaimed(msg.sender, token, amount);
            }
        }

        return amounts;
    }

    /**
     * @notice Claim all accumulated rewards from a single token and stake the reward
     * @param token Address of the reward token to claim and stake
     * @return amount Amount of reward token claimed and staked
     * @dev This only works if the token is PLUME
     */
    function claimAndStake(
        address token
    ) external nonReentrant returns (uint256 amount) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        StakeInfo storage info = $.stakeInfo[msg.sender];

        // If token is not address(0), it must not be a native token
        if (token != address(0)) {
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

            // Update staking information
            info.staked += amount;
            $.totalStaked += amount;

            _updateRewards(msg.sender);
            _addStakerIfNew(msg.sender);

            emit RewardClaimed(msg.sender, token, amount);
            emit Staked(msg.sender, amount, 0, 0, 0);
        }

        return amount;
    }

    /**
     * @notice Get information about the staking contract
     * @return totalStaked Total PLUME staked
     * @return totalCooling Total PLUME in cooling
     * @return totalWithdrawable Total PLUME in withdrawable state
     * @return minStakeAmount Minimum staking amount
     * @return rewardTokens Array of all reward tokens
     */
    function stakingInfo()
        external
        view
        returns (
            uint256 totalStaked,
            uint256 totalCooling,
            uint256 totalWithdrawable,
            uint256 minStakeAmount,
            address[] memory rewardTokens
        )
    {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        return ($.totalStaked, $.totalCooling, $.totalWithdrawable, $.minStakeAmount, $.rewardTokens);
    }

    /**
     * @notice Get staking information for a user
     * @param user Address of the user
     * @return stake The StakeInfo struct for the user
     */
    function stakeInfo(
        address user
    ) external view returns (StakeInfo memory) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        return $.stakeInfo[user];
    }

    /**
     * @notice Get token reward info
     * @param token Address of the token
     * @return rate Current reward rate
     * @return available Total rewards available
     */
    function tokenRewardInfo(
        address token
    ) external view returns (uint256 rate, uint256 available) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        return ($.rewardRates[token], $.rewardsAvailable[token]);
    }

    /**
     * @notice Get all stakers
     * @return Array of all staker addresses
     */
    function getAllStakers() external view returns (address[] memory) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        return $.stakers;
    }

    /**
     * @notice Get all reward tokens
     * @return tokens Array of all reward token addresses
     * @return rates Array of reward rates corresponding to each token
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
     * @notice Get reward information for a user
     * @param user Address of the user
     * @param token Address of the token
     * @return rewards Current pending rewards
     */
    function earned(address user, address token) external view returns (uint256 rewards) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();

        if (!_isRewardToken(token)) {
            return 0;
        }

        return _earned(user, token, $.stakeInfo[user].staked);
    }

    // Admin Functions

    /**
     * @notice Add a token to the rewards list
     * @param token Address of the token to add
     */
    function addRewardToken(
        address token
    ) external onlyRole(ADMIN_ROLE) {
        // Allow address(0) to represent native PLUME token
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();

        if (_isRewardToken(token)) {
            revert TokenAlreadyExists(token);
        }

        $.rewardTokens.push(token);
        $.lastUpdateTimes[token] = block.timestamp;
        emit RewardTokenAdded(token);
    }

    /**
     * @notice Remove a token from the rewards list
     * @param token Address of the token to remove
     */
    function removeRewardToken(
        address token
    ) external onlyRole(ADMIN_ROLE) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        uint256 tokenIndex = _getTokenIndex(token);

        if (tokenIndex >= $.rewardTokens.length) {
            revert TokenDoesNotExist(token);
        }

        // Capture any remaining rewards and zero the rate
        _updateRewardPerToken(token);
        $.rewardRates[token] = 0;

        // Remove token from the rewards list (replace with last element and pop)
        $.rewardTokens[tokenIndex] = $.rewardTokens[$.rewardTokens.length - 1];
        $.rewardTokens.pop();

        emit RewardTokenRemoved(token);
    }

    /**
     * @notice Set the reward rates for tokens
     * @param tokens Array of token addresses
     * @param rewardRates_ Array of reward rates
     */
    function setRewardRates(address[] calldata tokens, uint256[] calldata rewardRates_) external onlyRole(ADMIN_ROLE) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();

        if (tokens.length == 0) {
            revert EmptyArray();
        }

        if (tokens.length != rewardRates_.length) {
            revert ArrayLengthMismatch();
        }

        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 rate = rewardRates_[i];

            if (rate > MAX_REWARD_RATE) {
                revert RewardRateExceedsMax(rate, MAX_REWARD_RATE);
            }

            if (!_isRewardToken(token)) {
                // Add token to reward list if not already included
                // Allow address(0) to represent native PLUME token
                $.rewardTokens.push(token);
                $.lastUpdateTimes[token] = block.timestamp;
                emit RewardTokenAdded(token);
            } else {
                // Update existing token reward state
                _updateRewardPerToken(token);
            }

            $.rewardRates[token] = rate;
        }

        emit RewardRatesSet(tokens, rewardRates_);
    }

    /**
     * @notice Add rewards to the pool
     * @param token Address of the token
     * @param amount Amount to add
     */
    function addRewards(address token, uint256 amount) external payable onlyRole(ADMIN_ROLE) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();

        if (!_isRewardToken(token)) {
            revert TokenDoesNotExist(token);
        }

        _updateRewardPerToken(token);

        // For native token
        if (token == address(0)) {
            if (msg.value != amount) {
                revert InvalidAmount(msg.value, amount);
            }
            // Native tokens already received in msg.value
        } else {
            // Transfer ERC20 tokens from sender to this contract
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        $.rewardsAvailable[token] += amount;
        emit RewardsAdded(token, amount);
    }

    // Internal Functions

    /**
     * @notice Add a staker to the list if they are not already in it
     * @param staker Address of the staker
     */
    function _addStakerIfNew(
        address staker
    ) internal {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();

        if ($.stakeInfo[staker].staked > 0 && !$.isStaker[staker]) {
            $.stakers.push(staker);
            $.isStaker[staker] = true;
        }
    }

    /**
     * @notice Update rewards for a user
     * @param user The address of the user
     */
    function _updateRewards(
        address user
    ) internal {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
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
     * @param token The address of the reward token
     */
    function _updateRewardPerToken(
        address token
    ) internal {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();

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
     * @param user The address of the user
     * @param token The address of the token
     * @param userStakedAmount The amount staked by the user
     * @return rewards The earned rewards
     */
    function _earned(address user, address token, uint256 userStakedAmount) internal view returns (uint256 rewards) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();

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
     * @notice Get the index of a token in the rewards list
     * @param token The address of the token
     * @return The index of the token
     */
    function _getTokenIndex(
        address token
    ) internal view returns (uint256) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        address[] memory tokens = $.rewardTokens;

        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token) {
                return i;
            }
        }

        return tokens.length;
    }

    /**
     * @notice Check if a token is in the rewards list
     * @param token The address of the token
     * @return True if the token is in the rewards list, false otherwise
     */
    function _isRewardToken(
        address token
    ) internal view returns (bool) {
        return _getTokenIndex(token) < _getPlumeStakingStorage().rewardTokens.length;
    }

    /**
     * @notice Receive function to allow contract to receive native tokens
     */
    receive() external payable {
        // Allow the contract to receive native tokens
    }

    /**
     * @notice Get the total amount of PLUME staked in the contract
     * @return Total amount of PLUME staked
     */
    function totalAmountStaked() external view returns (uint256) {
        return _getPlumeStakingStorage().totalStaked;
    }

    /**
     * @notice Get the total amount of PLUME in cooling period
     * @return Total amount of PLUME in cooling period
     */
    function totalAmountCooling() external view returns (uint256) {
        return _getPlumeStakingStorage().totalCooling;
    }

    /**
     * @notice Get the total amount of PLUME that is withdrawable
     * @return Total amount of PLUME that is withdrawable
     */
    function totalAmountWithdrawable() external view returns (uint256) {
        return _getPlumeStakingStorage().totalWithdrawable;
    }

    /**
     * @notice Get the total amount of reward token claimable
     * @param token Address of the reward token
     * @return Total amount of reward token claimable
     */
    function totalAmountClaimable(
        address token
    ) external view returns (uint256) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        return $.totalClaimableByToken[token];
    }

    /**
     * @notice Get the total amount of reward tokens that can still be distributed
     * @param token Address of the reward token
     * @return Total amount of reward token available for distribution
     */
    function totalRewardsAvailable(
        address token
    ) external view returns (uint256) {
        return _getPlumeStakingStorage().rewardsAvailable[token];
    }

    // New functions from pUSDStaking

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

        // Update user's stake info
        info.staked = staked;
        info.cooled = cooled;
        info.parked = parked;
        info.cooldownEnd = cooldownEnd;

        // Add user to stakers list if they have any funds
        if (staked > 0 || cooled > 0 || parked > 0) {
            _addStakerIfNew(user);
        }

        // Update rewards for all tokens
        _updateRewards(user);

        emit StakeInfoUpdated(user, staked, cooled, parked, cooldownEnd, lastUpdateTimestamp);
    }

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
     * @notice Emitted when admin manually adds a staker
     * @param staker Address of the staker that was added
     */
    event StakerAdded(address indexed staker);

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
     * @notice Emitted when total amounts are updated by admin
     * @param totalStaked New total staked amount
     * @param totalCooling New total cooling amount
     * @param totalWithdrawable New total withdrawable amount
     */
    event TotalAmountsUpdated(uint256 totalStaked, uint256 totalCooling, uint256 totalWithdrawable);

    /**
     * @notice Allows admin to withdraw any token from the contract
     * @param token Address of the token to withdraw (use address(0) for native tokens)
     * @param amount Amount of tokens to withdraw
     * @param recipient Address to receive the tokens
     */
    function adminWithdraw(
        address token,
        uint256 amount,
        address recipient
    ) external onlyRole(ADMIN_ROLE) nonReentrant {
        if (recipient == address(0)) {
            revert ZeroAddress("recipient");
        }
        if (amount == 0) {
            revert InvalidAmount(0, 1);
        }

        // For native token (address(0))
        if (token == address(0)) {
            uint256 totalLocked = this.totalAmountStaked() + this.totalAmountCooling();
            uint256 balance = address(this).balance;
            require(balance - amount >= totalLocked, "Cannot withdraw staked/cooling tokens");

            // Transfer native tokens
            payable(recipient).sendValue(amount);
        } else {
            // For ERC20 tokens
            IERC20(token).safeTransfer(recipient, amount);
        }

        emit AdminWithdraw(token, amount, recipient);
    }

    /**
     * @notice Emitted when admin withdraws tokens from the contract
     * @param token Address of the token withdrawn
     * @param amount Amount of tokens withdrawn
     * @param recipient Address that received the tokens
     */
    event AdminWithdraw(address indexed token, uint256 amount, address indexed recipient);

    /**
     * @notice Set the maximum reward rate for a specific token
     * @param token The token to set the max rate for
     * @param newMaxRate The new maximum reward rate
     */
    function setMaxRewardRate(address token, uint256 newMaxRate) external onlyRole(ADMIN_ROLE) nonReentrant {
        if (!_isRewardToken(token)) {
            revert TokenDoesNotExist(token);
        }
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        $.maxRewardRates[token] = newMaxRate;
        emit MaxRewardRateUpdated(token, newMaxRate);
    }

    /**
     * @notice Emitted when the maximum reward rate for a token is updated
     * @param token The token whose max rate was updated
     * @param newMaxRate The new maximum reward rate
     */
    event MaxRewardRateUpdated(address indexed token, uint256 newMaxRate);

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

    /**
     * @notice Withdrawable balance of a user
     * @param user Address of the user
     * @return amount Amount of PLUME available to withdraw
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
     * @notice Claimable rewards of a user in a specific token
     * @param user Address of the user
     * @param token Address of the reward token
     * @return amount Amount of token available to claim
     */
    function claimableBalance(address user, address token) public view returns (uint256 amount) {
        if (!_isRewardToken(token)) {
            return 0;
        }
        return _earned(user, token, _getPlumeStakingStorage().stakeInfo[user].staked);
    }

    /**
     * @notice Returns the claimable amount for a specific token for the caller
     * @param token Address of the reward token
     * @return amount Claimable reward amount for the caller
     */
    function amountClaimable(
        address token
    ) external view returns (uint256 amount) {
        return claimableBalance(msg.sender, token);
    }

    /**
     * @notice Returns the claimable reward for a user for a given reward token.
     * @param user Address of the user.
     * @param token Address of the reward token.
     * @return amount Claimable reward amount.
     */
    function getClaimableReward(address user, address token) external view returns (uint256 amount) {
        return claimableBalance(user, token);
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
     * @notice Returns the amount of PLUME currently staked by the caller
     * @return amount Amount of PLUME staked
     */
    function amountStaked() external view returns (uint256 amount) {
        return _getPlumeStakingStorage().stakeInfo[msg.sender].staked;
    }

    /// @notice Minimum amount of $PLUME that can be staked
    function getMinStakeAmount() external view returns (uint256) {
        return _getPlumeStakingStorage().minStakeAmount;
    }

    /// @notice Cooldown interval for staked assets to be unlocked and parked
    function cooldownInterval() external view returns (uint256) {
        return _getPlumeStakingStorage().cooldownInterval;
    }

    /**
     * @notice Set the minimum amount of $PLUME that can be staked
     * @param minStakeAmount_ Minimum amount of $PLUME that can be staked
     */
    function setMinStakeAmount(
        uint256 minStakeAmount_
    ) external onlyRole(ADMIN_ROLE) nonReentrant {
        _getPlumeStakingStorage().minStakeAmount = minStakeAmount_;
        emit MinStakeAmountSet(minStakeAmount_);
    }

    /**
     * @notice Set the cooldown interval for staked assets to be unlocked and parked
     * @param cooldownInterval_ Cooldown interval for staked assets to be unlocked and parked
     */
    function setCooldownInterval(
        uint256 cooldownInterval_
    ) external onlyRole(ADMIN_ROLE) nonReentrant {
        _getPlumeStakingStorage().cooldownInterval = cooldownInterval_;
        emit CooldownIntervalSet(cooldownInterval_);
    }

    /**
     * @notice Get the reward rate for a specific token
     * @param token Address of the token
     * @return rate Current reward rate for the token
     */
    function rewardRate(
        address token
    ) external view returns (uint256 rate) {
        return _getPlumeStakingStorage().rewardRates[token];
    }

}
