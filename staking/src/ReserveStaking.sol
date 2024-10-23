// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ReserveStaking
 * @author Eugene Y. Q. Shen
 * @notice Pre-staking contract into the Plume Mainnet Reserve Fund
 */
contract ReserveStaking is AccessControlUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {

    // Types

    using SafeERC20 for IERC20;

    // Add minimum confirmations required for admin actions
    uint256 public constant MIN_CONFIRMATIONS = 3;

    // Add mapping for admin confirmations
    mapping(bytes32 => mapping(address => bool)) public adminConfirmations;
    mapping(bytes32 => uint256) public confirmationCount;
    mapping(bytes32 => bool) public isExecuted;

    // Track pending admin withdrawals
    struct PendingWithdrawal {
        uint256 sbtcAmount;
        uint256 stoneAmount;
        uint256 timestamp;
        bool executed;
    }

    mapping(bytes32 => PendingWithdrawal) public pendingWithdrawals;

    // Events for multisig operations
    event WithdrawalProposed(bytes32 indexed proposalId, address indexed proposer);
    event WithdrawalConfirmed(bytes32 indexed proposalId, address indexed confirmer);
    event WithdrawalExecuted(bytes32 indexed proposalId, address indexed executor);

    /**
     * @notice State of a user that deposits into the ReserveStaking contract
     * @param sbtcAmountSeconds Cumulative sum of the amount of SBTC staked by the user,
     *   multiplied by the number of seconds that the user has staked this amount for
     * @param sbtcAmountStaked Total amount of SBTC staked by the user
     * @param sbtcLastUpdate Timestamp of the most recent update to sbtcAmountSeconds
     * @param stoneAmountSeconds Cumulative sum of the amount of STONE staked by the user,
     *   multiplied by the number of seconds that the user has staked this amount for
     * @param stoneAmountStaked Total amount of STONE staked by the user
     * @param stoneLastUpdate Timestamp of the most recent update to stoneAmountSeconds
     */
    struct UserState {
        uint256 sbtcAmountSeconds;
        uint256 sbtcAmountStaked;
        uint256 sbtcLastUpdate;
        uint256 stoneAmountSeconds;
        uint256 stoneAmountStaked;
        uint256 stoneLastUpdate;
    }

    // Storage

    /// @custom:storage-location erc7201:plume.storage.ReserveStaking
    struct ReserveStakingStorage {
        /// @dev SBTC token contract address
        IERC20 sbtc;
        /// @dev STONE token contract address
        IERC20 stone;
        /// @dev Total amount of SBTC staked in the ReserveStaking contract
        uint256 sbtcTotalAmountStaked;
        /// @dev Total amount of STONE staked in the ReserveStaking contract
        uint256 stoneTotalAmountStaked;
        /// @dev List of users who have staked into the ReserveStaking contract
        address[] users;
        /// @dev Mapping of users to their state in the ReserveStaking contract
        mapping(address user => UserState userState) userStates;
        /// @dev Timestamp of when pre-staking ends, when the admin withdraws all SBTC and STONE
        uint256 endTime;
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.ReserveStaking")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant RESERVE_STAKING_STORAGE_LOCATION =
        0xa6cbc7710058576a270f67161d5bf15d0a5b41a0e20b4574e4fb07768a4d0c00;

    function _getReserveStakingStorage() private pure returns (ReserveStakingStorage storage $) {
        assembly {
            $.slot := RESERVE_STAKING_STORAGE_LOCATION
        }
    }

    // Constants

    /// @notice Role for the admin of the ReserveStaking contract
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @notice Role for the upgrader of the ReserveStaking contract
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // Events

    /**
     * @notice Emitted when an admin withdraws SBTC and STONE from the ReserveStaking contract
     * @param user Address of the admin who withdrew stablecoins
     * @param sbtcAmount Amount of SBTC withdrawn
     * @param stoneAmount Amount of STONE withdrawn
     */
    event AdminWithdrawn(address indexed user, uint256 sbtcAmount, uint256 stoneAmount);

    /**
     * @notice Emitted when a user withdraws SBTC and STONE from the ReserveStaking contract
     * @param user Address of the user who withdrew stablecoins
     * @param sbtcAmount Amount of SBTC withdrawn
     * @param stoneAmount Amount of STONE withdrawn
     */
    event Withdrawn(address indexed user, uint256 sbtcAmount, uint256 stoneAmount);

    /**
     * @notice Emitted when a user stakes SBTC into the ReserveStaking contract
     * @param user Address of the user who staked SBTC
     * @param sbtcAmount Amount of SBTC staked
     * @param stoneAmount Amount of STONE staked
     */
    event Staked(address indexed user, uint256 sbtcAmount, uint256 stoneAmount);

    // Events for multisig operations
    event WithdrawalProposed(bytes32 indexed proposalId, address indexed proposer);
    event WithdrawalConfirmed(bytes32 indexed proposalId, address indexed confirmer);
    event WithdrawalExecuted(bytes32 indexed proposalId, address indexed executor);

    // Errors

    /// @notice Indicates a failure because the pre-staking period has ended
    error StakingEnded();

    /**
     * @notice Indicates a failure because the user does not have enough SBTC or STONE staked
     * @param user Address of the user who does not have enough SBTC or STONE staked
     * @param sbtcAmount Amount of SBTC that the user does not have enough of
     * @param stoneAmount Amount of STONE that the user does not have enough of
     * @param sbtcAmountStaked Amount of SBTC that the user has staked
     * @param stoneAmountStaked Amount of STONE that the user has staked
     */
    error InsufficientStaked(
        address user, uint256 sbtcAmount, uint256 stoneAmount, uint256 sbtcAmountStaked, uint256 stoneAmountStaked
    );

    // Initializer

    /**
     * @notice Prevent the implementation contract from being initialized or reinitialized
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the ReserveStaking contract
     * @param owner Address of the owner of the ReserveStaking contract
     * @param sbtc SBTC token contract address
     * @param stone STONE token contract address
     */
    function initialize(address owner, IERC20 sbtc, IERC20 stone) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(ADMIN_ROLE, owner);
        _grantRole(UPGRADER_ROLE, owner);

        _getReserveStakingStorage().sbtc = sbtc;
        _getReserveStakingStorage().stone = stone;
    }

    // Override Functions

    /**
     * @notice Revert when `msg.sender` is not authorized to upgrade the contract
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) { }

    // Admin Functions

    /**
     * @notice Stop the ReserveStaking contract by withdrawing all SBTC and STONE
     * @dev Only the admin can withdraw SBTC and STONE from the ReserveStaking contract
     */
    // Modify adminWithdraw to use multisig
    function proposeAdminWithdraw() external onlyRole(ADMIN_ROLE) {
        ReserveStakingStorage storage $ = _getReserveStakingStorage();
        if ($.endTime != 0) {
            revert StakingEnded();
        }

        bytes32 proposalId = keccak256(abi.encodePacked("withdraw", block.timestamp, msg.sender));

        uint256 sbtcAmount = $.sbtc.balanceOf(address(this));
        uint256 stoneAmount = $.stone.balanceOf(address(this));

        pendingWithdrawals[proposalId] = PendingWithdrawal({
            sbtcAmount: sbtcAmount,
            stoneAmount: stoneAmount,
            timestamp: block.timestamp,
            executed: false
        });

        adminConfirmations[proposalId][msg.sender] = true;
        confirmationCount[proposalId] = 1;

        emit WithdrawalProposed(proposalId, msg.sender);
    }

    function confirmAdminWithdraw(bytes32 proposalId) external onlyRole(ADMIN_ROLE) {
        require(!adminConfirmations[proposalId][msg.sender], "Already confirmed");
        require(!isExecuted[proposalId], "Already executed");
        require(pendingWithdrawals[proposalId].timestamp != 0, "Invalid proposal");

        adminConfirmations[proposalId][msg.sender] = true;
        confirmationCount[proposalId] += 1;

        emit WithdrawalConfirmed(proposalId, msg.sender);
    }

    function executeAdminWithdraw(bytes32 proposalId) external onlyRole(ADMIN_ROLE) nonReentrant {
        require(confirmationCount[proposalId] >= MIN_CONFIRMATIONS, "Insufficient confirmations");
        require(!isExecuted[proposalId], "Already executed");

        ReserveStakingStorage storage $ = _getReserveStakingStorage();
        PendingWithdrawal storage withdrawal = pendingWithdrawals[proposalId];

        $.sbtc.safeTransfer(msg.sender, withdrawal.sbtcAmount);
        $.stone.safeTransfer(msg.sender, withdrawal.stoneAmount);
        $.endTime = block.timestamp;

        isExecuted[proposalId] = true;
        withdrawal.executed = true;

        emit WithdrawalExecuted(proposalId, msg.sender);
        emit AdminWithdrawn(msg.sender, withdrawal.sbtcAmount, withdrawal.stoneAmount);
    }

    // User Functions

    /**
     * @notice Stake SBTC and STONE into the ReserveStaking contract
     * @param sbtcAmount Amount of SBTC to stake
     * @param stoneAmount Amount of STONE to stake
     */
    function stake(uint256 sbtcAmount, uint256 stoneAmount) external {
        ReserveStakingStorage storage $ = _getReserveStakingStorage();
        if ($.endTime != 0) {
            revert StakingEnded();
        }

        uint256 timestamp = block.timestamp;
        UserState storage userState = $.userStates[msg.sender];
        if (userState.sbtcLastUpdate == 0 && userState.stoneLastUpdate == 0) {
            $.users.push(msg.sender);
        }

        uint256 actualSbtcAmount;
        uint256 actualStoneAmount;

        if (sbtcAmount > 0) {
            IERC20 sbtc = $.sbtc;
            uint256 previousBalance = sbtc.balanceOf(address(this));
            sbtc.safeTransferFrom(msg.sender, address(this), sbtcAmount);
            uint256 newBalance = sbtc.balanceOf(address(this));
            actualSbtcAmount = newBalance - previousBalance;
            userState.sbtcAmountSeconds += userState.sbtcAmountStaked * (timestamp - userState.sbtcLastUpdate);
            userState.sbtcAmountStaked += actualSbtcAmount;
            userState.sbtcLastUpdate = timestamp;
            $.sbtcTotalAmountStaked += actualSbtcAmount;
        }

        if (stoneAmount > 0) {
            IERC20 stone = $.stone;
            uint256 previousBalance = stone.balanceOf(address(this));
            stone.safeTransferFrom(msg.sender, address(this), stoneAmount);
            uint256 newBalance = stone.balanceOf(address(this));
            actualStoneAmount = newBalance - previousBalance;
            userState.stoneAmountSeconds += userState.stoneAmountStaked * (timestamp - userState.stoneLastUpdate);
            userState.stoneAmountStaked += stoneAmount;
            userState.stoneLastUpdate = timestamp;
            $.stoneTotalAmountStaked += stoneAmount;
        }

        emit Staked(msg.sender, actualSbtcAmount, actualStoneAmount);
    }

    /**
     * @notice Withdraw SBTC and STONE from the ReserveStaking contract and lose points
     * @param sbtcAmount Amount of SBTC to withdraw
     * @param stoneAmount Amount of STONE to withdraw
     */
    function withdraw(uint256 sbtcAmount, uint256 stoneAmount) external nonReentrant {
        ReserveStakingStorage storage $ = _getReserveStakingStorage();
        if ($.endTime != 0) {
            revert StakingEnded();
        }

        uint256 timestamp = block.timestamp;
        UserState storage userState = $.userStates[msg.sender];
        if (userState.sbtcAmountStaked < sbtcAmount || userState.stoneAmountStaked < stoneAmount) {
            revert InsufficientStaked(
                msg.sender, sbtcAmount, stoneAmount, userState.sbtcAmountStaked, userState.stoneAmountStaked
            );
        }

        if (sbtcAmount > 0) {
            IERC20 sbtc = $.sbtc;
            // Update state before transfer
            userState.sbtcAmountSeconds += userState.sbtcAmountStaked * (timestamp - userState.sbtcLastUpdate);
            userState.sbtcAmountSeconds -= userState.sbtcAmountSeconds * sbtcAmount / userState.sbtcAmountStaked;
            userState.sbtcAmountStaked -= sbtcAmount;
            userState.sbtcLastUpdate = timestamp;
            $.sbtcTotalAmountStaked -= sbtcAmount;

            // Perform transfer after state updates
            sbtc.safeTransfer(msg.sender, sbtcAmount);
        }

        if (stoneAmount > 0) {
            IERC20 stone = $.stone;
            // Update state before transfer
            userState.stoneAmountSeconds += userState.stoneAmountStaked * (timestamp - userState.stoneLastUpdate);
            userState.stoneAmountSeconds -= userState.stoneAmountSeconds * stoneAmount / userState.stoneAmountStaked;
            userState.stoneAmountStaked -= stoneAmount;
            userState.stoneLastUpdate = timestamp;
            $.stoneTotalAmountStaked -= stoneAmount;

            // Perform transfer after state updates
            stone.safeTransfer(msg.sender, stoneAmount);
        }

        emit Withdrawn(msg.sender, sbtcAmount, stoneAmount);
    }

    // Getter View Functions

    /// @notice SBTC token contract address
    function getSBTC() external view returns (IERC20) {
        return _getReserveStakingStorage().sbtc;
    }

    /// @notice STONE token contract address
    function getSTONE() external view returns (IERC20) {
        return _getReserveStakingStorage().stone;
    }

    /// @notice Total amount of SBTC staked in the ReserveStaking contract
    function getSBTCTotalAmountStaked() external view returns (uint256) {
        return _getReserveStakingStorage().sbtcTotalAmountStaked;
    }

    /// @notice Total amount of STONE staked in the ReserveStaking contract
    function getSTONETotalAmountStaked() external view returns (uint256) {
        return _getReserveStakingStorage().stoneTotalAmountStaked;
    }

    /// @notice List of users who have staked into the ReserveStaking contract
    function getUsers() external view returns (address[] memory) {
        return _getReserveStakingStorage().users;
    }

    /// @notice State of a user who has staked into the ReserveStaking contract
    function getUserState(address user) external view returns (uint256, uint256, uint256, uint256, uint256, uint256) {
        ReserveStakingStorage storage $ = _getReserveStakingStorage();
        UserState memory userState = $.userStates[user];
        return (
            userState.sbtcAmountSeconds
                + userState.sbtcAmountStaked * (($.endTime > 0 ? $.endTime : block.timestamp) - userState.sbtcLastUpdate),
            userState.sbtcAmountStaked,
            userState.sbtcLastUpdate,
            userState.stoneAmountSeconds
                + userState.stoneAmountStaked * (($.endTime > 0 ? $.endTime : block.timestamp) - userState.stoneLastUpdate),
            userState.stoneAmountStaked,
            userState.stoneLastUpdate
        );
    }

    /// @notice Timestamp of when pre-staking ends, when the admin withdraws all SBTC
    function getEndTime() external view returns (uint256) {
        return _getReserveStakingStorage().endTime;
    }

}
