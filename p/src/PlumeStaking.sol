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
        // Validator related storage
        /// @notice Information about each validator
        mapping(uint16 => ValidatorInfo) validators;
        /// @notice Array of all validator IDs
        uint16[] validatorIds;
        /// @notice Mapping to check if a validator exists
        mapping(uint16 => bool) validatorExists;
        /// @notice Maps a (user, validator) pair to the user's stake info for that validator
        mapping(address => mapping(uint16 => StakeInfo)) userValidatorStakes;
        /// @notice Maps a user to all validators they have staked with
        mapping(address => uint16[]) userValidators;
        /// @notice Maps a (user, validator) pair to indicate if user has staked with that validator
        mapping(address => mapping(uint16 => bool)) userHasStakedWithValidator;
        /// @notice Maps a validator to all stakers who have staked with it
        mapping(uint16 => address[]) validatorStakers;
        /// @notice Maps a (validator, staker) pair to indicate if staker has staked with that validator
        mapping(uint16 => mapping(address => bool)) isStakerForValidator;
        /// @notice Maps a validator to its total staked amount
        mapping(uint16 => uint256) validatorTotalStaked;
        /// @notice Maps a validator to its total cooling amount
        mapping(uint16 => uint256) validatorTotalCooling;
        /// @notice Maps a validator to its total withdrawable amount
        mapping(uint16 => uint256) validatorTotalWithdrawable;
        /// @notice Maps a (validator, token) pair to the last time rewards were updated
        mapping(uint16 => mapping(address => uint256)) validatorLastUpdateTimes;
        /// @notice Maps a (validator, token) pair to the reward per token accumulated
        mapping(uint16 => mapping(address => uint256)) validatorRewardPerTokenCumulative;
        /// @notice Maps a (user, validator, token) triple to the reward per token paid
        mapping(address => mapping(uint16 => mapping(address => uint256))) userRewardPerTokenPaid;
        /// @notice Maps a (user, validator, token) triple to the rewards earned
        mapping(address => mapping(uint16 => mapping(address => uint256))) userRewards;
        /// @notice Maps a (validator, token) pair to the commission accumulated
        mapping(uint16 => mapping(address => uint256)) validatorAccruedCommission;
        /// @notice Flag to indicate if epochs are being used
        bool usingEpochs;
        /// @notice Current epoch number
        uint256 currentEpochNumber;
        /// @notice Maps epoch number to validator amounts for each validator
        mapping(uint256 => mapping(uint16 => uint256)) epochValidatorAmounts;
    }

    // Validator info struct to store validator details
    struct ValidatorInfo {
        uint16 validatorId; // Fixed UUID for the validator
        uint256 commission; // Commission rate (BASE = 1e18, so 5% = 5e16)
        uint256 delegatedAmount; // Total amount delegated to this validator
        address l2AdminAddress; // Admin address (multisig)
        address l2WithdrawAddress; // Address for validator rewards
        string l1ValidatorAddress; // L1 validator address (for reference)
        string l1AccountAddress; // L1 account address (for reference)
        bool active; // Whether the validator is active
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
    /// @notice Address constant used to represent the native PLUME token
    address public constant PLUME = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

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

    /**
     * @notice Emitted when a user stakes PLUME to a validator
     * @param user Address of the user
     * @param validatorId ID of the validator
     * @param amount Total amount staked
     * @param fromCooling Amount taken from cooling
     * @param fromParked Amount taken from parked
     * @param fromWallet Amount taken from wallet
     */
    event StakedToValidator(
        address indexed user,
        uint16 indexed validatorId,
        uint256 amount,
        uint256 fromCooling,
        uint256 fromParked,
        uint256 fromWallet
    );

    /**
     * @notice Emitted when a user unstakes PLUME from a validator
     * @param user Address of the user
     * @param validatorId ID of the validator
     * @param amount Amount unstaked
     */
    event UnstakedFromValidator(address indexed user, uint16 indexed validatorId, uint256 amount);

    /**
     * @notice Emitted when a user claims rewards from a validator
     * @param user Address of the user
     * @param token Address of the reward token
     * @param validatorId ID of the validator
     * @param amount Amount claimed
     */
    event RewardClaimedFromValidator(
        address indexed user, address indexed token, uint16 indexed validatorId, uint256 amount
    );

    /**
     * @notice Emitted when validator commission is claimed
     * @param validatorId ID of the validator
     * @param token Address of the token
     * @param amount Amount of commission claimed
     */
    event ValidatorCommissionClaimed(uint16 indexed validatorId, address indexed token, uint256 amount);

    /**
     * @notice Emitted when a validator is added
     * @param validatorId ID of the validator
     * @param commission Commission rate
     * @param l2AdminAddress Admin address
     * @param l2WithdrawAddress Withdrawal address
     * @param l1ValidatorAddress L1 validator address
     * @param l1AccountAddress L1 account address
     */
    event ValidatorAdded(
        uint16 indexed validatorId,
        uint256 commission,
        address l2AdminAddress,
        address l2WithdrawAddress,
        string l1ValidatorAddress,
        string l1AccountAddress
    );

    /**
     * @notice Emitted when a validator is updated
     * @param validatorId ID of the validator
     * @param commission New commission rate
     * @param l2AdminAddress New admin address
     * @param l2WithdrawAddress New withdrawal address
     * @param l1ValidatorAddress New L1 validator address
     * @param l1AccountAddress New L1 account address
     */
    event ValidatorUpdated(
        uint16 indexed validatorId,
        uint256 commission,
        address l2AdminAddress,
        address l2WithdrawAddress,
        string l1ValidatorAddress,
        string l1AccountAddress
    );

    /**
     * @notice Emitted when a validator is deactivated
     * @param validatorId ID of the validator
     */
    event ValidatorDeactivated(uint16 indexed validatorId);

    /**
     * @notice Emitted when a validator is activated
     * @param validatorId ID of the validator
     */
    event ValidatorActivated(uint16 indexed validatorId);

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
     * @notice Thrown when trying to interact with a validator that doesn't exist
     * @param validatorId ID of the non-existent validator
     */
    error ValidatorDoesNotExist(uint16 validatorId);

    /**
     * @notice Thrown when trying to add a validator that already exists
     * @param validatorId ID of the already existing validator
     */
    error ValidatorAlreadyExists(uint16 validatorId);

    /**
     * @notice Thrown when commission is set too high
     * @param commission Specified commission rate
     * @param maxCommission Maximum allowed commission rate
     */
    error CommissionTooHigh(uint256 commission, uint256 maxCommission);

    /**
     * @notice Thrown when a non-admin tries to perform an admin action for a validator
     * @param caller Address that tried to perform the action
     * @param validatorId ID of the validator
     */
    error NotValidatorAdmin(address caller, uint16 validatorId);

    /**
     * @notice Thrown when trying to interact with an inactive validator
     * @param validatorId ID of the inactive validator
     */
    error ValidatorInactive(uint16 validatorId);

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

        // Update total staked amount - simple direct stake
        info.staked += amount;
        $.totalStaked += amount;

        _updateRewards(msg.sender);
        _addStakerIfNew(msg.sender);

        // Only from wallet - no other sources
        emit Staked(msg.sender, amount, 0, 0, amount);
    }

    /**
     * @notice Stake PLUME to a specific validator
     * @param validatorId ID of the validator to stake to
     */
    function stakeToValidator(
        uint16 validatorId
    ) external payable nonReentrant {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();

        // Verify validator exists and is active
        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }

        ValidatorInfo storage validator = $.validators[validatorId];
        if (!validator.active) {
            revert ValidatorInactive(validatorId);
        }

        uint256 amount = msg.value;
        if (amount < $.minStakeAmount) {
            revert InvalidAmount(amount, $.minStakeAmount);
        }

        // Get user's stake info for this validator
        StakeInfo storage info = $.userValidatorStakes[msg.sender][validatorId];

        // Update rewards before changing stake amount
        _updateRewardsForValidator(msg.sender, validatorId);

        // Update user's staked amount for this validator
        info.staked += amount;

        // Update validator's delegated amount
        validator.delegatedAmount += amount;

        // Update total staked amounts
        $.validatorTotalStaked[validatorId] += amount;
        $.totalStaked += amount;

        // Track user-validator relationship
        _addStakerToValidator(msg.sender, validatorId);

        // Update rewards again with new stake amount
        _updateRewardsForValidator(msg.sender, validatorId);

        emit StakedToValidator(msg.sender, validatorId, amount, 0, 0, amount);
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
     * @notice Unstake PLUME from a specific validator
     * @param validatorId ID of the validator to unstake from
     * @return amount Amount of PLUME unstaked
     */
    function unstakeFromValidator(
        uint16 validatorId
    ) external nonReentrant returns (uint256 amount) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();

        // Verify validator exists
        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }

        // Get user's stake info for this validator
        StakeInfo storage info = $.userValidatorStakes[msg.sender][validatorId];

        if (info.staked == 0) {
            revert NoActiveStake();
        }

        // Update rewards before changing stake amount
        _updateRewardsForValidator(msg.sender, validatorId);

        // Get unstaked amount
        amount = info.staked;

        // Update user's staked amount for this validator
        info.staked = 0;

        // Update validator's delegated amount
        $.validators[validatorId].delegatedAmount -= amount;

        // Update total staked amounts
        $.validatorTotalStaked[validatorId] -= amount;
        $.totalStaked -= amount;

        // Move tokens to cooling period
        info.cooled += amount;
        info.cooldownEnd = block.timestamp + $.cooldownInterval;

        // Update cooling totals
        $.validatorTotalCooling[validatorId] += amount;
        $.totalCooling += amount;

        emit UnstakedFromValidator(msg.sender, validatorId, amount);
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
            if (token != PLUME) {
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
     * @notice Claim all accumulated rewards from a single token and validator
     * @param token Address of the reward token to claim
     * @param validatorId ID of the validator to claim from
     * @return amount Amount of reward token claimed
     */
    function claimFromValidator(address token, uint16 validatorId) external nonReentrant returns (uint256 amount) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();

        if (!_isRewardToken(token)) {
            revert TokenDoesNotExist(token);
        }

        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }

        _updateRewardsForValidator(msg.sender, validatorId);

        amount = $.userRewards[msg.sender][validatorId][token];
        if (amount > 0) {
            $.userRewards[msg.sender][validatorId][token] = 0;

            // Transfer tokens - either ERC20 or native PLUME
            if (token != PLUME) {
                IERC20(token).safeTransfer(msg.sender, amount);
            } else {
                payable(msg.sender).sendValue(amount);
            }

            emit RewardClaimedFromValidator(msg.sender, token, validatorId, amount);
        }

        return amount;
    }

    /**
     * @notice Claim all accumulated rewards from a single token across all validators
     * @param token Address of the reward token to claim
     * @return totalAmount Total amount of reward token claimed
     */
    function claimFromAllValidators(
        address token
    ) external nonReentrant returns (uint256 totalAmount) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();

        if (!_isRewardToken(token)) {
            revert TokenDoesNotExist(token);
        }

        uint16[] memory userValidators = $.userValidators[msg.sender];
        totalAmount = 0;

        for (uint256 i = 0; i < userValidators.length; i++) {
            uint16 validatorId = userValidators[i];

            _updateRewardsForValidator(msg.sender, validatorId);

            uint256 amount = $.userRewards[msg.sender][validatorId][token];
            if (amount > 0) {
                $.userRewards[msg.sender][validatorId][token] = 0;
                totalAmount += amount;

                emit RewardClaimedFromValidator(msg.sender, token, validatorId, amount);
            }
        }

        if (totalAmount > 0) {
            // Transfer tokens - either ERC20 or native PLUME
            if (token != PLUME) {
                IERC20(token).safeTransfer(msg.sender, totalAmount);
            } else {
                payable(msg.sender).sendValue(totalAmount);
            }
        }

        return totalAmount;
    }

    /**
     * @notice Claim validator commission rewards
     * @param validatorId ID of the validator
     * @param token Address of the reward token to claim
     * @return amount Amount of commission claimed
     */
    function claimValidatorCommission(
        uint16 validatorId,
        address token
    ) external nonReentrant returns (uint256 amount) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();

        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }

        ValidatorInfo storage validator = $.validators[validatorId];

        // Only validator admin can claim commission
        if (msg.sender != validator.l2AdminAddress) {
            revert NotValidatorAdmin(msg.sender, validatorId);
        }

        // Update all rewards to ensure commission is current
        _updateRewardsForAllValidatorStakers(validatorId);

        amount = $.validatorAccruedCommission[validatorId][token];
        if (amount > 0) {
            $.validatorAccruedCommission[validatorId][token] = 0;

            // Transfer to validator's withdraw address
            if (token != PLUME) {
                IERC20(token).safeTransfer(validator.l2WithdrawAddress, amount);
            } else {
                payable(validator.l2WithdrawAddress).sendValue(amount);
            }

            emit ValidatorCommissionClaimed(validatorId, token, amount);
        }

        return amount;
    }

    /**
     * @notice Stakes native token (PLUME) rewards without withdrawing them first
     * @return stakedAmount Amount of PLUME rewards that were staked
     */
    function restakeRewards() external nonReentrant returns (uint256 stakedAmount) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        StakeInfo storage info = $.stakeInfo[msg.sender];

        // Native token is represented by PLUME constant
        address token = PLUME;

        if (!_isRewardToken(token)) {
            revert TokenDoesNotExist(token);
        }

        // Update rewards to get the latest amount
        _updateRewards(msg.sender);

        // Get the current reward amount for native token
        stakedAmount = $.rewards[msg.sender][token];

        if (stakedAmount > 0) {
            // Reset rewards to 0 as if they were claimed
            $.rewards[msg.sender][token] = 0;

            // Update total claimable
            if ($.totalClaimableByToken[token] >= stakedAmount) {
                $.totalClaimableByToken[token] -= stakedAmount;
            } else {
                $.totalClaimableByToken[token] = 0;
            }

            // Add to user's staked amount
            info.staked += stakedAmount;
            $.totalStaked += stakedAmount;

            // Update rewards again with new stake amount
            _updateRewards(msg.sender);
            _addStakerIfNew(msg.sender);

            // Emit both claimed and staked events
            emit RewardClaimed(msg.sender, token, stakedAmount);
            emit Staked(msg.sender, stakedAmount, 0, 0, 0);
        }

        return stakedAmount;
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
                if (token != PLUME) {
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
     * @notice Move funds from withdrawable or cooling balances into staking
     * @param amount Amount of PLUME to move from withdrawable/cooling to staking
     * @return stakedAmount Total amount successfully moved to staking
     */
    function restake(
        uint256 amount
    ) external nonReentrant returns (uint256 stakedAmount) {
        if (amount == 0) {
            revert InvalidAmount(amount, 1);
        }

        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        StakeInfo storage info = $.stakeInfo[msg.sender];

        _updateRewards(msg.sender);

        // Track sources of staked tokens
        uint256 fromParked = 0;
        uint256 fromCooling = 0;
        uint256 remainingToStake = amount;

        // First: Check withdrawable (parked) tokens
        if (remainingToStake > 0 && info.parked > 0) {
            fromParked = remainingToStake > info.parked ? info.parked : remainingToStake;
            info.parked -= fromParked;
            remainingToStake -= fromParked;

            // Update global withdrawable total
            $.totalWithdrawable -= fromParked;

            // Add to amount being staked
            stakedAmount += fromParked;
        }

        // Second: Check for cooled tokens - can use even if cooldown period is still active
        if (remainingToStake > 0 && info.cooled > 0) {
            fromCooling = remainingToStake > info.cooled ? info.cooled : remainingToStake;
            info.cooled -= fromCooling;

            // Clear cooldown if no more cooling tokens
            if (info.cooled == 0) {
                info.cooldownEnd = 0;
            }

            // Update global cooling total
            $.totalCooling -= fromCooling;

            // Add to amount being staked
            stakedAmount += fromCooling;
        }

        // Check if we were able to restake the requested amount
        if (stakedAmount < amount) {
            revert InvalidAmount(stakedAmount, amount);
        }

        // Update staking information
        info.staked += stakedAmount;
        $.totalStaked += stakedAmount;

        // After processing the requested amount, check if any remaining cooling tokens
        // have completed their cooldown period and move them to withdrawable
        if (info.cooled > 0 && info.cooldownEnd <= block.timestamp) {
            // Move cooled tokens to parked (withdrawable)
            info.parked += info.cooled;
            $.totalWithdrawable += info.cooled;
            $.totalCooling -= info.cooled;

            // Log how much was moved for event emission
            uint256 movedToWithdrawable = info.cooled;

            // Clear cooling info
            info.cooled = 0;
            info.cooldownEnd = 0;

            // Emit event about moving tokens from cooling to withdrawable
            emit CoolingCompleted(msg.sender, movedToWithdrawable);
        }

        _updateRewards(msg.sender);
        _addStakerIfNew(msg.sender);

        // Emit staking event with source breakdown
        emit Staked(msg.sender, stakedAmount, fromCooling, fromParked, 0);

        return stakedAmount;
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
        if (token == PLUME) {
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

    /**
     * @notice Add a new validator
     * @param validatorId Fixed UUID for the validator
     * @param commission Commission rate (as fraction of REWARD_PRECISION)
     * @param l2AdminAddress Admin address for the validator
     * @param l2WithdrawAddress Withdrawal address for validator rewards
     * @param l1ValidatorAddress Address of validator on L1 (informational)
     * @param l1AccountAddress Address of account on L1 (informational)
     */
    function addValidator(
        uint16 validatorId,
        uint256 commission,
        address l2AdminAddress,
        address l2WithdrawAddress,
        string calldata l1ValidatorAddress,
        string calldata l1AccountAddress
    ) external onlyRole(ADMIN_ROLE) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();

        if ($.validatorExists[validatorId]) {
            revert ValidatorAlreadyExists(validatorId);
        }

        if (l2AdminAddress == address(0)) {
            revert ZeroAddress("l2AdminAddress");
        }

        if (l2WithdrawAddress == address(0)) {
            revert ZeroAddress("l2WithdrawAddress");
        }

        if (commission > REWARD_PRECISION) {
            revert CommissionTooHigh(commission, REWARD_PRECISION);
        }

        // Create new validator
        ValidatorInfo storage validator = $.validators[validatorId];
        validator.validatorId = validatorId;
        validator.commission = commission;
        validator.delegatedAmount = 0;
        validator.l2AdminAddress = l2AdminAddress;
        validator.l2WithdrawAddress = l2WithdrawAddress;
        validator.l1ValidatorAddress = l1ValidatorAddress;
        validator.l1AccountAddress = l1AccountAddress;
        validator.active = true;

        // Add to validator registry
        $.validatorIds.push(validatorId);
        $.validatorExists[validatorId] = true;

        // Initialize epoch data if using epochs
        if ($.usingEpochs) {
            $.epochValidatorAmounts[$.currentEpochNumber][validatorId] = 0;
        }

        emit ValidatorAdded(
            validatorId, commission, l2AdminAddress, l2WithdrawAddress, l1ValidatorAddress, l1AccountAddress
        );
    }

    /**
     * @notice Update an existing validator
     * @param validatorId ID of the validator to update
     * @param commission New commission rate
     * @param l2AdminAddress New admin address
     * @param l2WithdrawAddress New withdrawal address
     * @param l1ValidatorAddress New L1 validator address
     * @param l1AccountAddress New L1 account address
     */
    function updateValidator(
        uint16 validatorId,
        uint256 commission,
        address l2AdminAddress,
        address l2WithdrawAddress,
        string calldata l1ValidatorAddress,
        string calldata l1AccountAddress
    ) external onlyRole(ADMIN_ROLE) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();

        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }

        if (l2AdminAddress == address(0)) {
            revert ZeroAddress("l2AdminAddress");
        }

        if (l2WithdrawAddress == address(0)) {
            revert ZeroAddress("l2WithdrawAddress");
        }

        if (commission > REWARD_PRECISION) {
            revert CommissionTooHigh(commission, REWARD_PRECISION);
        }

        ValidatorInfo storage validator = $.validators[validatorId];

        // Update reward state before changing commission
        _updateRewardsForAllValidatorStakers(validatorId);

        validator.commission = commission;
        validator.l2AdminAddress = l2AdminAddress;
        validator.l2WithdrawAddress = l2WithdrawAddress;
        validator.l1ValidatorAddress = l1ValidatorAddress;
        validator.l1AccountAddress = l1AccountAddress;

        emit ValidatorUpdated(
            validatorId, commission, l2AdminAddress, l2WithdrawAddress, l1ValidatorAddress, l1AccountAddress
        );
    }

    /**
     * @notice Deactivate a validator
     * @param validatorId ID of the validator to deactivate
     */
    function deactivateValidator(
        uint16 validatorId
    ) external onlyRole(ADMIN_ROLE) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();

        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }

        ValidatorInfo storage validator = $.validators[validatorId];
        validator.active = false;

        emit ValidatorDeactivated(validatorId);
    }

    /**
     * @notice Activate a validator
     * @param validatorId ID of the validator to activate
     */
    function activateValidator(
        uint16 validatorId
    ) external onlyRole(ADMIN_ROLE) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();

        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }

        ValidatorInfo storage validator = $.validators[validatorId];
        validator.active = true;

        emit ValidatorActivated(validatorId);
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
     * @notice Add a staker to a validator's staker list
     * @param staker Address of the staker
     * @param validatorId ID of the validator
     */
    function _addStakerToValidator(address staker, uint16 validatorId) internal {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();

        // Add validator to user's validator list if not already there
        if (!$.userHasStakedWithValidator[staker][validatorId]) {
            $.userValidators[staker].push(validatorId);
            $.userHasStakedWithValidator[staker][validatorId] = true;
        }

        // Add user to validator's staker list if not already there
        if (!$.isStakerForValidator[validatorId][staker]) {
            $.validatorStakers[validatorId].push(staker);
            $.isStakerForValidator[validatorId][staker] = true;
        }

        // Also add to global stakers list if not already there
        _addStakerIfNew(staker);
    }

    /**
     * @notice Update rewards for a user on a specific validator
     * @param user Address of the user
     * @param validatorId ID of the validator
     */
    function _updateRewardsForValidator(address user, uint16 validatorId) internal {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        address[] memory rewardTokens = $.rewardTokens;

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];

            // Update reward per token for this validator
            _updateRewardPerTokenForValidator(token, validatorId);

            if (user != address(0)) {
                // Calculate user's earned rewards from this validator
                uint256 oldReward = $.userRewards[user][validatorId][token];
                uint256 newReward =
                    _earnedFromValidator(user, token, validatorId, $.userValidatorStakes[user][validatorId].staked);

                // Update user's reward for this token and validator
                $.userRewards[user][validatorId][token] = newReward;
                $.userRewardPerTokenPaid[user][validatorId][token] =
                    $.validatorRewardPerTokenCumulative[validatorId][token];

                // Calculate validator commission
                ValidatorInfo storage validator = $.validators[validatorId];
                if (newReward > oldReward && validator.commission > 0) {
                    uint256 rewardDelta = newReward - oldReward;
                    uint256 commissionAmount = (rewardDelta * validator.commission) / REWARD_PRECISION;
                    $.validatorAccruedCommission[validatorId][token] += commissionAmount;
                }
            }
        }
    }

    /**
     * @notice Update the reward per token value for a specific validator
     * @param token The address of the reward token
     * @param validatorId The ID of the validator
     */
    function _updateRewardPerTokenForValidator(address token, uint16 validatorId) internal {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();

        if ($.validatorTotalStaked[validatorId] > 0) {
            uint256 timeDelta = block.timestamp - $.validatorLastUpdateTimes[validatorId][token];
            if (timeDelta > 0 && $.rewardRates[token] > 0) {
                uint256 reward =
                    (timeDelta * $.rewardRates[token] * REWARD_PRECISION) / $.validatorTotalStaked[validatorId];
                $.validatorRewardPerTokenCumulative[validatorId][token] += reward;
            }
        }

        $.validatorLastUpdateTimes[validatorId][token] = block.timestamp;
    }

    /**
     * @notice Calculate the earned rewards for a user from a specific validator
     * @param user The address of the user
     * @param token The address of the token
     * @param validatorId The ID of the validator
     * @param userStakedAmount The amount staked by the user to this validator
     * @return rewards The earned rewards
     */
    function _earnedFromValidator(
        address user,
        address token,
        uint16 validatorId,
        uint256 userStakedAmount
    ) internal view returns (uint256 rewards) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();

        uint256 rewardPerToken = $.validatorRewardPerTokenCumulative[validatorId][token];

        // If there are currently staked tokens, add the rewards since last update
        if ($.validatorTotalStaked[validatorId] > 0) {
            uint256 timeDelta = block.timestamp - $.validatorLastUpdateTimes[validatorId][token];
            if (timeDelta > 0 && $.rewardRates[token] > 0) {
                rewardPerToken +=
                    (timeDelta * $.rewardRates[token] * REWARD_PRECISION) / $.validatorTotalStaked[validatorId];
            }
        }

        // Get validator commission as a decimal (divide by REWARD_PRECISION)
        uint256 validatorCommission = $.validators[validatorId].commission;

        // Calculate reward with commission deducted
        uint256 fullReward = (userStakedAmount * (rewardPerToken - $.userRewardPerTokenPaid[user][validatorId][token]))
            / REWARD_PRECISION;
        uint256 commission = (fullReward * validatorCommission) / REWARD_PRECISION;

        return $.userRewards[user][validatorId][token] + (fullReward - commission);
    }

    /**
     * @notice Update rewards for all stakers of a validator
     * @param validatorId ID of the validator
     */
    function _updateRewardsForAllValidatorStakers(
        uint16 validatorId
    ) internal {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        address[] memory stakers = $.validatorStakers[validatorId];

        for (uint256 i = 0; i < stakers.length; i++) {
            _updateRewardsForValidator(stakers[i], validatorId);
        }
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
     * @param token Address of the token to withdraw (use PLUME for native tokens)
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

        // For native token (PLUME)
        if (token == PLUME) {
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
     * @notice Returns the amount of PLUME currently in cooling period for the caller
     * @return amount Amount of PLUME in cooling period, returns 0 if cooldown period has passed
     */
    function amountCoolingOf(
        address user
    ) external view returns (uint256 amount) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        StakeInfo storage info = $.stakeInfo[user];

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

    /**
     * @notice Emitted when tokens complete cooldown and are moved to withdrawable state
     * @param user Address of the user
     * @param amount Amount of PLUME moved from cooling to withdrawable
     */
    event CoolingCompleted(address indexed user, uint256 amount);

}
