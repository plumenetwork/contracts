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
 * @title nYieldStaking
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Pre-staking contract for nYIELD Staking on Plume
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

    error InsufficientBalance(uint256 available, uint256 required);

    error ConversionNotStarted(uint256 currentTime, uint256 startTime);

    event VaultConversionStartTimeSet(uint256 startTime);

    event StablecoinConvertedToVault(IERC20 stablecoin, IBoringVault vault, uint256 amount, uint256 shares);
    event UserBridgeOptInUpdated(address indexed user, IERC20 indexed stablecoin, bool optIn);
    event UserPositionBridged(address indexed user, IERC20 indexed stablecoin, uint256 shares);

    event UserConvertedToVault(
        address indexed user, IERC20 indexed stablecoin, ITeller vault, uint256 amount, uint256 shares
    );

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
    struct nYieldStakingStorage {
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
    bytes32 private constant NYIELD_STAKING_STORAGE_LOCATION =
        0x91fba57b99f8ab5feaeb3c341c9ead66b71426630d0f57b5ca97617e91ea5000;

    function _getnYieldStakingStorage() private pure returns (nYieldStakingStorage storage $) {
        assembly {
            $.slot := NYIELD_STAKING_STORAGE_LOCATION
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
        if (msg.sender != address(_getnYieldStakingStorage().timelock)) {
            revert Unauthorized(msg.sender, address(_getnYieldStakingStorage().timelock));
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

        nYieldStakingStorage storage $ = _getnYieldStakingStorage();
        $.multisig = owner;
        $.timelock = timelock;

        // Initialize BoringVault struct from parameters
        $.vault = boringVaultConfig;

        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(ADMIN_ROLE, owner);

        // Initialize with default stablecoins
        _allowStablecoin(IERC20(0x4c9EDD5852cd905f086C759E8383e09bff1E68B3)); // USDe
        _allowStablecoin(IERC20(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497)); // sUSDe
        _allowStablecoin(IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)); // USDC
        _allowStablecoin(IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7)); // USDT
    }

    /**
     * @notice Reinitialize the RWAStaking contract by adding the timelock and multisig contract address
     * @param multisig Multisig contract address
     * @param timelock Timelock contract address
     */
    function reinitialize(address multisig, TimelockController timelock) public reinitializer(2) onlyRole(ADMIN_ROLE) {
        nYieldStakingStorage storage $ = _getnYieldStakingStorage();
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
        _getnYieldStakingStorage().multisig = multisig;
    }

    function setVaultConversionStartTime(
        uint256 startTime
    ) external onlyRole(ADMIN_ROLE) {
        require(startTime > block.timestamp, "Start time must be in future");
        nYieldStakingStorage storage $ = _getnYieldStakingStorage();
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
        nYieldStakingStorage storage $ = _getnYieldStakingStorage();
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
        nYieldStakingStorage storage $ = _getnYieldStakingStorage();
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
    function adminBridge(ITeller teller, BridgeData calldata bridgeData) external nonReentrant onlyTimelock {
        nYieldStakingStorage storage $ = _getnYieldStakingStorage();
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
                teller.depositAndBridge{ value: fee }(ERC20(address(stablecoin)), amount, amount, bridgeData);
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
        nYieldStakingStorage storage $ = _getnYieldStakingStorage();
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
        nYieldStakingStorage storage $ = _getnYieldStakingStorage();
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
        nYieldStakingStorage storage $ = _getnYieldStakingStorage();
        if ($.endTime != 0) {
            revert StakingEnded();
        }
        if ($.paused) {
            revert DepositPaused();
        }
        if (!$.allowedStablecoins[stablecoin]) {
            revert NotAllowedStablecoin(stablecoin);
        }

        uint256 previousBalance = stablecoin.balanceOf(address(this));

        stablecoin.safeTransferFrom(msg.sender, address(this), amount);

        uint256 newBalance = stablecoin.balanceOf(address(this));
        // Convert the amount to the base unit of amount, i.e. USDC amount gets multiplied by 10^12
        uint256 actualAmount =
            (newBalance - previousBalance) * 10 ** (_BASE - IERC20Metadata(address(stablecoin)).decimals());

        uint256 timestamp = block.timestamp;
        UserState storage userState = $.userStates[msg.sender];
        if (userState.lastUpdate == 0) {
            $.users.push(msg.sender);
        }
        userState.amountSeconds += userState.amountStaked * (timestamp - userState.lastUpdate);
        userState.amountStaked += actualAmount;
        userState.lastUpdate = timestamp;
        userState.stablecoinAmounts[stablecoin] += actualAmount;
        $.totalAmountStaked += actualAmount;

        emit Staked(msg.sender, stablecoin, actualAmount);
    }

    /**
     * @notice Withdraw stablecoins from the RWAStaking contract
     * @param amount Amount of stablecoins to withdraw
     * @param stablecoin Stablecoin token contract address
     */
    function withdraw(uint256 amount, IERC20 stablecoin) external nonReentrant {
        nYieldStakingStorage storage $ = _getnYieldStakingStorage();
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
        return _getnYieldStakingStorage().totalAmountStaked;
    }

    /// @notice List of users who have staked into the RWAStaking contract
    function getUsers() external view returns (address[] memory) {
        return _getnYieldStakingStorage().users;
    }

    /// @notice State of a user who has staked into the RWAStaking contract
    function getUserState(
        address user
    ) external view returns (uint256 amountSeconds, uint256 amountStaked, uint256 lastUpdate) {
        nYieldStakingStorage storage $ = _getnYieldStakingStorage();
        UserState storage userState = $.userStates[user];
        return (
            userState.amountSeconds
                + userState.amountStaked * (($.endTime > 0 ? $.endTime : block.timestamp) - userState.lastUpdate),
            userState.amountStaked,
            userState.lastUpdate
        );
    }

    /// @notice Amount of stablecoins staked by a user for each stablecoin
    function getUserStablecoinAmounts(address user, IERC20 stablecoin) external view returns (uint256) {
        return _getnYieldStakingStorage().userStates[user].stablecoinAmounts[stablecoin];
    }

    /// @notice List of stablecoins allowed to be staked in the RWAStaking contract
    function getAllowedStablecoins() external view returns (IERC20[] memory) {
        return _getnYieldStakingStorage().stablecoins;
    }

    /// @notice Whether a stablecoin is allowed to be staked in the RWAStaking contract
    function isAllowedStablecoin(
        IERC20 stablecoin
    ) external view returns (bool) {
        return _getnYieldStakingStorage().allowedStablecoins[stablecoin];
    }

    /// @notice Timestamp of when pre-staking ends, when the admin withdraws all stablecoins
    function getEndTime() external view returns (uint256) {
        return _getnYieldStakingStorage().endTime;
    }

    /// @notice Returns true if the RWAStaking contract is pauseWhether the RWAStaking contract is paused for deposits
    function isPaused() external view returns (bool) {
        return _getnYieldStakingStorage().paused;
    }

    /// @notice Multisig address that withdraws the tokens and proposes/executes Timelock transactions
    function getMultisig() external view returns (address) {
        return _getnYieldStakingStorage().multisig;
    }

    /// @notice Timelock contract that controls upgrades and withdrawals
    function getTimelock() external view returns (TimelockController) {
        return _getnYieldStakingStorage().timelock;
    }

    function convertToBoringVault(IERC20 stablecoin, ITeller teller, uint256 amount) external {
        nYieldStakingStorage storage $ = _getnYieldStakingStorage();

        // Check if conversion period has started
        if (block.timestamp < $.vaultConversionStartTime) {
            revert ConversionNotStarted(block.timestamp, $.vaultConversionStartTime);
        }

        UserState storage userState = $.userStates[msg.sender];

        // Verify stablecoin is allowed
        if (!$.allowedStablecoins[stablecoin]) {
            revert NotAllowedStablecoin(stablecoin);
        }

        // Check user has enough balance
        uint256 userBalance = userState.stablecoinAmounts[stablecoin];
        if (userBalance < amount) {
            revert InsufficientBalance(userBalance, amount);
        }

        // Approve stablecoin transfer
        stablecoin.approve(address(teller), amount);

        // Deposit into teller and receive shares
        uint256 minimumMint = 0; // Can be parameterized if needed
        uint256 receivedShares = teller.deposit(
            ERC20(address(stablecoin)), // depositAsset
            amount, // depositAmount
            minimumMint // minimumMint
        );

        // Update user's stablecoin and share balances
        userState.stablecoinAmounts[stablecoin] -= amount;
        $.userVaultShares[msg.sender][stablecoin] += receivedShares;
        $.vaultTotalShares[stablecoin] += receivedShares;

        emit UserConvertedToVault(msg.sender, stablecoin, teller, amount, receivedShares);
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
        nYieldStakingStorage storage $ = _getnYieldStakingStorage();

        // Get the teller
        ITeller teller = ITeller(address($.stablecoinToVault[stablecoin]));
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

    function getVaultConversionStartTime() external view returns (uint256) {
        return _getnYieldStakingStorage().vaultConversionStartTime;
    }

    /*
    function adminConvertToBoringVault(IERC20 stablecoin, IBoringVault vault, uint256 amount) external onlyTimelock {
        nYieldStakingStorage storage $ = _getnYieldStakingStorage();

        // Verify stablecoin is allowed
        if (!$.allowedStablecoins[stablecoin]) {
            revert NotAllowedStablecoin(stablecoin);
        }

        // Ensure we have enough stablecoins
        uint256 balance = stablecoin.balanceOf(address(this));
        if (balance < amount) {
            revert InsufficientBalance(balance, amount);
        }

        // Set vault for stablecoin if not already set
        if (address($.stablecoinToVault[stablecoin]) == address(0)) {
            $.stablecoinToVault[stablecoin] = vault;
        }

        // Calculate shares to mint
        uint256 totalAssets = vault.totalAssets();
        uint256 totalShares = vault.totalSupply();
        uint256 sharesToMint;

        if (totalShares == 0) {
            sharesToMint = amount; // 1:1 for first deposit
        } else {
            sharesToMint = (amount * totalShares) / totalAssets;
        }

        // Approve stablecoin transfer
        stablecoin.approve(address(vault), amount);

        // Enter vault position
        vault.enter(
            address(this), // from
            ERC20(address(stablecoin)), // asset
            amount, // assetAmount
            address(this), // to
            sharesToMint // shareAmount
        );

        // Update total shares
        $.vaultTotalShares[stablecoin] += sharesToMint;

        // Distribute shares proportionally to users based on their stablecoin amounts
        address[] memory stakingUsers = $.users;
        uint256 totalStaked = 0;

        // First get total staked amount for this stablecoin
        for (uint256 i = 0; i < stakingUsers.length; i++) {
            totalStaked += $.userStates[stakingUsers[i]].stablecoinAmounts[stablecoin];
        }

        // Then distribute shares proportionally
        if (totalStaked > 0) {
            for (uint256 i = 0; i < stakingUsers.length; i++) {
                address user = stakingUsers[i];
                uint256 userStablecoinAmount = $.userStates[user].stablecoinAmounts[stablecoin];

                if (userStablecoinAmount > 0) {
                    uint256 userShares = (sharesToMint * userStablecoinAmount) / totalStaked;
                    $.userVaultShares[user][stablecoin] += userShares;
                }
            }
        }

        emit StablecoinConvertedToVault(stablecoin, vault, amount, sharesToMint);
    }
    
    function userOptInToBridge(IERC20 stablecoin, bool optIn) external {
        // Allow users to opt in/out of bridging
        console.log("userOptInToBridge");
    }

    function adminBridgeSelected(
        ITeller teller,
        BridgeData calldata bridgeData,
        address[] calldata users,
        IERC20 stablecoin
    ) external onlyTimelock {
        // Bridge only selected users' positions
        console.log("adminBridgeSelected");
    }

    function getUserPositionStatus(
        address user,
        IERC20 stablecoin
    ) external view returns (uint256 depositedAmount, uint256 boringVaultShares, bool isBridged) {
        console.log("getUserPositionStatus");
    }
    */

}
