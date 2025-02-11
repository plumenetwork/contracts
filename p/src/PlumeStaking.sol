// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { Plume } from "./Plume.sol";

/**
 * @title PlumeStaking
 * @author Eugene Y. Q. Shen
 * @notice Staking contract for $PLUME
 */
contract PlumeStaking is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{

    // Storage

    /// @custom:storage-location erc7201:plume.storage.PlumeStaking
    struct PlumeStakingStorage {
        /// @dev Address of the $PLUME token
        Plume plume;
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
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.PlumeStaking")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PLUME_STAKING_STORAGE_LOCATION =
        0x40f2ca4cf3a525ed9b1b2649f0f850db77540accc558be58ba47f8638359e800;

    function _getPlumeStakingStorage() internal pure returns (PlumeStakingStorage storage $) {
        assembly {
            $.slot := PLUME_STAKING_STORAGE_LOCATION
        }
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
    function initialize(
        address owner,
        address plume_
    ) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        $.plume = Plume(plume_);
        $.minStakeAmount = 1e18;
        $.maxStakeInterval = 365 * 4 + 1 days;
        $.cooldownInterval = 7 days;

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

    // User Functions

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
     * @notice Stake $PLUME in the contract
     * @dev TODO unlockTime == 0 for auto-extending staking
     * @param amount Amount of $PLUME to stake
     * @param timestamp Timestamp at which the assets at stake unlock
     */
    function stake(uint256 amount, uint256 timestamp) external {
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

        emit Staked(msg.sender, amount, timestamp);
    }

    /**
     * @notice Park and stake $PLUME in the contract
     * @dev TODO unlockTime == 0 for auto-extending staking
     * @param amount Amount of $PLUME to park and stake
     * @param timestamp Timestamp at which the assets at stake unlock
     */
    function parkAndStake(uint256 amount, uint256 timestamp) external {
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

        emit Parked(msg.sender, amount);
        emit Staked(msg.sender, amount, timestamp);
    }

    /**
     * @notice Extend the unlock time for the staked assets
     * @param timestamp New timestamp at which the assets at stake unlock
     */
    function extendTime(uint256 timestamp) external {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        if ($.cooldownEnd[msg.sender] > block.timestamp) {
            revert CooldownPeriodNotEnded($.cooldownEnd[msg.sender]);
        }
        if (timestamp <= $.unlockTime[msg.sender] || timestamp > $.unlockTime[msg.sender] + $.maxStakeInterval) {
            revert InvalidUnlockTime();
        }

        $.unlockTime[msg.sender] = timestamp;

        emit ExtendedTime(msg.sender, timestamp);
    }

    /**
     * @notice Unstake $PLUME from the contract
     * @return amount Amount of $PLUME unstaked
     * @dev TODO for current prototype, the implementation is limited because:
     *   - you cannot set the amount that you unstake; it all unstakes at once
     *   - you cannot stake again until after the cooldown period ends
     */
    function unstake() external returns (uint256 amount) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        if ($.unlockTime[msg.sender] > block.timestamp) {
            revert NotUnlocked();
        }

        amount = $.staked[msg.sender];
        $.staked[msg.sender] = 0;
        $.cooled[msg.sender] += amount;
        $.unlockTime[msg.sender] = 0;
        $.cooldownEnd[msg.sender] = block.timestamp + $.cooldownInterval;

        emit Unstaked(msg.sender, amount);
    }

    /**
     * @notice Unpark $PLUME from the contract
     * @param amount Amount of $PLUME to unpark
     */
    function unpark(uint256 amount) external {
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

    // View Functions

    /// @notice Address of the $PLUME token
    function plume() public view returns (Plume) {
        return _getPlumeStakingStorage().plume;
    }

    /// @notice Minimum amount of $PLUME that can be staked
    function minStakeAmount() public view returns (uint256) {
        return _getPlumeStakingStorage().minStakeAmount;
    }

    /// @notice Maximum interval for which assets can be staked for
    function maxStakeInterval() public view returns (uint256) {
        return _getPlumeStakingStorage().maxStakeInterval;
    }

    /// @notice Cooldown interval for staked assets to be unlocked and parked
    function cooldownInterval() public view returns (uint256) {
        return _getPlumeStakingStorage().cooldownInterval;
    }

    /**
     * @notice Amount of $PLUME staked by a user
     * @param user Address of the user
     * @return amount Amount of $PLUME staked by the user
     */
    function staked(address user) public view returns (uint256) {
        return _getPlumeStakingStorage().staked[user];
    }

    /**
     * @notice Amount of $PLUME parked by a user
     * @param user Address of the user
     * @return amount Amount of $PLUME parked by the user
     */
    function parked(address user) public view returns (uint256) {
        return _getPlumeStakingStorage().parked[user];
    }

    /**
     * @notice Amount of $PLUME awaiting cooldown by a user
     * @param user Address of the user
     * @return amount Amount of $PLUME awaiting cooldown by the user
     */
    function cooled(address user) public view returns (uint256) {
        return _getPlumeStakingStorage().cooled[user];
    }

    /**
     * @notice Timestamp at which the assets at stake unlock for a user
     * @param user Address of the user
     * @return timestamp Timestamp at which the assets at stake unlock
     */
    function unlockTime(address user) public view returns (uint256) {
        return _getPlumeStakingStorage().unlockTime[user];
    }

    /**
     * @notice Timestamp at which the cooldown period ends when the user is unstaking
     * @param user Address of the user
     * @return timestamp Timestamp at which the cooldown period ends
     */
    function cooldownEnd(address user) public view returns (uint256) {
        return _getPlumeStakingStorage().cooldownEnd[user];
    }

    /**
     * @notice Withdrawable balance of a user
     * @param user Address of the user
     * @return amount Amount of $PLUME available to unpark
     */
    function withdrawableBalance(address user) public view returns (uint256 amount) {
        PlumeStakingStorage storage $ = _getPlumeStakingStorage();
        amount = $.parked[user];
        if ($.cooled[user] > 0 && $.cooldownEnd[user] >= block.timestamp) {
            amount += $.cooled[user];
        }
    }
}
