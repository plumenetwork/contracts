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
import { ITeller } from "./interfaces/ITeller.sol";

/**
 * @title BoringVaultPredeposit
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Pre-deposit contract for integration with BoringVaults on Plume
 */
contract nYieldStaking is AccessControlUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {

    // Types

    using SafeERC20 for IERC20;

    /**
     * @notice State of a user that deposits into the BoringVaultPredeposit contract
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
        mapping(IERC20 stablecoin => uint256 shares) vaultShares;
    }

    // Storage

    struct BoringVault {
        ITeller teller;
        IBoringVault vault;
        IAtomicQueue atomicQueue;
        ILens lens;
        IAccountantWithRateProviders accountant;
    }

    /// @custom:storage-location erc7201:plume.storage.BoringVaultPredeposit
    struct BoringVaultPredepositStorage {
        /// @dev Total amount of stablecoins staked in the BoringVaultPredeposit contract
        uint256 totalAmountStaked;
        /// @dev List of users who have staked into the BoringVaultPredeposit contract
        address[] users;
        /// @dev Mapping of users to their state in the BoringVaultPredeposit contract
        mapping(address user => UserState userState) userStates;
        /// @dev List of stablecoins allowed to be staked in the BoringVaultPredeposit contract
        IERC20[] stablecoins;
        /// @dev Mapping of stablecoins to whether they are allowed to be staked
        mapping(IERC20 stablecoin => bool allowed) allowedStablecoins;
        /// @dev Timestamp of when pre-staking ends, when the admin withdraws all stablecoins
        uint256 endTime;
        /// @dev True if the BoringVaultPredeposit contract is paused for deposits, false otherwise
        bool paused;
        /// @dev Multisig address that withdraws the tokens and proposes/executes Timelock transactions
        address multisig;
        /// @dev BoringVault vault address
        BoringVault vault;
        /// @dev Timelock contract address
        TimelockController timelock;
        /// @dev Timestamp when users can start converting
        uint256 vaultConversionStartTime;
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.nYieldBoringVaultPredeposit")) - 1)) &
    // ~bytes32(uint256(0xff))
    bytes32 private constant BORINGVAULT_PREDEPOSIT_STORAGE_LOCATION =
        0x714034f23dd5282a94e73061db4134cb46d9e6964d121d2c45f80404b7307c00;

    function _getBoringVaultPredepositStorage() private pure returns (BoringVaultPredepositStorage storage $) {
        assembly {
            $.slot := BORINGVAULT_PREDEPOSIT_STORAGE_LOCATION
        }
    }

    // Constants

    /// @notice Role for the admin of the BoringVaultPredeposit contract
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @notice Number of decimals for the base unit of amount
    uint8 public constant _BASE = 18;

    // Events

    /**
     * @notice Emitted when an admin withdraws stablecoins from the BoringVaultPredeposit contract
     * @param user Address of the admin who withdrew stablecoins
     * @param stablecoin Stablecoin token contract address
     * @param amount Amount of stablecoins withdrawn
     */
    event AdminWithdrawn(address indexed user, IERC20 indexed stablecoin, uint256 amount);

    /**
     * @notice Emitted when a user withdraws stablecoins from the BoringVaultPredeposit contract
     * @param user Address of the user who withdrew stablecoins
     * @param stablecoin Stablecoin token contract address
     * @param amount Amount of stablecoins withdrawn
     */
    event Withdrawn(address indexed user, IERC20 indexed stablecoin, uint256 amount);

    /**
     * @notice Emitted when a user stakes stablecoins into the BoringVaultPredeposit contract
     * @param user Address of the user who staked stablecoins
     * @param stablecoin Stablecoin token contract address
     * @param amount Amount of stablecoins staked
     */
    event Staked(address indexed user, IERC20 indexed stablecoin, uint256 amount);

    /// @notice Emitted when the BoringVaultPredeposit contract is paused for deposits
    event Paused();

    /// @notice Emitted when the BoringVaultPredeposit contract is unpaused for deposits
    event Unpaused();

    /// @notice Emitted when a new stablecoin is allowed for staking
    /// @param stablecoin The address of the stablecoin that was allowed
    /// @param decimals The number of decimals of the stablecoin
    event StablecoinAllowed(IERC20 indexed stablecoin, uint8 decimals);

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

    /// @notice Thrown when a user tries to withdraw or transfer more than their available balance
    /// @param available The user's current available balance
    /// @param required The amount the user attempted to withdraw or transfer
    error InsufficientBalance(uint256 available, uint256 required);

    /// @notice Thrown when a user tries to convert to vault shares before the conversion start time
    /// @param currentTime The current block timestamp
    /// @param startTime The configured vault conversion start time
    error ConversionNotStarted(uint256 currentTime, uint256 startTime);

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
     * @notice Initialize the BoringVaultPredeposit contract
     * @param timelock Timelock contract address
     * @param owner Address of the owner of the BoringVaultPredeposit contract
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
     * @notice Reinitialize the BoringVaultPredeposit contract by adding the timelock and multisig contract address
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
     * @notice Allow a stablecoin to be staked into the BoringVaultPredeposit contract
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
     * @notice Stop the BoringVaultPredeposit contract by withdrawing all stablecoins
     * @dev Only the admin can withdraw stablecoins from the BoringVaultPredeposit contract
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
     * @notice Pause the BoringVaultPredeposit contract for deposits
     * @dev Only the admin can pause the BoringVaultPredeposit contract for deposits
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        BoringVaultPredepositStorage storage $ = _getBoringVaultPredepositStorage();
        if ($.paused) {
            revert AlreadyPaused();
        }
        $.paused = true;
        emit Paused();
    }

    /**
     * @notice Unpause the BoringVaultPredeposit contract for deposits
     * @dev Only the admin can unpause the BoringVaultPredeposit contract for deposits
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
     * @notice Stake stablecoins into the BoringVaultPredeposit contract
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

        emit Staked(msg.sender, stablecoin, amount);
    }

    /**
     * @notice Withdraw stablecoins from the BoringVaultPredeposit contract
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

    /// @notice Total amount of stablecoins staked in the BoringVaultPredeposit contract
    function getTotalAmountStaked() external view returns (uint256) {
        return _getBoringVaultPredepositStorage().totalAmountStaked;
    }

    /// @notice List of users who have staked into the BoringVaultPredeposit contract
    function getUsers() external view returns (address[] memory) {
        return _getBoringVaultPredepositStorage().users;
    }

    /// @notice State of a user who has staked into the BoringVaultPredeposit contract
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

    /// @notice List of stablecoins allowed to be staked in the BoringVaultPredeposit contract
    function getAllowedStablecoins() external view returns (IERC20[] memory) {
        return _getBoringVaultPredepositStorage().stablecoins;
    }

    /// @notice Whether a stablecoin is allowed to be staked in the BoringVaultPredeposit contract
    function isAllowedStablecoin(
        IERC20 stablecoin
    ) external view returns (bool) {
        return _getBoringVaultPredepositStorage().allowedStablecoins[stablecoin];
    }

    /// @notice Timestamp of when pre-staking ends, when the admin withdraws all stablecoins
    function getEndTime() external view returns (uint256) {
        return _getBoringVaultPredepositStorage().endTime;
    }

    /// @notice Returns true if the BoringVaultPredeposit contract is pauseWhether the BoringVaultPredeposit contract is
    /// paused for deposits
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

    /// @notice Deposits user's stablecoins into nYIELD vault and sends shares directly to user
    /// @param depositAsset The stablecoin to deposit
    /// @return shares Amount of shares received
    function depositToVault(
        ERC20 depositAsset
    ) external nonReentrant returns (uint256 shares) {
        BoringVaultPredepositStorage storage $ = _getBoringVaultPredepositStorage();
        require($.allowedStablecoins[IERC20(address(depositAsset))], "Stablecoin not allowed");

        UserState storage userState = $.userStates[msg.sender];
        uint256 depositAmount =
            _fromBaseUnits(userState.stablecoinAmounts[IERC20(address(depositAsset))], IERC20(address(depositAsset)));
        require(depositAmount > 0, "No tokens to deposit");

        // Update stablecoin balances
        userState.amountStaked -= userState.stablecoinAmounts[IERC20(address(depositAsset))];
        userState.stablecoinAmounts[IERC20(address(depositAsset))] = 0;
        $.totalAmountStaked -= userState.stablecoinAmounts[IERC20(address(depositAsset))];

        // Approve both teller and vault to spend tokens
        depositAsset.approve(address($.vault.teller), depositAmount);
        depositAsset.approve(address($.vault.vault), depositAmount);

        // Calculate minimum shares (99% of deposit amount)
        uint256 minimumMint = (depositAmount * 99) / 100;

        // Deposit into vault through Teller
        shares = $.vault.teller.deposit(depositAsset, depositAmount, minimumMint);

        // Transfer shares directly to user
        ERC20(address($.vault.vault)).transfer(msg.sender, shares);

        emit ConvertedToBoringVault(msg.sender, IERC20(address(depositAsset)), depositAmount, shares);

        return shares;
    }

    /// @notice Admin function to deposit multiple users' funds into vault and distribute shares
    /// @param recipients Array of addresses to receive vault shares
    /// @param depositAssets Array of stablecoins to deposit for each recipient
    /// @param amounts Array of amounts to deposit for each recipient
    /// @return shares Array of share amounts received for each deposit
    function batchDepositToVault(
        address[] calldata recipients,
        ERC20[] calldata depositAssets,
        uint256[] calldata amounts
    ) external nonReentrant onlyRole(ADMIN_ROLE) returns (uint256[] memory shares) {
        BoringVaultPredepositStorage storage $ = _getBoringVaultPredepositStorage();

        require(
            recipients.length == depositAssets.length && depositAssets.length == amounts.length,
            "Array lengths must match"
        );

        shares = new uint256[](recipients.length);

        for (uint256 i = 0; i < recipients.length; i++) {
            address recipient = recipients[i];
            ERC20 depositAsset = depositAssets[i];
            uint256 depositAmount = amounts[i];

            require($.allowedStablecoins[IERC20(address(depositAsset))], "Stablecoin not allowed");
            require(recipient != address(0), "Invalid recipient");
            require(depositAmount > 0, "Amount must be greater than 0");

            // Approve both teller and vault to spend tokens
            depositAsset.approve(address($.vault.teller), depositAmount);
            depositAsset.approve(address($.vault.vault), depositAmount);

            // Calculate minimum shares (99% of deposit amount)
            uint256 minimumMint = (depositAmount * 99) / 100;

            // Deposit into vault through Teller
            shares[i] = $.vault.teller.deposit(depositAsset, depositAmount, minimumMint);

            // Transfer shares directly to recipient
            ERC20(address($.vault.vault)).transfer(recipient, shares[i]);

            emit ConvertedToBoringVault(recipient, IERC20(address(depositAsset)), depositAmount, shares[i]);
        }

        return shares;
    }

    /// @notice Returns the timestamp when vault conversion will be enabled
    /// @return uint256 The conversion start timestamp
    function getVaultConversionStartTime() external view returns (uint256) {
        return _getBoringVaultPredepositStorage().vaultConversionStartTime;
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
        return $.userStates[user].vaultShares[stablecoin];
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

}
