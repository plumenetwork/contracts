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
        /// @notice Maps a token address to the last time its reward was globally updated
        mapping(address => uint256) lastUpdateTimes;
        /// @notice Maps a token address to the reward per token accumulated so far
        mapping(address => uint256) rewardPerTokenCumulative;
        /// @notice Maps a token address to the amount of rewards still to be distributed
        mapping(address => uint256) rewardsAvailable;
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
     * @return Array of all reward token addresses
     */
    function getRewardTokens() external view returns (address[] memory) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        return $.rewardTokens;
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
     * @notice Set the minimum stake amount
     * @param amount The new minimum stake amount
     */
    function setMinStakeAmount(
        uint256 amount
    ) external onlyRole(ADMIN_ROLE) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        $.minStakeAmount = amount;
        emit MinStakeAmountSet(amount);
    }

    /**
     * @notice Set the cooldown interval
     * @param interval The new cooldown interval in seconds
     */
    function setCooldownInterval(
        uint256 interval
    ) external onlyRole(ADMIN_ROLE) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        $.cooldownInterval = interval;
        emit CooldownIntervalSet(interval);
    }

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
        StakeInfo storage info = $.stakeInfo[staker];

        if (info.staked > 0) {
            address[] storage stakersList = $.stakers;
            for (uint256 i = 0; i < stakersList.length; i++) {
                if (stakersList[i] == staker) {
                    return;
                }
            }
            stakersList.push(staker);
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
                $.rewards[user][token] = _earned(user, token, $.stakeInfo[user].staked);
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

}
