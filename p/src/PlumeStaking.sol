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
        /// @dev Rate of $pUSD rewarded per $PLUME staked per second, scaled by _BASE
        uint256 perSecondRewardRate;
        /// @dev Amount of $PLUME deposited but not staked by each user
        mapping(address user => uint256 amount) parked;
        /// @dev Amount of $PLUME that are in cooldown (unstaked but not yet withdrawable)
        mapping(address user => uint256 amount) cooled;
        /// @dev Timestamp at which the cooldown period ends when the user is unstaking
        mapping(address user => uint256 timestamp) cooldownEnd;
        /// @dev Detailed active stake info for each user
        mapping(address user => StakeInfo info) stakeInfo;
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
        uint256 amount;
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
     * @param perSecondRewardRate Rate of $pUSD rewarded per $PLUME staked per second, scaled by _BASE
     */
    event SetPerSecondRewardRate(uint256 perSecondRewardRate);

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

    // Errors

    /**
     * @notice Indicates a failure because the amount is invalid
     * @param amount Amount of $PLUME requested
     * @param minStakeAmount Minimum amount of $PLUME allowed
     */
    error InvalidAmount(uint256 amount, uint256 minStakeAmount);

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
        $.cooldownInterval = 7 days;
        $.perSecondRewardRate = 1e18 * 0.05 * 0.12;

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
     * @param perSecondRewardRate_ Rate of $pUSD rewarded per $PLUME staked per second, scaled by _BASE
     */
    function setPerSecondRewardRate(
        uint256 perSecondRewardRate_
    ) external onlyRole(ADMIN_ROLE) nonReentrant {
        _getPlumeStakingStorage().perSecondRewardRate = perSecondRewardRate_;
        emit SetPerSecondRewardRate(perSecondRewardRate_);
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

        SafeERC20.safeTransferFrom($.plume, msg.sender, address(this), amount);
        $.parked[msg.sender] += amount;

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
        if ($.cooldownEnd[msg.sender] > block.timestamp) {
            revert CooldownPeriodNotEnded($.cooldownEnd[msg.sender]);
        }
        if (amount < $.minStakeAmount) {
            revert InvalidAmount(amount, $.minStakeAmount);
        }
        if ($.parked[msg.sender] < amount) {
            revert InsufficientBalance(amount, $.parked[msg.sender]);
        }

        $.parked[msg.sender] -= amount;
        $.staked[msg.sender] += amount;

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
        if ($.cooldownEnd[msg.sender] > block.timestamp) {
            revert CooldownPeriodNotEnded($.cooldownEnd[msg.sender]);
        }
        if (amount < $.minStakeAmount) {
            revert InvalidAmount(amount, $.minStakeAmount);
        }

        SafeERC20.safeTransferFrom($.plume, msg.sender, address(this), amount);
        $.staked[msg.sender] += amount;

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

        amount = $.staked[msg.sender];
        $.staked[msg.sender] = 0;
        $.cooled[msg.sender] += amount;
        $.cooldownEnd[msg.sender] = block.timestamp + $.cooldownInterval;

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
    function claimPlume(
        uint256 amount
    ) external nonReentrant {
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
    function claimStable(
        uint256 amount
    ) external nonReentrant {
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

    /// @notice Cooldown interval for staked assets to be unlocked and parked
    function cooldownInterval() external view returns (uint256) {
        return _getPlumeStakingStorage().cooldownInterval;
    }

    /// @notice Rate of $pUSD rewarded per $PLUME staked per second, scaled by _BASE
    function perSecondRewardRate() external view returns (uint256) {
        return _getPlumeStakingStorage().perSecondRewardRate;
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
     * @notice Amount of $PLUME staked by a user
     * @param user Address of the user
     * @return amount Amount of $PLUME staked by the user
     */
    function staked(
        address user
    ) external view returns (uint256) {
        return _getPlumeStakingStorage().staked[user];
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
     * @notice Amount of $PLUME awaiting cooldown by a user
     * @param user Address of the user
     * @return amount Amount of $PLUME awaiting cooldown by the user
     */
    function cooled(
        address user
    ) external view returns (uint256) {
        return _getPlumeStakingStorage().cooled[user];
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
     * @notice Withdrawable balance of a user
     * @param user Address of the user
     * @return amount Amount of $PLUME available to unpark
     */
    function withdrawableBalance(
        address user
    ) external view returns (uint256 amount) {
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
    function claimablePlumeBalance(
        address user
    ) public view returns (uint256 amount) {
        amount = _getPlumeStakingStorage().claimablePlume[user];
        // TODO additional calculation here
    }

    /**
     * @notice Claimable $pUSD balance of a user
     * @param user Address of the user
     * @return amount Amount of $pUSD available to claim
     */
    function claimableStableBalance(
        address user
    ) public view returns (uint256 amount) {
        amount = _getPlumeStakingStorage().claimableStable[user];
        // TODO additional calculation here
    }

}
