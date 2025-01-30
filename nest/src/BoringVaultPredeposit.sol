// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IAccountantWithRateProviders } from "./interfaces/IAccountantWithRateProviders.sol";
import { IAtomicQueue } from "./interfaces/IAtomicQueue.sol";
import { IBoringVault } from "./interfaces/IBoringVault.sol";
import { ILens } from "./interfaces/ILens.sol";
import { BridgeData, ITeller } from "./interfaces/ITeller.sol";

import { console } from "forge-std/console.sol";

/**
 * @title BoringVaultPredeposit
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Pre-deposit contract for integration with BoringVaults on Plume
 */
contract nYieldStaking is AccessControlUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {

    // Types

    using SafeERC20 for IERC20;

    /**
     * @notice State of a user that deposits into the RWAStaking contract
     * @param amountSeconds Cumulative sum of the amount of stablecoins staked by the user,
     *   multiplied by the number of seconds that the user has staked this amount for
     * @param amountStaked Total amount of stablecoins staked by the user
     * @param lastUpdate Timestamp of the most recent update to amountSeconds
     * @param stablecoinAmounts Mapping of stablecoin token contract addresses
     *   to the amount of stablecoins staked by the user
     */
    struct UserState {
        uint256 amountSeconds;
        uint256 amountStaked;
        uint256 lastUpdate;
        mapping(IERC20 stablecoin => uint256 amount) stablecoinAmounts;
    }

    /// @notice Thrown when a user tries to withdraw or transfer more than their available balance
    /// @param available The user's current available balance
    /// @param required The amount the user attempted to withdraw or transfer
    error InsufficientBalance(uint256 available, uint256 required);

    /// @notice Thrown when a user tries to convert to vault shares before the conversion start time
    /// @param currentTime The current block timestamp
    /// @param startTime The configured vault conversion start time
    error ConversionNotStarted(uint256 currentTime, uint256 startTime);

    /// @notice Emitted when the admin sets the time when users can start converting their stablecoins to vault shares
    /// @param startTime The timestamp when conversion will be enabled
    event VaultConversionStartTimeSet(uint256 startTime);

    /// @notice Emitted when stablecoins are converted to vault shares
    /// @param stablecoin The address of the stablecoin that was converted
    /// @param vault The address of the vault that received the stablecoins
    /// @param amount The amount of stablecoins converted
    /// @param shares The amount of vault shares received
    event StablecoinConvertedToVault(IERC20 stablecoin, IBoringVault vault, uint256 amount, uint256 shares);

    /// @notice Emitted when a user updates their bridge opt-in status for a specific stablecoin
    /// @param user The address of the user who updated their opt-in status
    /// @param stablecoin The stablecoin for which the opt-in status was updated
    /// @param optIn The new opt-in status (true = opted in, false = opted out)
    event UserBridgeOptInUpdated(address indexed user, IERC20 indexed stablecoin, bool optIn);

    /// @notice Emitted when a user's position is bridged to another chain
    /// @param user The address of the user whose position was bridged
    /// @param stablecoin The stablecoin that was bridged
    /// @param shares The amount of shares that were bridged
    event UserPositionBridged(address indexed user, IERC20 indexed stablecoin, uint256 shares);

    /// @notice Emitted when a user converts their stablecoins to BoringVault shares
    /// @param user The address of the user who converted their stablecoins
    /// @param stablecoin The stablecoin that was converted
    /// @param amount The amount of stablecoins converted
    /// @param receivedShares The amount of vault shares received
    event ConvertedToBoringVault(
        address indexed user, IERC20 indexed stablecoin, uint256 amount, uint256 receivedShares
    );

    /// @notice Emitted when vault shares are transferred between users
    /// @param from The address sending the shares
    /// @param to The address receiving the shares
    /// @param stablecoin The stablecoin associated with the shares
    /// @param amount The amount of shares transferred
    event SharesTransferred(address indexed from, address indexed to, IERC20 indexed stablecoin, uint256 amount);

    /// @notice Emitted when a user converts their stablecoins to vault shares through the Teller contract
    /// @param user The address of the user who converted their stablecoins
    /// @param stablecoin The stablecoin that was converted
    /// @param vault The Teller contract used for the conversion
    /// @param amount The amount of stablecoins converted
    /// @param shares The amount of vault shares received
    event UserConvertedToVault(
        address indexed user, IERC20 indexed stablecoin, ITeller vault, uint256 amount, uint256 shares
    );

    /// @notice Emitted when vault shares are transferred to a user
    /// @param user The address receiving the vault shares
    /// @param stablecoin The stablecoin associated with the shares
    /// @param shares The amount of shares transferred
    event VaultSharesTransferred(address indexed user, IERC20 indexed stablecoin, uint256 shares);

    // Storage

    struct BoringVault {
        ITeller teller;
        IBoringVault vault;
        IAtomicQueue atomicQueue;
        ILens lens;
        IAccountantWithRateProviders accountant;
    }

    /// @custom:storage-location erc7201:plume.storage.RWAStaking
    struct BoringVaultPredepositStorage {
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
        /// @dev True if the RWAStaking contract is paused for deposits, false otherwise
        bool paused;
        /// @dev Multisig address that withdraws the tokens and proposes/executes Timelock transactions
        address multisig;
        /// @dev nYIELD vault address
        BoringVault vault;
        /// @dev Timelock contract address
        TimelockController timelock;
        /// @dev Timestamp when users can start converting
        uint256 vaultConversionStartTime;
        // New storage for vault conversion
        mapping(IERC20 => IBoringVault) stablecoinToVault;
        mapping(IERC20 => uint256) vaultTotalShares;
        mapping(address => mapping(IERC20 => uint256)) userVaultShares;
        mapping(address => mapping(IERC20 => bool)) userBridgeOptIn;
        mapping(address => mapping(IERC20 => bool)) userPositionBridged;
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.nYieldStaking")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BORINGVAULT_PREDEPOSIT_STORAGE_LOCATION =
        0x91fba57b99f8ab5feaeb3c341c9ead66b71426630d0f57b5ca97617e91ea5000;

    function _getBoringVaultPredepositStorage() private pure returns (BoringVaultPredepositStorage storage $) {
        assembly {
            $.slot := BORINGVAULT_PREDEPOSIT_STORAGE_LOCATION
        }
    }

    // Constants

    /// @notice Role for the admin of the RWAStaking contract
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @notice Number of decimals for the base unit of amount
    uint8 public constant _BASE = 18;

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

    /// @notice Emitted when the RWAStaking contract is paused for deposits
    event Paused();

    /// @notice Emitted when the RWAStaking contract is unpaused for deposits
    event Unpaused();

    event StablecoinAllowed(IERC20 indexed stablecoin, uint8 decimals);

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

    /// @notice Indicates a failure because the stablecoin has too many decimals
    error TooManyDecimals();

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

    // Modifiers

    /// @notice Only the timelock contract can call this function
    modifier onlyTimelock() {
        if (msg.sender != address(_getBoringVaultPredepositStorage().timelock)) {
            revert Unauthorized(msg.sender, address(_getBoringVaultPredepositStorage().timelock));
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
     * @notice Initialize the RWAStaking contract
     * @param timelock Timelock contract address
     * @param owner Address of the owner of the RWAStaking contract
     */
    function initialize(
        TimelockController timelock,
        address owner,
        BoringVault memory boringVaultConfig
    ) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        BoringVaultPredepositStorage storage $ = _getBoringVaultPredepositStorage();
        $.multisig = owner;
        $.timelock = timelock;

        // Initialize BoringVault struct from parameters
        $.vault = boringVaultConfig;

        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(ADMIN_ROLE, owner);
    }

    /**
     * @notice Reinitialize the RWAStaking contract by adding the timelock and multisig contract address
     * @param multisig Multisig contract address
     * @param timelock Timelock contract address
     */
    function reinitialize(address multisig, TimelockController timelock) public reinitializer(2) onlyRole(ADMIN_ROLE) {
        BoringVaultPredepositStorage storage $ = _getBoringVaultPredepositStorage();
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
        _getBoringVaultPredepositStorage().multisig = multisig;
    }

    /// @notice Sets the time when users can start converting their stablecoins to vault shares
    /// @dev Only callable by admin role
    /// @param startTime The timestamp when conversion will be enabled
    /// @custom:throws If startTime is not in the future
    function setVaultConversionStartTime(
        uint256 startTime
    ) external onlyRole(ADMIN_ROLE) {
        require(startTime > block.timestamp, "Start time must be in future");
        BoringVaultPredepositStorage storage $ = _getBoringVaultPredepositStorage();
        $.vaultConversionStartTime = startTime;
        emit VaultConversionStartTimeSet(startTime);
    }

    /**
     * @notice Allow a stablecoin to be staked into the RWAStaking contract
     * @dev This function can only be called by an admin
     * @param stablecoin Stablecoin token contract address
     */
    function allowStablecoin(
        IERC20 stablecoin
    ) external onlyRole(ADMIN_ROLE) {
        _allowStablecoin(stablecoin);
    }

    // Internal function for allowing stablecoins
    function _allowStablecoin(
        IERC20 stablecoin
    ) internal {
        BoringVaultPredepositStorage storage $ = _getBoringVaultPredepositStorage();
        if ($.allowedStablecoins[stablecoin]) {
            revert AlreadyAllowedStablecoin(stablecoin);
        }

        uint8 decimals = IERC20Metadata(address(stablecoin)).decimals();
        if (decimals > _BASE) {
            revert TooManyDecimals();
        }

        $.stablecoins.push(stablecoin);
        $.allowedStablecoins[stablecoin] = true;

        emit StablecoinAllowed(stablecoin, decimals);
    }

    /**
     * @notice Stop the RWAStaking contract by withdrawing all stablecoins
     * @dev Only the admin can withdraw stablecoins from the RWAStaking contract
     */
    function adminWithdraw() external nonReentrant onlyTimelock {
        BoringVaultPredepositStorage storage $ = _getBoringVaultPredepositStorage();
        if ($.endTime != 0) {
            revert StakingEnded();
        }

        IERC20[] storage stablecoins = $.stablecoins;
        uint256 length = stablecoins.length;
        for (uint256 i = 0; i < length; ++i) {
            IERC20 stablecoin = stablecoins[i];
            uint256 amount = stablecoin.balanceOf(address(this));
            stablecoin.safeTransfer($.multisig, amount);
            emit AdminWithdrawn(
                $.multisig, stablecoin, amount * 10 ** (_BASE - IERC20Metadata(address(stablecoin)).decimals())
            );
        }
        $.endTime = block.timestamp;
    }

    /**
     * @notice Bridge stablecoins to Plume mainnet through the Teller contract
     * @param teller Teller contract address
     * @param bridgeData Data required for bridging
     */
    function adminBridge(ITeller teller, BridgeData calldata bridgeData) external payable nonReentrant onlyTimelock {
        BoringVaultPredepositStorage storage $ = _getBoringVaultPredepositStorage();
        if ($.endTime != 0) {
            revert StakingEnded();
        }

        IERC20[] storage stablecoins = $.stablecoins;
        uint256 length = stablecoins.length;
        for (uint256 i = 0; i < length; ++i) {
            IERC20 stablecoin = stablecoins[i];
            uint256 amount = stablecoin.balanceOf(address(this));
            if (amount > 0) {
                stablecoin.forceApprove(address($.vault.teller), amount);
                uint256 fee = teller.previewFee(amount, bridgeData);
                teller.depositAndBridge{ value: msg.value }(ERC20(address(stablecoin)), amount, amount, bridgeData);
                emit AdminWithdrawn(
                    $.multisig, stablecoin, amount * 10 ** (_BASE - IERC20Metadata(address(stablecoin)).decimals())
                );
            }
        }

        $.endTime = block.timestamp;
    }

    /**
     * @notice Pause the RWAStaking contract for deposits
     * @dev Only the admin can pause the RWAStaking contract for deposits
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        BoringVaultPredepositStorage storage $ = _getBoringVaultPredepositStorage();
        if ($.paused) {
            revert AlreadyPaused();
        }
        $.paused = true;
        emit Paused();
    }

    // Errors

    /**
     * @notice Unpause the RWAStaking contract for deposits
     * @dev Only the admin can unpause the RWAStaking contract for deposits
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        BoringVaultPredepositStorage storage $ = _getBoringVaultPredepositStorage();
        if (!$.paused) {
            revert NotPaused();
        }
        $.paused = false;
        emit Unpaused();
    }

    // User Functions

    /**
     * @notice Stake stablecoins into the RWAStaking contract
     * @param amount Amount of stablecoins to stake
     * @param stablecoin Stablecoin token contract address
     */
    function stake(uint256 amount, IERC20 stablecoin) external nonReentrant {
        BoringVaultPredepositStorage storage $ = _getBoringVaultPredepositStorage();
        require($.allowedStablecoins[stablecoin], "Stablecoin not allowed");
        require(amount > 0, "Amount must be greater than 0");

        // Get initial balance to verify transfer
        uint256 initialBalance = stablecoin.balanceOf(address(this));

        // Transfer tokens from user
        stablecoin.safeTransferFrom(msg.sender, address(this), amount);

        // Verify transfer amount
        uint256 actualAmount = stablecoin.balanceOf(address(this)) - initialBalance;
        require(actualAmount == amount, "Transfer amount mismatch");

        // Convert to base units (18 decimals) for internal accounting
        uint256 baseAmount = _toBaseUnits(amount, stablecoin);

        // Update state
        UserState storage userState = $.userStates[msg.sender];
        userState.amountStaked += baseAmount;
        userState.stablecoinAmounts[stablecoin] += baseAmount;
        $.totalAmountStaked += baseAmount;

        // Also track shares 1:1 with staked amount
        $.userVaultShares[msg.sender][stablecoin] += amount;
        $.vaultTotalShares[stablecoin] += amount;

        emit Staked(msg.sender, stablecoin, amount);
    }

    /**
     * @notice Withdraw stablecoins from the RWAStaking contract
     * @param amount Amount of stablecoins to withdraw
     * @param stablecoin Stablecoin token contract address
     */
    function withdraw(uint256 amount, IERC20 stablecoin) external nonReentrant {
        BoringVaultPredepositStorage storage $ = _getBoringVaultPredepositStorage();
        if ($.endTime != 0) {
            revert StakingEnded();
        }

        uint256 baseUnitConversion = 10 ** (_BASE - IERC20Metadata(address(stablecoin)).decimals());
        uint256 timestamp = block.timestamp;
        UserState storage userState = $.userStates[msg.sender];
        if (userState.stablecoinAmounts[stablecoin] < amount * baseUnitConversion) {
            revert InsufficientStaked(
                msg.sender, stablecoin, amount * baseUnitConversion, userState.stablecoinAmounts[stablecoin]
            );
        }

        userState.amountSeconds += userState.amountStaked * (timestamp - userState.lastUpdate);
        uint256 previousBalance = stablecoin.balanceOf(address(this));
        stablecoin.safeTransfer(msg.sender, amount);
        uint256 newBalance = stablecoin.balanceOf(address(this));
        uint256 actualAmount = (previousBalance - newBalance) * baseUnitConversion;

        userState.amountSeconds -= userState.amountSeconds * actualAmount / userState.amountStaked;
        userState.amountStaked -= actualAmount;
        userState.lastUpdate = timestamp;
        userState.stablecoinAmounts[stablecoin] -= actualAmount;
        $.totalAmountStaked -= actualAmount;

        emit Withdrawn(msg.sender, stablecoin, actualAmount);
    }

    // Getter View Functions

    /// @notice Total amount of stablecoins staked in the RWAStaking contract
    function getTotalAmountStaked() external view returns (uint256) {
        return _getBoringVaultPredepositStorage().totalAmountStaked;
    }

    /// @notice List of users who have staked into the RWAStaking contract
    function getUsers() external view returns (address[] memory) {
        return _getBoringVaultPredepositStorage().users;
    }

    /// @notice State of a user who has staked into the RWAStaking contract
    function getUserState(
        address user
    ) external view returns (uint256 amountSeconds, uint256 amountStaked, uint256 lastUpdate) {
        BoringVaultPredepositStorage storage $ = _getBoringVaultPredepositStorage();
        UserState storage userState = $.userStates[user];
        return (
            userState.amountSeconds
                + userState.amountStaked * (($.endTime > 0 ? $.endTime : block.timestamp) - userState.lastUpdate),
            userState.amountStaked,
            userState.lastUpdate
        );
    }
    /*
    /// @notice Amount of stablecoins staked by a user for each stablecoin
    function getUserStablecoinAmounts(address user, IERC20 stablecoin) external view returns (uint256) {
        return _getBoringVaultPredepositStorage().userStates[user].stablecoinAmounts[stablecoin];
    }
    */
    /// @notice List of stablecoins allowed to be staked in the RWAStaking contract

    function getAllowedStablecoins() external view returns (IERC20[] memory) {
        return _getBoringVaultPredepositStorage().stablecoins;
    }

    /// @notice Whether a stablecoin is allowed to be staked in the RWAStaking contract
    function isAllowedStablecoin(
        IERC20 stablecoin
    ) external view returns (bool) {
        return _getBoringVaultPredepositStorage().allowedStablecoins[stablecoin];
    }

    /// @notice Timestamp of when pre-staking ends, when the admin withdraws all stablecoins
    function getEndTime() external view returns (uint256) {
        return _getBoringVaultPredepositStorage().endTime;
    }

    /// @notice Returns true if the RWAStaking contract is pauseWhether the RWAStaking contract is paused for deposits
    function isPaused() external view returns (bool) {
        return _getBoringVaultPredepositStorage().paused;
    }

    /// @notice Multisig address that withdraws the tokens and proposes/executes Timelock transactions
    function getMultisig() external view returns (address) {
        return _getBoringVaultPredepositStorage().multisig;
    }

    /// @notice Timelock contract that controls upgrades and withdrawals
    function getTimelock() external view returns (TimelockController) {
        return _getBoringVaultPredepositStorage().timelock;
    }

    /// @notice Converts user's stablecoins to BoringVault shares through the Teller contract
    /// @dev Requires conversion period to have started and sufficient balance
    /// @param stablecoin The stablecoin to convert
    /// @param teller The Teller contract to use for conversion
    /// @param amount The amount of stablecoins to convert
    /// @custom:throws If conversion hasn't started, stablecoin not allowed, or insufficient balance
    function convertToBoringVault(IERC20 stablecoin, ITeller teller, uint256 amount) external nonReentrant {
        BoringVaultPredepositStorage storage $ = _getBoringVaultPredepositStorage();
        require(block.timestamp >= $.vaultConversionStartTime, "Conversion not started");
        require($.allowedStablecoins[stablecoin], "Stablecoin not allowed");

        uint256 baseAmount = _toBaseUnits(amount, stablecoin);
        require($.userStates[msg.sender].stablecoinAmounts[stablecoin] >= baseAmount, "Insufficient balance");

        // Update state before transfer
        $.userStates[msg.sender].amountStaked -= baseAmount;
        $.userStates[msg.sender].stablecoinAmounts[stablecoin] -= baseAmount;
        $.totalAmountStaked -= baseAmount;

        // Update shares
        $.userVaultShares[msg.sender][stablecoin] -= amount;
        $.vaultTotalShares[stablecoin] -= amount;

        // Approve vault to spend tokens
        IERC20(stablecoin).approve(address($.vault.vault), amount);

        // Approve teller to spend tokens
        IERC20(stablecoin).approve(address(teller), amount);

        // Deposit into Boring vault
        uint256 receivedShares = teller.deposit(
            ERC20(address(stablecoin)),
            amount,
            0 // minimum shares to receive
        );

        emit ConvertedToBoringVault(msg.sender, stablecoin, amount, receivedShares);
    }

    /// @notice Transfers vault shares to multiple recipients in a single transaction
    /// @dev All arrays must be the same length
    /// @param stablecoins Array of stablecoin addresses
    /// @param recipients Array of recipient addresses
    /// @param amounts Array of amounts to transfer
    /// @custom:throws If array lengths don't match, stablecoin not allowed, invalid recipient, or insufficient balance
    function batchTransferShares(
        IERC20[] calldata stablecoins,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external nonReentrant {
        require(
            stablecoins.length == recipients.length && recipients.length == amounts.length, "Array lengths must match"
        );

        BoringVaultPredepositStorage storage $ = _getBoringVaultPredepositStorage();

        for (uint256 i = 0; i < stablecoins.length; i++) {
            IERC20 stablecoin = stablecoins[i];
            address recipient = recipients[i];
            uint256 amount = amounts[i];

            require($.allowedStablecoins[stablecoin], "Stablecoin not allowed");
            require(recipient != address(0), "Invalid recipient");

            uint256 baseAmount = _toBaseUnits(amount, stablecoin);
            require($.userStates[msg.sender].stablecoinAmounts[stablecoin] >= baseAmount, "Insufficient balance");

            // Update sender state
            $.userStates[msg.sender].amountStaked -= baseAmount;
            $.userStates[msg.sender].stablecoinAmounts[stablecoin] -= baseAmount;

            // Update recipient state
            $.userStates[recipient].amountStaked += baseAmount;
            $.userStates[recipient].stablecoinAmounts[stablecoin] += baseAmount;

            // Update shares
            $.userVaultShares[msg.sender][stablecoin] -= amount;
            $.userVaultShares[recipient][stablecoin] += amount;

            emit SharesTransferred(msg.sender, recipient, stablecoin, amount);
        }
    }

    /**
     * @notice Batch transfer vault shares to users
     * @param stablecoin The stablecoin whose vault shares to transfer
     * @param users Array of users to transfer shares to
     * @dev Called periodically (e.g., every 12 hours) to save gas
     */
    function batchTransferVaultShares(
        IERC20 stablecoin,
        address[] calldata users
    ) external onlyRole(ADMIN_ROLE) nonReentrant {
        BoringVaultPredepositStorage storage $ = _getBoringVaultPredepositStorage();

        // Get the teller
        //ITeller teller = ITeller(address($.stablecoinToVault[stablecoin]));
        ITeller teller = $.vault.teller;
        require(address(teller) != address(0), "Teller not set");

        // nYIELD token
        ERC20 nYIELD = ERC20(0x892DFf5257B39f7afB7803dd7C81E8ECDB6af3E8);

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            uint256 shares = $.userVaultShares[user][stablecoin];

            if (shares > 0) {
                // Reset user's share balance before transfer
                $.userVaultShares[user][stablecoin] = 0;
                $.vaultTotalShares[stablecoin] -= shares;

                // Transfer nYIELD tokens to user
                nYIELD.transfer(user, shares);

                emit VaultSharesTransferred(user, stablecoin, shares);
            }
        }
    }

    /// @notice Returns the timestamp when vault conversion will be enabled
    /// @return uint256 The conversion start timestamp
    function getVaultConversionStartTime() external view returns (uint256) {
        return _getBoringVaultPredepositStorage().vaultConversionStartTime;
    }

    /// @notice Returns the total shares for a given stablecoin
    /// @param stablecoin The stablecoin to query
    /// @return uint256 The total shares for the stablecoin
    function getVaultTotalShares(
        IERC20 stablecoin
    ) external view returns (uint256) {
        BoringVaultPredepositStorage storage $ = _getBoringVaultPredepositStorage();
        return $.vaultTotalShares[stablecoin];
    }

    // Utility Functions

    /// @notice Returns the amount of stablecoins a user has staked
    /// @param user The address of the user
    /// @param stablecoin The stablecoin to query
    /// @return uint256 The amount of stablecoins in the token's native decimals
    function getUserStablecoinAmounts(address user, IERC20 stablecoin) external view returns (uint256) {
        BoringVaultPredepositStorage storage $ = _getBoringVaultPredepositStorage();
        uint256 baseAmount = $.userStates[user].stablecoinAmounts[stablecoin];
        return _fromBaseUnits(baseAmount, stablecoin);
    }

    /// @notice Returns the amount of vault shares a user has for a given stablecoin
    /// @param user The address of the user
    /// @param stablecoin The stablecoin to query
    /// @return uint256 The amount of vault shares
    function getUserVaultShares(address user, IERC20 stablecoin) external view returns (uint256) {
        BoringVaultPredepositStorage storage $ = _getBoringVaultPredepositStorage();
        return $.userVaultShares[user][stablecoin];
    }

    /// @notice Converts an amount from token decimals to base units (18 decimals)
    /// @dev Used for internal accounting
    /// @param amount The amount to convert
    /// @param token The token whose decimals to use
    /// @return uint256 The amount in base units
    function _toBaseUnits(uint256 amount, IERC20 token) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(address(token)).decimals();
        if (decimals == _BASE) {
            return amount;
        }
        return amount * (10 ** (_BASE - decimals));
    }

    /// @notice Converts an amount from base units (18 decimals) to token decimals
    /// @dev Used for external-facing functions
    /// @param amount The amount in base units to convert
    /// @param token The token whose decimals to convert to
    /// @return uint256 The amount in token decimals
    function _fromBaseUnits(uint256 amount, IERC20 token) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(address(token)).decimals();
        if (decimals == _BASE) {
            return amount;
        }
        return amount / (10 ** (_BASE - decimals));
    }

    /// @notice Allows the contract to receive ETH
    /// @dev Required for bridge fees
    receive() external payable { }

}
