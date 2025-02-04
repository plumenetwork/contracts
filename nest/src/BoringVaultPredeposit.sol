// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IBoringVault } from "./interfaces/IBoringVault.sol";
import { ITeller } from "./interfaces/ITeller.sol";

/**
 * @title BoringVaultPredeposit
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Pre-deposit contract for integration with BoringVaults on Plume
 */
contract BoringVaultPredeposit is AccessControlUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {

    // Types

    using SafeERC20 for IERC20;

    /**
     * @notice State of a user that deposits into the BoringVaultPredeposit contract
     * @param amountSeconds Cumulative sum of the amount of tokens staked by the user,
     *   multiplied by the number of seconds that the user has staked this amount for
     * @param lastUpdate Timestamp of the most recent update to amountSeconds
     * @param tokenAmounts Mapping of token contract addresses
     *   to the amount of tokens staked by the user
     */
    struct UserState {
        uint256 amountSeconds;
        uint256 lastUpdate;
        mapping(IERC20 => uint256) tokenAmounts;
        mapping(IERC20 => uint256) vaultShares;
    }

    struct UserTokenState {
        uint256 amountSeconds;
        uint256 tokenAmount;
    }

    // Storage

    struct BoringVault {
        ITeller teller;
        IBoringVault vault;
    }

    /// @custom:storage-location erc7201:plume.storage.BoringVaultPredeposit
    struct BoringVaultPredepositStorage {
        /// @dev Total amount of tokens staked in the BoringVaultPredeposit contract
        mapping(IERC20 => uint256) totalAmountStaked;
        /// @dev List of users who have staked into the BoringVaultPredeposit contract
        address[] users;
        /// @dev Mapping of users to their state in the BoringVaultPredeposit contract
        mapping(address user => UserState userState) userStates;
        /// @dev List of tokens allowed to be staked in the BoringVaultPredeposit contract
        IERC20[] tokens;
        /// @dev Mapping of tokens to whether they are allowed to be staked
        mapping(IERC20 => bool) allowedTokens;
        /// @dev Cache token decimals for allowed tokens (used for unit conversion)
        mapping(IERC20 => uint8) tokenDecimals;
        /// @dev Timestamp of when pre-staking ends, when the admin withdraws all tokens
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

    // --- Dynamic Storage Slot ---
    //
    // We store the slot in a private variable.
    // This variable is computed once (during initialize) based on a salt.
    bytes32 private _storageSlot;

    /// @dev Returns a pointer to our storage structure using the dynamic slot.
    function _getBoringVaultPredepositStorage() private view returns (BoringVaultPredepositStorage storage $) {
        bytes32 slot = _storageSlot;
        assembly {
            $.slot := slot
        }
    }

    // Constants

    /// @notice Role for the admin of the BoringVaultPredeposit contract
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @notice Number of decimals for the base unit of amount
    uint8 public constant _BASE = 18;

    // Events

    /**
     * @notice Emitted when an admin withdraws tokens from the BoringVaultPredeposit contract
     * @param user Address of the admin who withdrew tokens
     * @param token Token contract address
     * @param amount Amount of token withdrawn
     */
    event AdminWithdrawn(address indexed user, IERC20 indexed token, uint256 amount);

    /**
     * @notice Emitted when a user withdraws tokens from the BoringVaultPredeposit contract
     * @param user Address of the user who withdrew tokens
     * @param token Token contract address
     * @param amount Amount of tokens withdrawn
     */
    event Withdrawn(address indexed user, IERC20 indexed token, uint256 amount);

    /**
     * @notice Emitted when a user stakes tokens into the BoringVaultPredeposit contract
     * @param user Address of the user who staked tokens
     * @param token Token contract address
     * @param amount Amount of tokens staked
     */
    event Staked(address indexed user, IERC20 indexed token, uint256 amount);

    /// @notice Emitted when the BoringVaultPredeposit contract is paused for deposits
    event Paused();

    /// @notice Emitted when the BoringVaultPredeposit contract is unpaused for deposits
    event Unpaused();

    /// @notice Emitted when a new tokend is allowed for staking
    /// @param token The address of the token that was allowed
    /// @param decimals The number of decimals of the token
    event TokenAllowed(IERC20 indexed token, uint8 decimals);

    /// @notice Emitted when a new tokend is allowed for staking
    /// @param token The address of the token that was allowed
    event TokenDisabled(IERC20 indexed token);

    /// @notice Emitted when the admin sets the time when users can start converting their tokens to vault shares
    /// @param startTime The timestamp when conversion will be enabled
    event VaultConversionStartTimeSet(uint256 startTime);

    /// @notice Emitted when a user converts their tokens to BoringVault shares
    /// @param user The address of the user who converted their tokens
    /// @param token The token that was converted
    /// @param amount The amount of tokens converted
    /// @param receivedShares The amount of vault shares received
    event ConvertedToBoringVault(address indexed user, IERC20 indexed token, uint256 amount, uint256 receivedShares);

    /// @notice Emitted when timelock address is changed
    /// @param newTimelock The new timelock address (zero address if disabled)
    event TimelockSet(address newTimelock);

    /// @notice Emitted when owner address is changed
    /// @param newOwner The new owner address
    event OwnerSet(address newOwner);

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

    /// @notice Indicates a failure because the token has too many decimals
    error TooManyDecimals();

    /// @notice Thrown when array lengths don't match
    /// @param expected The expected length
    /// @param received The received length
    error ArrayLengthMismatch(uint256 expected, uint256 received);

    /// @notice Thrown when there's an issue with the amount being transferred
    /// @param expected The amount that was expected
    /// @param received The amount that was actually received (0 if amount is invalid)
    error InvalidAmount(uint256 expected, uint256 received);

    /// @notice Thrown when an address parameter is zero
    error ZeroAddress();

    /**
     * @notice Indicates a failure because the token is already allowed to be staked
     * @param token Token contract address
     */
    error AlreadyAllowedToken(IERC20 token);

    /**
     * @notice Indicates a failure because the token is not allowed to be staked
     * @param token Token contract address
     */
    error NotAllowedToken(IERC20 token);

    /// @notice Thrown when a timestamp is invalid (e.g., not in future when required)
    /// @param expected The expected timestamp
    /// @param received The received timestamp
    error InvalidTimestamp(uint256 expected, uint256 received);

    /**
     * @notice Indicates a failure because the user does not have enough tokens staked
     * @param user Address of the user who does not have enough tokens staked
     * @param token Token contract address
     * @param amount Amount of tokens that the user wants to withdraw
     * @param amountStaked Amount of tokens that the user has staked
     */
    error InsufficientStaked(address user, IERC20 token, uint256 amount, uint256 amountStaked);

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
     * @notice Initialize the contract.
     * @param timelock The timelock contract address.
     * @param owner The owner address.
     * @param boringVaultConfig The configuration for the BoringVault.
     * @param salt A value (e.g. derived from the vault’s parameters) used to derive a unique storage slot.
     *
     * The storage slot is computed as:
     * keccak256(abi.encodePacked("plume.storage.BoringVaultPredeposit", salt))
     */
    function initialize(
        TimelockController timelock,
        address owner,
        BoringVault memory boringVaultConfig,
        bytes32 salt
    ) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        _storageSlot = keccak256(abi.encodePacked("plume.storage.BoringVaultPredeposit", salt));
        BoringVaultPredepositStorage storage $ = _getBoringVaultPredepositStorage();

        $.multisig = owner;
        $.timelock = timelock;
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
    ) external nonReentrant onlyRole(ADMIN_ROLE) {
        _getBoringVaultPredepositStorage().multisig = multisig;
    }

    /// @notice Changes the timelock address. Set to zero address to disable timelock.
    /// @param newTimelock The new timelock contract address, or zero address
    function setTimelock(
        TimelockController newTimelock
    ) external onlyRole(ADMIN_ROLE) {
        _getBoringVaultPredepositStorage().timelock = newTimelock;
        emit TimelockSet(address(newTimelock));
    }

    /// @notice Changes the owner address
    /// @param newOwner The new owner address
    function setOwner(
        address newOwner
    ) external onlyRole(ADMIN_ROLE) {
        if (newOwner == address(0)) {
            revert ZeroAddress();
        }
        _getBoringVaultPredepositStorage().multisig = newOwner;
        _grantRole(DEFAULT_ADMIN_ROLE, newOwner);
        _grantRole(ADMIN_ROLE, newOwner);
        emit OwnerSet(newOwner);
    }

    /// @notice Sets the time when users can start converting their tokens to vault shares
    /// @dev Only callable by admin role
    /// @param startTime The timestamp when conversion will be enabled
    /// @custom:throws If startTime is not in the future
    function setVaultConversionStartTime(
        uint256 startTime
    ) external onlyRole(ADMIN_ROLE) {
        if (startTime < block.timestamp) {
            revert InvalidTimestamp(block.timestamp, startTime);
        }

        BoringVaultPredepositStorage storage $ = _getBoringVaultPredepositStorage();
        $.vaultConversionStartTime = startTime;
        emit VaultConversionStartTimeSet(startTime);
    }

    /**
     * @notice Allow a token to be deposited.
     * @dev This function can only be called by an admin
     * @param token Token contract address
     */
    function allowToken(
        IERC20 token
    ) external onlyRole(ADMIN_ROLE) {
        if (address(token) == address(0)) {
            revert ZeroAddress();
        }
        _allowToken(token);
    }

    // Internal function for allowing tokens

    function _allowToken(
        IERC20 token
    ) internal {
        BoringVaultPredepositStorage storage $ = _getBoringVaultPredepositStorage();
        if ($.allowedTokens[token]) {
            revert AlreadyAllowedToken(token);
        }
        uint8 decimals = IERC20Metadata(address(token)).decimals();
        if (decimals > _BASE) {
            revert TooManyDecimals();
        }

        $.tokens.push(token);
        $.allowedTokens[token] = true;
        $.tokenDecimals[token] = decimals;
        emit TokenAllowed(token, decimals);
    }

    /**
     * @notice Disables a token so that no new deposits are accepted.
     *         Existing deposits remain withdrawable.
     * @param token The token to disable.
     */
    function disableToken(
        IERC20 token
    ) external onlyRole(ADMIN_ROLE) {
        BoringVaultPredepositStorage storage $ = _getBoringVaultPredepositStorage();
        if (!$.allowedTokens[token]) {
            revert NotAllowedToken(token);
        }
        $.allowedTokens[token] = false;
        emit TokenDisabled(token);
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
     * @notice Stake tokens into the BoringVaultPredeposit contract
     * @param amount Amount of tokens to stake
     * @param token Token contract address
     */
    function stake(uint256 amount, IERC20 token) external nonReentrant {
        BoringVaultPredepositStorage storage $ = _getBoringVaultPredepositStorage();

        if ($.paused) {
            revert DepositPaused();
        }

        if ($.endTime != 0) {
            revert StakingEnded();
        }

        if (!$.allowedTokens[token]) {
            revert NotAllowedToken(token);
        }

        if (amount == 0) {
            revert InvalidAmount(0, 0);
        }

        uint256 currentTime = block.timestamp;

        // Get initial balance to verify transfer
        uint256 initialBalance = token.balanceOf(address(this));

        // Transfer tokens from user
        token.safeTransferFrom(msg.sender, address(this), amount);

        // Verify transfer amount
        uint256 received = token.balanceOf(address(this)) - initialBalance;

        if (received != amount) {
            revert InvalidAmount(amount, received);
        }

        // Convert to base units (18 decimals) for internal accounting
        uint256 baseAmount = _toBaseUnits(amount, token);

        // Update state
        UserState storage userState = $.userStates[msg.sender];

        // Add new user to list if first deposit.
        // only checking lastUpdate = 0 would not work because user could have deposited and withdrawn so lastUpdate
        // would not be 0
        if (userState.lastUpdate == 0) {
            $.users.push(msg.sender);
        }

        // Update accumulated stake-time.
        if (userState.lastUpdate != 0) {
            userState.amountSeconds += userState.tokenAmounts[token] * (currentTime - userState.lastUpdate);
        }

        userState.lastUpdate = currentTime;
        userState.tokenAmounts[token] += baseAmount;
        $.totalAmountStaked[token] += baseAmount;

        emit Staked(msg.sender, token, amount);
    }

    /**
     * @notice Withdraw tokens from the BoringVaultPredeposit contract
     * @param amount Amount of tokens to withdraw
     * @param token Token contract address
     */
    function withdraw(uint256 amount, IERC20 token) external nonReentrant {
        BoringVaultPredepositStorage storage $ = _getBoringVaultPredepositStorage();
        if ($.endTime != 0) {
            revert StakingEnded();
        }

        if (amount == 0) {
            revert InvalidAmount(0, 0);
        }

        uint8 decimals = $.tokenDecimals[token];
        if (decimals == 0) {
            decimals = IERC20Metadata(address(token)).decimals();
        }
        uint256 conversionFactor = 10 ** (_BASE - decimals);

        UserState storage userState = $.userStates[msg.sender];
        uint256 requiredBase = amount * conversionFactor;
        if (userState.tokenAmounts[token] < requiredBase) {
            revert InsufficientStaked(msg.sender, token, requiredBase, userState.tokenAmounts[token]);
        }

        uint256 currentTime = block.timestamp;

        // Update accumulated stake-time.
        userState.amountSeconds += userState.tokenAmounts[token] * (currentTime - userState.lastUpdate);
        userState.lastUpdate = currentTime;

        uint256 initialBalance = token.balanceOf(address(this));
        token.safeTransfer(msg.sender, amount);
        uint256 finalBalance = token.balanceOf(address(this));
        uint256 actualBase = (initialBalance - finalBalance) * conversionFactor;

        // Adjust accumulated stake-time proportionally.
        uint256 prevAmountStaked = userState.tokenAmounts[token];
        userState.amountSeconds = (userState.amountSeconds * (prevAmountStaked - actualBase)) / prevAmountStaked;

        userState.tokenAmounts[token] -= actualBase;
        $.totalAmountStaked[token] -= actualBase;

        emit Withdrawn(msg.sender, token, actualBase);
    }

    /// @notice Deposits user's tokens into nYIELD vault and sends shares directly to user
    /// @param token The token to deposit
    /// @param minimumMint The minimum amount of shares to mint
    /// @return shares Amount of shares received
    function depositToVault(IERC20 token, uint256 minimumMint) external nonReentrant returns (uint256 shares) {
        BoringVaultPredepositStorage storage $ = _getBoringVaultPredepositStorage();

        BoringVault memory vault = $.vault;
        UserState storage userState = $.userStates[msg.sender];

        if (block.timestamp < $.vaultConversionStartTime) {
            revert ConversionNotStarted(block.timestamp, $.vaultConversionStartTime);
        }

        if (!$.allowedTokens[token]) {
            revert NotAllowedToken(token);
        }

        // Get user's token balance and convert to deposit amount
        uint256 tokenBaseAmount = userState.tokenAmounts[token];
        if (tokenBaseAmount == 0) {
            revert InvalidAmount(0, 0);
        }

        uint256 depositAmount = _fromBaseUnits(tokenBaseAmount, token);
        if (depositAmount == 0) {
            revert InvalidAmount(0, 0);
        }

        // Update accumulated stake-time before modifying state
        uint256 currentTime = block.timestamp;
        userState.amountSeconds += userState.tokenAmounts[token] * (currentTime - userState.lastUpdate);
        userState.lastUpdate = currentTime;

        // Update state before external calls
        userState.tokenAmounts[token] = 0;
        $.totalAmountStaked[token] -= tokenBaseAmount; // Update per token

        // Approve spending
        token.safeIncreaseAllowance(address(vault.teller), depositAmount);
        token.safeIncreaseAllowance(address(vault.vault), depositAmount);

        // Deposit and get shares
        shares = vault.teller.deposit(token, depositAmount, minimumMint);

        // Transfer and record shares
        IERC20(address(vault.vault)).safeTransfer(msg.sender, shares);
        userState.vaultShares[token] += shares;

        emit ConvertedToBoringVault(msg.sender, token, depositAmount, shares);
    }

    /// @notice Admin function to deposit multiple users' funds into vault and distribute shares
    /// @param recipients Array of addresses to receive vault shares
    /// @param tokens Array of tokens to deposit for each recipient
    /// @param amounts Array of amounts to deposit for each recipient
    /// @param minimumMintBps The minimum amount of shares to mint
    /// @return shares Array of share amounts received for each deposit
    function batchDepositToVault(
        address[] calldata recipients,
        IERC20[] calldata tokens,
        uint256[] calldata amounts,
        uint256 minimumMintBps
    ) external nonReentrant returns (uint256[] memory shares) {
        BoringVaultPredepositStorage storage $ = _getBoringVaultPredepositStorage();

        // If timelock is set, only timelock can call. Otherwise, only admin can call
        if (address($.timelock) != address(0)) {
            if (msg.sender != address($.timelock)) {
                revert Unauthorized(msg.sender, address($.timelock));
            }
        } else {
            if (!hasRole(ADMIN_ROLE, msg.sender)) {
                revert Unauthorized(msg.sender, $.multisig);
            }
        }

        BoringVault memory vault = $.vault;

        if (block.timestamp < $.vaultConversionStartTime) {
            revert ConversionNotStarted(block.timestamp, $.vaultConversionStartTime);
        }

        if (recipients.length != tokens.length || tokens.length != amounts.length) {
            revert ArrayLengthMismatch(recipients.length, tokens.length);
        }

        shares = new uint256[](recipients.length);
        uint256 currentTime = block.timestamp;

        for (uint256 i = 0; i < recipients.length; i++) {
            address recipient = recipients[i];
            IERC20 token = tokens[i];
            uint256 depositAmount = amounts[i];

            if (recipient == address(0)) {
                revert ZeroAddress();
            }
            if (depositAmount == 0) {
                revert InvalidAmount(0, 0);
            }
            if (!$.allowedTokens[token]) {
                revert NotAllowedToken(token);
            }

            // Get user's token balance and convert to base units
            UserState storage userState = $.userStates[recipient];
            uint256 tokenBaseAmount = userState.tokenAmounts[token];
            if (tokenBaseAmount == 0) {
                revert InvalidAmount(0, 0);
            }

            // Update accumulated stake-time before modifying state
            userState.amountSeconds += userState.tokenAmounts[token] * (currentTime - userState.lastUpdate);
            userState.lastUpdate = currentTime;

            // Update state before external calls
            userState.tokenAmounts[token] = 0;
            $.totalAmountStaked[token] -= tokenBaseAmount; // Update per token

            // Calculate minimum shares for this deposit
            uint256 minimumShares = (depositAmount * minimumMintBps) / 10_000;

            // Approve spending
            token.safeIncreaseAllowance(address(vault.teller), depositAmount);
            token.safeIncreaseAllowance(address(vault.vault), depositAmount);

            // Deposit and get shares
            uint256 mintedShares = vault.teller.deposit(token, depositAmount, minimumShares);
            shares[i] = mintedShares;

            // Transfer and record shares
            IERC20(address(vault.vault)).safeTransfer(recipient, mintedShares);
            $.userStates[recipient].vaultShares[token] += mintedShares;

            emit ConvertedToBoringVault(recipient, token, depositAmount, mintedShares);
        }
        return shares;
    }

    // Getter View Functions

    /// @notice Total amount of tokens staked in the BoringVaultPredeposit contract
    /// @param token The token to query
    /// @return uint256 The total amount of tokens staked in the BoringVaultPredeposit contract
    function getTotalAmountStaked(
        IERC20 token
    ) external view returns (uint256) {
        return _getBoringVaultPredepositStorage().totalAmountStaked[token];
    }

    /// @notice List of users who have staked into the BoringVaultPredeposit contract
    function getUsers() external view returns (address[] memory) {
        return _getBoringVaultPredepositStorage().users;
    }

    /// @notice Get user's state for all tokens
    /// @param user The address of the user
    /// @return tokens Array of token addresses
    /// @return states Array of UserTokenState structs containing amountSeconds and amount for each token
    /// @return lastUpdate Last update timestamp
    function getUserState(
        address user
    ) external view returns (IERC20[] memory tokens, UserTokenState[] memory states, uint256 lastUpdate) {
        BoringVaultPredepositStorage storage $ = _getBoringVaultPredepositStorage();
        UserState storage userState = $.userStates[user];

        tokens = $.tokens;
        states = new UserTokenState[](tokens.length);

        uint256 currentTime = block.timestamp;
        lastUpdate = userState.lastUpdate;

        // Calculate current amountSeconds and get token amounts for each token
        if (lastUpdate != 0) {
            for (uint256 i = 0; i < tokens.length; i++) {
                IERC20 token = tokens[i];
                uint256 tokenAmount = userState.tokenAmounts[token];

                states[i] = UserTokenState({
                    amountSeconds: userState.amountSeconds + tokenAmount * (currentTime - lastUpdate),
                    tokenAmount: tokenAmount
                });
            }
        }

        return (tokens, states, lastUpdate);
    }

    /// @notice Get user's state for a specific token
    /// @param user The address of the user
    /// @param token The token to query
    /// @return amountSeconds Amount-seconds for the specific token
    /// @return tokenAmount Amount of token staked
    /// @return lastUpdate Last update timestamp
    function getUserStateForToken(
        address user,
        IERC20 token
    ) external view returns (uint256 amountSeconds, uint256 tokenAmount, uint256 lastUpdate) {
        BoringVaultPredepositStorage storage $ = _getBoringVaultPredepositStorage();
        UserState storage state = $.userStates[user];

        uint256 currentTime = block.timestamp;
        tokenAmount = state.tokenAmounts[token];
        lastUpdate = state.lastUpdate;

        amountSeconds = state.amountSeconds;
        if (lastUpdate != 0) {
            amountSeconds += tokenAmount * (currentTime - lastUpdate);
        }

        return (amountSeconds, tokenAmount, lastUpdate);
    }

    /// @notice List of all tokens that have been added to the BoringVaultPredeposit contract
    function getTokenList() external view returns (IERC20[] memory) {
        return _getBoringVaultPredepositStorage().tokens;
    }

    /// @notice Whether a token is allowed to be staked in the BoringVaultPredeposit contract
    function isAllowedToken(
        IERC20 token
    ) external view returns (bool) {
        return _getBoringVaultPredepositStorage().allowedTokens[token];
    }

    /// @notice Timestamp of when pre-staking ends, when the admin withdraws all tokens
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

    /// @notice Returns the timestamp when vault conversion will be enabled
    /// @return uint256 The conversion start timestamp
    function getVaultConversionStartTime() external view returns (uint256) {
        return _getBoringVaultPredepositStorage().vaultConversionStartTime;
    }

    // Utility Functions

    /// @notice Returns the amount of tokens a user has staked
    /// @param user The address of the user
    /// @param token The token to query
    /// @return uint256 The amount of tokens in the token's native decimals
    function getUserTokenAmounts(address user, IERC20 token) external view returns (uint256) {
        return _getBoringVaultPredepositStorage().userStates[user].tokenAmounts[token];
    }

    /// @notice Returns the amount of vault shares a user has for a given token
    /// @param user The address of the user
    /// @param token The token to query
    /// @return uint256 The amount of vault shares
    function getUserVaultShares(address user, IERC20 token) external view returns (uint256) {
        BoringVaultPredepositStorage storage $ = _getBoringVaultPredepositStorage();
        return $.userStates[user].vaultShares[token];
    }

    /// @notice Converts an amount from token decimals to base units (18 decimals)
    /// @dev Used for internal accounting
    /// @param amount The amount to convert
    /// @param token The token whose decimals to use
    /// @return uint256 The amount in base units
    function _toBaseUnits(uint256 amount, IERC20 token) internal view returns (uint256) {
        BoringVaultPredepositStorage storage $ = _getBoringVaultPredepositStorage();
        uint8 tokenDec = $.tokenDecimals[token];
        if (tokenDec == 0) {
            tokenDec = IERC20Metadata(address(token)).decimals();
        }
        if (tokenDec == _BASE) {
            return amount;
        }
        return amount * (10 ** (_BASE - tokenDec));
    }

    /// @notice Converts an amount from base units (18 decimals) to token decimals
    /// @dev Used for external-facing functions
    /// @param amount The amount in base units to convert
    /// @param token The token whose decimals to convert to
    /// @return uint256 The amount in token decimals
    function _fromBaseUnits(uint256 amount, IERC20 token) internal view returns (uint256) {
        BoringVaultPredepositStorage storage $ = _getBoringVaultPredepositStorage();
        uint8 tokenDec = $.tokenDecimals[token];
        if (tokenDec == 0) {
            tokenDec = IERC20Metadata(address(token)).decimals();
        }
        if (tokenDec == _BASE) {
            return amount;
        }
        return amount / (10 ** (_BASE - tokenDec));
    }

    /**
     * @notice Returns the dynamic storage slot used by this contract.
     * @return The storage slot as a bytes32 value.
     */
    function getStorageSlot() external view returns (bytes32) {
        return _storageSlot;
    }

}
