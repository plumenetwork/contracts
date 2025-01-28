// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { BridgeData, ITeller } from "./interfaces/ITeller.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
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
        /// @dev True if the ReserveStaking contract is paused for deposits, false otherwise
        bool paused;
        /// @dev Multisig address that withdraws the tokens and proposes/executes Timelock transactions
        address multisig;
        /// @dev Timelock contract address
        TimelockController timelock;
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

    /// @notice Emitted when the ReserveStaking contract is paused for deposits
    event Paused();

    /// @notice Emitted when the ReserveStaking contract is unpaused for deposits
    event Unpaused();

    // Errors

    /**
     * @notice Indicates a failure because the sender is not authorized to perform the action
     * @param sender Address of the sender that is not authorized
     * @param authorizedUser Address of the authorized user who can perform the action
     */
    error Unauthorized(address sender, address authorizedUser);

    /// @notice Indicates a failure because the contract is paused for deposits
    error DepositPaused();

    /// @notice Indicates a failure because the contract is already paused for deposits
    error AlreadyPaused();

    /// @notice Indicates a failure because the contract is not paused for deposits
    error NotPaused();

    /// @notice Indicates a failure because the pre-staking period has ended
    error StakingEnded();

    /**
     * @notice Indicates a failure because the user does not have enough SBTC or STONE staked
     * @param user Address of the user who does not have enough SBTC or STONE staked
     * @param sbtcAmount Amount of SBTC that the user wants to withdraw
     * @param stoneAmount Amount of STONE that the user wants to withdraw
     * @param sbtcAmountStaked Amount of SBTC that the user has staked
     * @param stoneAmountStaked Amount of STONE that the user has staked
     */
    error InsufficientStaked(
        address user, uint256 sbtcAmount, uint256 stoneAmount, uint256 sbtcAmountStaked, uint256 stoneAmountStaked
    );

    // Modifiers

    /// @notice Only the timelock contract can call this function
    modifier onlyTimelock() {
        if (msg.sender != address(_getReserveStakingStorage().timelock)) {
            revert Unauthorized(msg.sender, address(_getReserveStakingStorage().timelock));
        }
        _;
    }

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
     * @param timelock Timelock contract address
     * @param owner Address of the owner of the ReserveStaking contract
     * @param sbtc SBTC token contract address
     * @param stone STONE token contract address
     */
    function initialize(TimelockController timelock, address owner, IERC20 sbtc, IERC20 stone) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(ADMIN_ROLE, owner);

        ReserveStakingStorage storage $ = _getReserveStakingStorage();
        $.sbtc = sbtc;
        $.stone = stone;
        $.multisig = owner;
        $.timelock = timelock;
    }

    /**
     * @notice Reinitialize the ReserveStaking contract by adding the timelock and multisig contract address
     * @param multisig Multisig contract address
     * @param timelock Timelock contract address
     */
    function reinitialize(address multisig, TimelockController timelock) public reinitializer(2) onlyRole(ADMIN_ROLE) {
        ReserveStakingStorage storage $ = _getReserveStakingStorage();
        $.multisig = multisig;
        $.timelock = timelock;
    }

    // Override Functions

    /**
     * @notice Revert when `msg.sender` is not authorized to upgrade the contract
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyTimelock { }

    // Admin Functions

    /**
     * @notice Set the multisig address
     * @param multisig Multisig address
     */
    function setMultisig(
        address multisig
    ) external nonReentrant onlyTimelock {
        _getReserveStakingStorage().multisig = multisig;
    }

    /**
     * @notice Stop the ReserveStaking contract by withdrawing all SBTC and STONE
     * @dev Only the admin can withdraw SBTC and STONE from the ReserveStaking contract
     */
    function adminWithdraw() external nonReentrant onlyTimelock {
        ReserveStakingStorage storage $ = _getReserveStakingStorage();
        if ($.endTime != 0) {
            revert StakingEnded();
        }

        uint256 sbtcAmount = $.sbtc.balanceOf(address(this));
        uint256 stoneAmount = $.stone.balanceOf(address(this));

        $.sbtc.safeTransfer($.multisig, sbtcAmount);
        $.stone.safeTransfer($.multisig, stoneAmount);
        $.endTime = block.timestamp;

        emit AdminWithdrawn($.multisig, sbtcAmount, stoneAmount);
    }

    /**
     * @notice Bridge SBTC and STONE to Plume mainnet through the Teller contract
     * @param teller Teller contract address
     * @param bridgeData Data required for bridging
     */
    function adminBridge(
        ITeller teller,
        BridgeData calldata bridgeData,
        address vault_
    ) external nonReentrant onlyTimelock {
        ReserveStakingStorage storage $ = _getReserveStakingStorage();
        if ($.endTime != 0) {
            revert StakingEnded();
        }

        // Bridge SBTC
        uint256 sbtcAmount = $.sbtc.balanceOf(address(this));
        if (sbtcAmount > 0) {
            $.sbtc.forceApprove(vault_, sbtcAmount);
            uint256 fee = teller.previewFee(sbtcAmount, bridgeData);
            teller.depositAndBridge{ value: fee }(ERC20(address($.sbtc)), sbtcAmount, sbtcAmount, bridgeData);
        }

        // Bridge STONE
        uint256 stoneAmount = $.stone.balanceOf(address(this));
        if (stoneAmount > 0) {
            $.stone.forceApprove(vault_, stoneAmount);
            uint256 fee = teller.previewFee(stoneAmount, bridgeData);
            teller.depositAndBridge{ value: fee }(ERC20(address($.stone)), stoneAmount, stoneAmount, bridgeData);
        }

        $.endTime = block.timestamp;
        emit AdminWithdrawn($.multisig, sbtcAmount, stoneAmount);
    }

    /**
     * @notice Pause the ReserveStaking contract for deposits
     * @dev Only the admin can pause the ReserveStaking contract for deposits
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        ReserveStakingStorage storage $ = _getReserveStakingStorage();
        if ($.paused) {
            revert AlreadyPaused();
        }
        $.paused = true;
        emit Paused();
    }

    /**
     * @notice Unpause the ReserveStaking contract for deposits
     * @dev Only the admin can unpause the ReserveStaking contract for deposits
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        ReserveStakingStorage storage $ = _getReserveStakingStorage();
        if (!$.paused) {
            revert NotPaused();
        }
        $.paused = false;
        emit Unpaused();
    }

    // User Functions

    /**
     * @notice Stake SBTC and STONE into the ReserveStaking contract
     * @param sbtcAmount Amount of SBTC to stake
     * @param stoneAmount Amount of STONE to stake
     */
    function stake(uint256 sbtcAmount, uint256 stoneAmount) external nonReentrant {
        ReserveStakingStorage storage $ = _getReserveStakingStorage();
        if ($.endTime != 0) {
            revert StakingEnded();
        }
        if ($.paused) {
            revert DepositPaused();
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

        uint256 actualSbtcAmount;
        uint256 actualStoneAmount;

        if (sbtcAmount > 0) {
            IERC20 sbtc = $.sbtc;
            userState.sbtcAmountSeconds += userState.sbtcAmountStaked * (timestamp - userState.sbtcLastUpdate);
            uint256 previousBalance = sbtc.balanceOf(address(this));
            sbtc.safeTransfer(msg.sender, sbtcAmount);
            uint256 newBalance = sbtc.balanceOf(address(this));
            actualSbtcAmount = previousBalance - newBalance;
            userState.sbtcAmountSeconds -= userState.sbtcAmountSeconds * actualSbtcAmount / userState.sbtcAmountStaked;
            userState.sbtcAmountStaked -= actualSbtcAmount;
            userState.sbtcLastUpdate = timestamp;
            $.sbtcTotalAmountStaked -= actualSbtcAmount;
        }

        if (stoneAmount > 0) {
            IERC20 stone = $.stone;
            userState.stoneAmountSeconds += userState.stoneAmountStaked * (timestamp - userState.stoneLastUpdate);
            uint256 previousBalance = stone.balanceOf(address(this));
            stone.safeTransfer(msg.sender, stoneAmount);
            uint256 newBalance = stone.balanceOf(address(this));
            actualStoneAmount = previousBalance - newBalance;
            userState.stoneAmountSeconds -=
                userState.stoneAmountSeconds * actualStoneAmount / userState.stoneAmountStaked;
            userState.stoneAmountStaked -= actualStoneAmount;
            userState.stoneLastUpdate = timestamp;
            $.stoneTotalAmountStaked -= actualStoneAmount;
        }

        emit Withdrawn(msg.sender, actualSbtcAmount, actualStoneAmount);
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
    function getUserState(
        address user
    ) external view returns (uint256, uint256, uint256, uint256, uint256, uint256) {
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

    /// @notice Returns true if the ReserveStaking contract is paused for deposits, otherwise false
    function isPaused() external view returns (bool) {
        return _getReserveStakingStorage().paused;
    }

    /// @notice Multisig address that withdraws the tokens and proposes/executes Timelock transactions
    function getMultisig() external view returns (address) {
        return _getReserveStakingStorage().multisig;
    }

    /// @notice Timelock contract that controls upgrades and withdrawals
    function getTimelock() external view returns (TimelockController) {
        return _getReserveStakingStorage().timelock;
    }

}
