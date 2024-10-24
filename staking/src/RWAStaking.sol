// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title RWAStaking
 * @author Eugene Y. Q. Shen
 * @notice Pre-staking contract for RWA Staking on Plume
 */
contract RWAStaking is AccessControlUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {

    // Types

    using SafeERC20 for IERC20;

    /**
     * @notice State of a user that deposits into the RWAStaking contract
     * @param amountSeconds Cumulative sum of the amount of stablecoins staked by the user,
     *   multiplied by the number of seconds that the user has staked this amount for
     * @param amountStaked Total amount of stablecoins staked by the user
     * @param lastUpdate Timestamp of the most recent update to amountSeconds
     */
    struct UserState {
        uint256 amountSeconds;
        uint256 amountStaked;
        uint256 lastUpdate;
    }

    // Storage

    /// @custom:storage-location erc7201:plume.storage.RWAStaking
    struct RWAStakingStorage {
        /// @dev Total amount of stablecoins staked in the RWAStaking contract
        uint256 totalAmountStaked;
        /// @dev List of users who have staked into the RWAStaking contract
        address[] users;
        /// @dev Mapping of users to their state in the RWAStaking contract
        mapping(address user => UserState userState) userStates;
        /// @dev List of stablecoins allowed to be staked in the RWAStaking contract
        IERC20[] stablecoins;
        /// @dev Mapping of stablecoins to whether they are allowed to be staked
        mapping(IERC20 stablecoin => bool allowed) allowedStablecoins;
        /// @dev Timestamp of when pre-staking ends, when the admin withdraws all stablecoins
        uint256 endTime;
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.RWAStaking")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant RWA_STAKING_STORAGE_LOCATION =
        0x985cf34339f517022bb48b1ce402d8af12b040d0d5b3c991a00533cf3bab8800;

    function _getRWAStakingStorage() private pure returns (RWAStakingStorage storage $) {
        assembly {
            $.slot := RWA_STAKING_STORAGE_LOCATION
        }
    }

    // Constants

    /// @notice Role for the admin of the RWAStaking contract
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @notice Role for the upgrader of the RWAStaking contract
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // Events

    /**
     * @notice Emitted when an admin withdraws stablecoins from the RWAStaking contract
     * @param user Address of the admin who withdrew stablecoins
     * @param stablecoin Stablecoin token contract address
     * @param amount Amount of stablecoins withdrawn
     */
    event AdminWithdrawn(address indexed user, IERC20 indexed stablecoin, uint256 amount);

    /**
     * @notice Emitted when a user withdraws stablecoins from the RWAStaking contract
     * @param user Address of the user who withdrew stablecoins
     * @param stablecoin Stablecoin token contract address
     * @param amount Amount of stablecoins withdrawn
     */
    event Withdrawn(address indexed user, IERC20 indexed stablecoin, uint256 amount);

    /**
     * @notice Emitted when a user stakes stablecoins into the RWAStaking contract
     * @param user Address of the user who staked stablecoins
     * @param stablecoin Stablecoin token contract address
     * @param amount Amount of stablecoins staked
     */
    event Staked(address indexed user, IERC20 indexed stablecoin, uint256 amount);

    // Errors

    /// @notice Indicates a failure because the pre-staking period has ended
    error StakingEnded();

    /**
     * @notice Indicates a failure because the stablecoin is already allowed to be staked
     * @param stablecoin Stablecoin token contract address
     */
    error AlreadyAllowedStablecoin(IERC20 stablecoin);

    /**
     * @notice Indicates a failure because the stablecoin is not allowed to be staked
     * @param stablecoin Stablecoin token contract address
     */
    error NotAllowedStablecoin(IERC20 stablecoin);

    /**
     * @notice Indicates a failure because the user does not have enough stablecoins staked
     * @param user Address of the user who does not have enough stablecoins staked
     * @param stablecoin Stablecoin token contract address
     * @param amount Amount of stablecoins that the user wants to withdraw
     * @param amountStaked Amount of stablecoins that the user has staked
     */
    error InsufficientStaked(address user, IERC20 stablecoin, uint256 amount, uint256 amountStaked);

    // Initializer

    /**
     * @notice Prevent the implementation contract from being initialized or reinitialized
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the RWAStaking contract
     * @param owner Address of the owner of the RWAStaking contract
     */
    function initialize(
        address owner
    ) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

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
     * @notice Allow a stablecoin to be staked into the RWAStaking contract
     * @dev This function can only be called by an admin
     * @param stablecoin Stablecoin token contract address
     */
    function allowStablecoin(
        IERC20 stablecoin
    ) external onlyRole(ADMIN_ROLE) {
        RWAStakingStorage storage $ = _getRWAStakingStorage();
        if ($.allowedStablecoins[stablecoin]) {
            revert AlreadyAllowedStablecoin(stablecoin);
        }
        $.stablecoins.push(stablecoin);
        $.allowedStablecoins[stablecoin] = true;
    }

    /**
     * @notice Stop the RWAStaking contract by withdrawing all stablecoins
     * @dev Only the admin can withdraw stablecoins from the RWAStaking contract
     */
    function adminWithdraw() external onlyRole(ADMIN_ROLE) {
        RWAStakingStorage storage $ = _getRWAStakingStorage();
        if ($.endTime != 0) {
            revert StakingEnded();
        }

        IERC20[] storage stablecoins = $.stablecoins;
        uint256 length = stablecoins.length;
        for (uint256 i = 0; i < length; ++i) {
            IERC20 stablecoin = stablecoins[i];
            uint256 amount = stablecoin.balanceOf(address(this));
            stablecoin.safeTransfer(msg.sender, amount);
            emit AdminWithdrawn(msg.sender, stablecoin, amount);
        }
        $.endTime = block.timestamp;
    }

    // User Functions

    /**
     * @notice Stake stablecoins into the RWAStaking contract
     * @param amount Amount of stablecoins to stake
     * @param stablecoin Stablecoin token contract address
     */
    function stake(uint256 amount, IERC20 stablecoin) external nonReentrant {
        RWAStakingStorage storage $ = _getRWAStakingStorage();
        if ($.endTime != 0) {
            revert StakingEnded();
        }
        if (!$.allowedStablecoins[stablecoin]) {
            revert NotAllowedStablecoin(stablecoin);
        }

        uint256 previousBalance = stablecoin.balanceOf(address(this));

        stablecoin.safeTransferFrom(msg.sender, address(this), amount);

        uint256 newBalance = stablecoin.balanceOf(address(this));
        uint256 actualAmount = newBalance - previousBalance;

        uint256 timestamp = block.timestamp;
        UserState storage userState = $.userStates[msg.sender];
        if (userState.lastUpdate == 0) {
            $.users.push(msg.sender);
        }
        userState.amountSeconds += userState.amountStaked * (timestamp - userState.lastUpdate);
        userState.amountStaked += actualAmount;
        userState.lastUpdate = timestamp;
        $.totalAmountStaked += actualAmount;

        emit Staked(msg.sender, stablecoin, actualAmount);
    }

    /**
     * @notice Withdraw stablecoins from the RWAStaking contract
     * @param amount Amount of stablecoins to withdraw
     * @param stablecoin Stablecoin token contract address
     */
    function withdraw(uint256 amount, IERC20 stablecoin) external nonReentrant {
        RWAStakingStorage storage $ = _getRWAStakingStorage();
        if ($.endTime != 0) {
            revert StakingEnded();
        }

        uint256 timestamp = block.timestamp;
        UserState storage userState = $.userStates[msg.sender];
        if (userState.amountStaked < amount) {
            revert InsufficientStaked(msg.sender, stablecoin, amount, userState.amountStaked);
        }

        userState.amountSeconds += userState.amountStaked * (timestamp - userState.lastUpdate);
        uint256 previousBalance = stablecoin.balanceOf(address(this));
        stablecoin.safeTransfer(msg.sender, amount);
        uint256 newBalance = stablecoin.balanceOf(address(this));
        uint256 actualAmount = previousBalance - newBalance;

        userState.amountSeconds -= userState.amountSeconds * actualAmount / userState.amountStaked;
        userState.amountStaked -= actualAmount;
        userState.lastUpdate = timestamp;
        $.totalAmountStaked -= actualAmount;

        emit Withdrawn(msg.sender, stablecoin, actualAmount);
    }

    // Getter View Functions

    /// @notice Total amount of stablecoins staked in the RWAStaking contract
    function getTotalAmountStaked() external view returns (uint256) {
        return _getRWAStakingStorage().totalAmountStaked;
    }

    /// @notice List of users who have staked into the RWAStaking contract
    function getUsers() external view returns (address[] memory) {
        return _getRWAStakingStorage().users;
    }

    /// @notice State of a user who has staked into the RWAStaking contract
    function getUserState(
        address user
    ) external view returns (uint256, uint256, uint256) {
        RWAStakingStorage storage $ = _getRWAStakingStorage();
        UserState memory userState = $.userStates[user];
        return (
            userState.amountSeconds
                + userState.amountStaked * (($.endTime > 0 ? $.endTime : block.timestamp) - userState.lastUpdate),
            userState.amountStaked,
            userState.lastUpdate
        );
    }

    /// @notice List of stablecoins allowed to be staked in the RWAStaking contract
    function getAllowedStablecoins() external view returns (IERC20[] memory) {
        return _getRWAStakingStorage().stablecoins;
    }

    /// @notice Whether a stablecoin is allowed to be staked in the RWAStaking contract
    function isAllowedStablecoin(
        IERC20 stablecoin
    ) external view returns (bool) {
        return _getRWAStakingStorage().allowedStablecoins[stablecoin];
    }

    /// @notice Timestamp of when pre-staking ends, when the admin withdraws all stablecoins
    function getEndTime() external view returns (uint256) {
        return _getRWAStakingStorage().endTime;
    }

}
