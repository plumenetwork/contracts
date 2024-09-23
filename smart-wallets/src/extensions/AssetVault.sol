// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAssetToken } from "../interfaces/IAssetToken.sol";
import { IAssetVault } from "../interfaces/IAssetVault.sol";
import { ISmartWallet } from "../interfaces/ISmartWallet.sol";

/**
 * @title AssetVault
 * @author Eugene Y. Q. Shen
 * @notice Smart wallet extension on Plume that allows users to lock yield-bearing assets
 *   in a vault, then take the yield distributed to those locked yield-bearing assets
 *   and manage the redistribution of that yield to multiple beneficiaries.
 */
contract AssetVault is IAssetVault {

    // Types

    /**
     * @notice Yield of some amount that expires at some time
     * @dev Can be used to represent both yield allowances and yield distributions
     */
    struct Yield {
        /// @dev Amount of asset tokens that are locked for this yield, must always be positive
        uint256 amount;
        /// @dev Timestamp at which the yield expires
        uint256 expiration;
    }

    /// @notice Item in a linked list of yield distributions
    struct YieldDistributionListItem {
        /// @dev Address of the beneficiary of the yield distribution
        address beneficiary;
        /// @dev Yield represented by the yield distribution
        Yield yield;
        /// @dev Next YieldDistributionListItem in the linked list
        YieldDistributionListItem[] next; // Use array to avoid recursive struct definition error
    }

    // Storage

    /// @custom:storage-location erc7201:plume.storage.AssetVault
    struct AssetVaultStorage {
        /// @dev Mapping of yield allowances for each asset token and beneficiary
        mapping(IAssetToken assetToken => mapping(address beneficiary => Yield allowance)) yieldAllowances;
        /// @dev Mapping of the yield distribution list for each asset token
        mapping(IAssetToken assetToken => YieldDistributionListItem distribution) yieldDistributions;
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.AssetVault")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ASSET_VAULT_STORAGE_LOCATION =
        0x8705cfd43fb7e30ae97a9cbbffbf82f7d6cb80ad243d5fc52988024cb47c5700;

    function _getAssetVaultStorage() private pure returns (AssetVaultStorage storage $) {
        assembly {
            $.slot := ASSET_VAULT_STORAGE_LOCATION
        }
    }

    // Constants

    /// @notice Address of the user smart wallet that contains this AssetVault extension
    address public immutable wallet;

    /**
     * @dev Maximum amount of gas used in each iteration of the loops.
     *   We keep iterating until we have less than this much gas left,
     *   then we stop the loop so that we do not reach the gas limit.
     */
    uint256 private constant MAX_GAS_PER_ITERATION = 50_000;

    // Events

    /**
     * @notice Emitted when the user wallet updates a yield allowance
     * @param assetToken AssetToken from which the yield is to be redistributed
     * @param beneficiary Address of the beneficiary of the yield allowance
     * @param amount Amount of AssetTokens that are locked for this yield
     * @param expiration Timestamp at which the yield expires
     */
    event YieldAllowanceUpdated(
        IAssetToken indexed assetToken, address indexed beneficiary, uint256 amount, uint256 expiration
    );

    /**
     * @notice Emitted when the user wallet redistributes yield to the beneficiaries
     * @param assetToken AssetToken from which the yield was redistributed
     * @param beneficiary Address of the beneficiary that received the yield redistribution
     * @param currencyToken Token in which the yield was redistributed
     * @param yieldShare Amount of currencyToken that was redistributed to the beneficiary
     */
    event YieldRedistributed(
        IAssetToken indexed assetToken, address indexed beneficiary, IERC20 indexed currencyToken, uint256 yieldShare
    );

    /**
     * @notice Emitted when a beneficiary accepts a yield allowance and creates a new yield distribution
     * @param assetToken AssetToken from which the yield is to be redistributed
     * @param beneficiary Address of the beneficiary of the yield distribution
     * @param amount Amount of AssetTokens that are locked for this yield
     * @param expiration Timestamp at which the yield expires
     */
    event YieldDistributionCreated(
        IAssetToken indexed assetToken, address indexed beneficiary, uint256 amount, uint256 expiration
    );

    /**
     * @notice Emitted when a beneficiary renounces their yield distributions
     * @param assetToken AssetToken from which the yield is to be redistributed
     * @param beneficiary Address of the beneficiary of the yield distribution
     * @param amount Amount of AssetTokens that are renounced from the yield distributions of the beneficiary
     */
    event YieldDistributionRenounced(IAssetToken indexed assetToken, address indexed beneficiary, uint256 amount);

    /**
     * @notice Emitted when anyone clears expired yield distributions from the linked list
     * @param assetToken AssetToken from which the yield is to be redistributed
     * @param amountCleared Amount of AssetTokens that were cleared from the yield distributions
     */
    event YieldDistributionsCleared(IAssetToken indexed assetToken, uint256 amountCleared);

    // Errors

    /// @notice Indicates a failure because the given address is 0x0
    error ZeroAddress();

    /// @notice Indicates a failure because the given amount is 0
    error ZeroAmount();

    /**
     * @notice Indicates a failure because the given expiration timestamp is too old
     * @param expiration Expiration timestamp that was too old
     * @param currentTimestamp Current block.timestamp
     */
    error InvalidExpiration(uint256 expiration, uint256 currentTimestamp);

    /**
     * @notice Indicates a failure because the given expiration does not match the actual one
     * @param invalidExpiration Expiration timestamp that does not match the actual expiration
     * @param expiration Actual expiration timestamp at which the yield expires
     */
    error MismatchedExpiration(uint256 invalidExpiration, uint256 expiration);

    /**
     * @notice Indicates a failure because the beneficiary does not have enough yield allowances
     * @param assetToken AssetToken from which the yield is to be redistributed
     * @param beneficiary Address of the beneficiary of the yield allowance
     * @param allowanceAmount Amount of assetTokens included in this yield allowance
     * @param amount Amount of assetTokens that the beneficiary tried to accept the yield of
     */
    error InsufficientYieldAllowance(
        IAssetToken assetToken, address beneficiary, uint256 allowanceAmount, uint256 amount
    );

    /**
     * @notice Indicates a failure because the user wallet does not have enough AssetTokens
     * @param assetToken AssetToken for which a new yield distribution is to be made
     * @param amount Amount of assetTokens that the user wallet tried to add to the distribution
     */
    error InsufficientBalance(IAssetToken assetToken, uint256 amount);

    /**
     * @notice Indicates a failure because the beneficiary does not have enough yield distributions
     * @param assetToken AssetToken from which the yield is to be redistributed
     * @param beneficiary Address of the beneficiary of the yield distributions
     * @param amount Amount of assetTokens included in all of their yield distributions
     * @param amountRenounced Amount of assetTokens that the beneficiary tried to renounce the yield of
     */
    error InsufficientYieldDistributions(
        IAssetToken assetToken, address beneficiary, uint256 amount, uint256 amountRenounced
    );

    /**
     * @notice Indicates a failure because the caller is not the user wallet
     * @param invalidUser Address of the caller who tried to call a wallet-only function
     */
    error UnauthorizedCall(address invalidUser);

    // Modifiers

    /// @notice Only the user wallet can call this function
    modifier onlyWallet() {
        if (msg.sender != wallet) {
            revert UnauthorizedCall(msg.sender);
        }
        _;
    }

    // Constructor

    /**
     * @notice Construct the AssetVault extension
     * @dev The sender of the transaction creates an AssetVault for themselves,
     *   and their address is saved as the public immutable variable `wallet`.
     */
    constructor() {
        wallet = msg.sender;
    }

    // User Wallet Functions

    /**
     * @notice Update the yield allowance of the given beneficiary
     * @dev Only the user wallet can update yield allowances for tokens in their own AssetVault
     * @param assetToken AssetToken from which the yield is to be redistributed
     * @param beneficiary Address of the beneficiary of the yield allowance
     * @param amount Amount of assetTokens to be locked for this yield allowance
     * @param expiration Timestamp at which the yield expires
     */
    function updateYieldAllowance(
        IAssetToken assetToken,
        address beneficiary,
        uint256 amount,
        uint256 expiration
    ) external onlyWallet {
        if (address(assetToken) == address(0) || beneficiary == address(0)) {
            revert ZeroAddress();
        }
        if (amount == 0) {
            revert ZeroAmount();
        }
        if (expiration <= block.timestamp) {
            revert InvalidExpiration(expiration, block.timestamp);
        }

        Yield storage allowance = _getAssetVaultStorage().yieldAllowances[assetToken][beneficiary];
        allowance.amount = amount;
        allowance.expiration = expiration;

        emit YieldAllowanceUpdated(assetToken, beneficiary, amount, expiration);
    }

    /**
     * @notice Redistribute yield to the beneficiaries of the asset token, using yield distributions
     * @dev Only the user wallet can initiate the yield redistribution. The yield redistributed
     *   to each beneficiary is rounded down, and any remaining currencyTokens are kept in the vault.
     * @param assetToken AssetToken from which the yield is to be redistributed
     * @param currencyToken Token in which the yield is to be redistributed
     * @param currencyTokenAmount Amount of currencyToken to redistribute
     */
    function redistributeYield(
        IAssetToken assetToken,
        IERC20 currencyToken,
        uint256 currencyTokenAmount
    ) external onlyWallet {
        if (currencyTokenAmount == 0) {
            return;
        }

        uint256 amountTotal = assetToken.balanceOf(wallet);

        // Iterate through the list and transfer yield to the beneficiary for each yield distribution
        YieldDistributionListItem storage distribution = _getAssetVaultStorage().yieldDistributions[assetToken];
        uint256 amountLocked = distribution.yield.amount;
        while (amountLocked > 0) {
            if (distribution.yield.expiration > block.timestamp) {
                uint256 yieldShare = (currencyTokenAmount * amountLocked) / amountTotal;
                // TODO transfer yield from the user wallet to the beneficiary
                emit YieldRedistributed(assetToken, distribution.beneficiary, currencyToken, yieldShare);
            }

            distribution = distribution.next[0];
            amountLocked = distribution.yield.amount;
        }
    }

    // Permissionless Functions

    /**
     * @notice Get the number of AssetTokens that are currently locked in the AssetVault
     * @param assetToken AssetToken from which the yield is to be redistributed
     */
    function getBalanceLocked(IAssetToken assetToken) external view returns (uint256 balanceLocked) {
        // Iterate through the list and sum up the locked balance across all yield distributions
        YieldDistributionListItem storage distribution = _getAssetVaultStorage().yieldDistributions[assetToken];
        while (true) {
            if (distribution.yield.expiration > block.timestamp) {
                balanceLocked += distribution.yield.amount;
            }
            if (distribution.next.length > 0) {
                distribution = distribution.next[0];
            } else {
                break;
            }
        }

        return balanceLocked;
    }

    /**
     * @notice Accept the yield allowance and create a new yield distribution
     * @dev The beneficiary must call this function to accept the yield allowance
     * @param assetToken AssetToken from which the yield is to be redistributed
     * @param amount Amount of AssetTokens included in this yield allowance
     * @param expiration Timestamp at which the yield expires
     */
    function acceptYieldAllowance(IAssetToken assetToken, uint256 amount, uint256 expiration) external {
        AssetVaultStorage storage $ = _getAssetVaultStorage();
        address beneficiary = msg.sender;
        Yield storage allowance = $.yieldAllowances[assetToken][beneficiary];

        if (amount == 0) {
            revert ZeroAmount();
        }
        if (expiration <= block.timestamp) {
            revert InvalidExpiration(expiration, block.timestamp);
        }
        if (allowance.expiration != expiration) {
            revert MismatchedExpiration(allowance.expiration, expiration);
        }
        if (allowance.amount < amount) {
            revert InsufficientYieldAllowance(assetToken, beneficiary, allowance.amount, amount);
        }
        if (assetToken.getBalanceAvailable(address(this)) < amount) {
            revert InsufficientBalance(assetToken, amount);
        }

        allowance.amount -= amount;

        // Either update the existing distribution with the same expiration or append a new one
        YieldDistributionListItem storage distribution = $.yieldDistributions[assetToken];
        while (true) {
            if (distribution.beneficiary == beneficiary && distribution.yield.expiration == expiration) {
                distribution.yield.amount += amount;
                emit YieldDistributionCreated(assetToken, beneficiary, amount, expiration);
                return;
            }
            if (distribution.next.length > 0) {
                distribution = distribution.next[0];
            } else {
                distribution.next.push();
                distribution = distribution.next[0];
                break;
            }
        }
        distribution.beneficiary = beneficiary;
        distribution.yield.amount = amount;
        distribution.yield.expiration = expiration;

        emit YieldDistributionCreated(assetToken, beneficiary, amount, expiration);
    }

    /**
     * @notice Renounce the given amount of AssetTokens from the beneficiary's yield distributions
     * @dev The beneficiary must call this function to reduce the size of their yield distributions.
     *   If there are too many yield distributions to process, the function will stop to avoid
     *   reaching the gas limit, and the beneficiary must call the function again to renounce more.
     * @param assetToken AssetToken from which the yield is to be redistributed
     * @param amount Amount of AssetTokens to renounce from from the yield distribution
     * @param expiration Timestamp at which the yield expires
     */
    function renounceYieldDistribution(
        IAssetToken assetToken,
        uint256 amount,
        uint256 expiration
    ) external returns (uint256 amountRenounced) {
        YieldDistributionListItem storage distribution = _getAssetVaultStorage().yieldDistributions[assetToken];
        address beneficiary = msg.sender;
        uint256 amountLeft = amount;

        // Iterate through the list and subtract the amount from the beneficiary's yield distributions
        uint256 amountLocked = distribution.yield.amount;
        while (amountLocked > 0) {
            if (distribution.beneficiary == beneficiary && distribution.yield.expiration == expiration) {
                // If the entire yield distribution is to be renounced, then set its timestamp
                // to be in the past so it is cleared on the next run of `clearYieldDistributions`
                if (amountLeft >= amountLocked) {
                    amountLeft -= amountLocked;
                    distribution.yield.expiration = block.timestamp - 1 days;
                    if (amountLeft == 0) {
                        break;
                    }
                } else {
                    distribution.yield.amount -= amountLeft;
                    amountLeft = 0;
                    break;
                }
            }

            if (gasleft() < MAX_GAS_PER_ITERATION) {
                emit YieldDistributionRenounced(assetToken, beneficiary, amount - amountLeft);
                return amount - amountLeft;
            }
            distribution = distribution.next[0];
            amountLocked = distribution.yield.amount;
        }

        if (amountLeft > 0) {
            revert InsufficientYieldDistributions(assetToken, beneficiary, amount - amountLeft, amount);
        }
        emit YieldDistributionRenounced(assetToken, beneficiary, amount);
        return amount;
    }

    /**
     * @notice Clear expired yield distributions from the linked list
     * @dev Anyone can call this function to free up unused storage for gas refunds.
     *   If there are too many yield distributions to process, the function will stop to avoid
     *   reaching the gas limit, and the caller must call the function again to clear more.
     * @param assetToken AssetToken from which the yield is to be redistributed
     */
    function clearYieldDistributions(IAssetToken assetToken) external {
        uint256 amountCleared = 0;

        // Iterate through the list and delete all expired yield distributions
        YieldDistributionListItem storage distribution = _getAssetVaultStorage().yieldDistributions[assetToken];
        while (distribution.yield.amount > 0) {
            YieldDistributionListItem storage nextDistribution = distribution.next[0];
            if (distribution.yield.expiration <= block.timestamp) {
                amountCleared += distribution.yield.amount;
                distribution.beneficiary = nextDistribution.beneficiary;
                distribution.yield = nextDistribution.yield;
                distribution.next[0] = nextDistribution.next[0];
            } else {
                distribution = nextDistribution;
            }

            if (gasleft() < MAX_GAS_PER_ITERATION) {
                emit YieldDistributionsCleared(assetToken, amountCleared);
                return;
            }
        }
        emit YieldDistributionsCleared(assetToken, amountCleared);
    }

}
