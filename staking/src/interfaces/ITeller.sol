// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @dev Bridge data structure containing parameters needed for cross-chain transfer
 * @param destinationChainId The chain ID of the destination network
 * @param recipient The address receiving the shares on the destination chain
 * @param data Additional data required by the bridge implementation
 */
struct BridgeData {
    uint32 chainSelector;
    address destinationChainReceiver;
    IERC20 bridgeFeeToken;
    uint64 messageGas;
    bytes data;
}

/**
 * @title ITeller
 * @notice Interface for interacting with the Teller contract which manages vault deposits and withdrawals
 */
interface ITeller {

    // ========== Structs ==========
    struct Asset {
        bool allowDeposits;
        bool allowWithdraws;
        uint16 sharePremium;
    }

    // ========== Events ==========
    event Paused();
    event Unpaused();
    event AssetDataUpdated(address indexed asset, bool allowDeposits, bool allowWithdraws, uint16 sharePremium);
    event Deposit(
        uint256 indexed nonce,
        address indexed receiver,
        address indexed depositAsset,
        uint256 depositAmount,
        uint256 shareAmount,
        uint256 depositTimestamp,
        uint256 shareLockPeriodAtTimeOfDeposit
    );
    event BulkDeposit(address indexed asset, uint256 depositAmount);
    event BulkWithdraw(address indexed asset, uint256 shareAmount);
    event DepositRefunded(uint256 indexed nonce, bytes32 depositHash, address indexed user);

    // ========== View Functions ==========

    /**
     * @notice Check if deposits are currently paused
     * @return bool indicating if deposits are paused
     */
    function isPaused() external view returns (bool);

    /**
     * @notice Calculates the fee for bridging shares
     * @dev Returns the fee amount in share tokens that will be charged for bridging
     * @param shareAmount The amount of shares being bridged
     * @param data The bridge data containing destination chain and other parameters
     * @return fee The calculated fee amount in share tokens
     */
    function previewFee(uint256 shareAmount, BridgeData calldata data) external view returns (uint256 fee);

    /**
     * @notice Deposits an asset and bridges the resulting shares to another chain
     * @dev Requires authorization and implements reentrancy protection
     * @param depositAsset The ERC20 token being deposited
     * @param depositAmount The amount of tokens to deposit
     * @param minimumMint The minimum amount of shares that must be minted, reverts if not met
     * @param data Bridge data containing destination chain information
     * @custom:throws TellerWithMultiAssetSupport__AssetNotSupported if depositAsset is not supported
     */
    function depositAndBridge(
        ERC20 depositAsset,
        uint256 depositAmount,
        uint256 minimumMint,
        BridgeData calldata data
    ) external payable;

    /**
     * @notice Check if an asset is supported for deposits/withdrawals
     * @param asset The asset to check support for
     * @return bool indicating if the asset is supported
     */
    function isSupported(
        IERC20 asset
    ) external view returns (bool);

    /**
     * @notice Get asset configuration data
     * @param asset The asset to get data for
     * @return Asset struct containing configuration data
     */
    function assetData(
        IERC20 asset
    ) external view returns (Asset memory);

    /**
     * @notice Get the current share lock period
     * @return uint64 The period shares are locked for after deposit
     */
    function shareLockPeriod() external view returns (uint64);

    /**
     * @notice Get when a user's shares will be unlocked
     * @param user The address to check unlock time for
     * @return uint256 The timestamp when shares will unlock
     */
    function shareUnlockTime(
        address user
    ) external view returns (uint256);

    // ========== State Changing Functions ==========

    /**
     * @notice Deposit assets into the vault
     * @param depositAsset The asset being deposited
     * @param depositAmount The amount of asset to deposit
     * @param minimumMint The minimum amount of shares to receive
     * @return shares The amount of shares minted
     */
    function deposit(
        IERC20 depositAsset,
        uint256 depositAmount,
        uint256 minimumMint
    ) external payable returns (uint256 shares);

    /**
     * @notice Deposit assets using permit
     * @param depositAsset The asset being deposited
     * @param depositAmount The amount of asset to deposit
     * @param minimumMint The minimum amount of shares to receive
     * @param deadline The deadline for the permit
     * @param v v component of signature
     * @param r r component of signature
     * @param s s component of signature
     * @return shares The amount of shares minted
     */
    function depositWithPermit(
        IERC20 depositAsset,
        uint256 depositAmount,
        uint256 minimumMint,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 shares);

    /**
     * @notice Bulk deposit function for solvers
     * @param depositAsset The asset being deposited
     * @param depositAmount The amount of asset to deposit
     * @param minimumMint The minimum amount of shares to receive
     * @param to The recipient of the shares
     * @return shares The amount of shares minted
     */
    function bulkDeposit(
        IERC20 depositAsset,
        uint256 depositAmount,
        uint256 minimumMint,
        address to
    ) external returns (uint256 shares);

    /**
     * @notice Bulk withdraw function for solvers
     * @param withdrawAsset The asset to receive
     * @param shareAmount The amount of shares to burn
     * @param minimumAssets The minimum amount of assets to receive
     * @param to The recipient of the assets
     * @return assetsOut The amount of assets withdrawn
     */
    function bulkWithdraw(
        IERC20 withdrawAsset,
        uint256 shareAmount,
        uint256 minimumAssets,
        address to
    ) external returns (uint256 assetsOut);

    /**
     * @notice Refund a deposit during the lock period
     * @param nonce The deposit nonce
     * @param receiver The original receiver of shares
     * @param depositAsset The asset that was deposited
     * @param depositAmount The amount that was deposited
     * @param shareAmount The amount of shares minted
     * @param depositTimestamp When the deposit occurred
     * @param shareLockUpPeriodAtTimeOfDeposit The lock period at time of deposit
     */
    function refundDeposit(
        uint256 nonce,
        address receiver,
        address depositAsset,
        uint256 depositAmount,
        uint256 shareAmount,
        uint256 depositTimestamp,
        uint256 shareLockUpPeriodAtTimeOfDeposit
    ) external;

}
