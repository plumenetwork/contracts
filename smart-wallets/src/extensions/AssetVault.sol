// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAssetToken } from "../interfaces/IAssetToken.sol";
import { ISmartWallet } from "../interfaces/ISmartWallet.sol";

/**
 * @title AssetVault
 * @author Eugene Y. Q. Shen
 * @notice Smart wallet extension on Plume that allows users to lock yield-bearing assets
 *   in a vault, then take the yield distributed to those locked yield-bearing assets
 *   and manage the redistribution of that yield to multiple beneficiaries.
 * @dev Invariant: yield.amount > 0 for all Yield items
 */
contract AssetVault {

    // Types

    /// @notice Yield of some amount that expires at some time
    struct Yield {
        /// @dev Amount of asset tokens that are locked for this yield, must always be positive
        uint256 amount;
        /// @dev Timestamp at which the yield expires
        uint256 expiresAt;
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
        mapping(address assetToken => mapping(address beneficiary => Yield)) yieldAllowances;
        /// @dev Mapping of the yield distribution list for each asset token
        mapping(address assetToken => YieldDistributionListItem) yieldDistributions;
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.AssetVault")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ASSET_VAULT_STORAGE_LOCATION =
        0x8705cfd43fb7e30ae97a9cbbffbf82f7d6cb80ad243d5fc52988024cb47c5700;

    function _getAssetVaultStorage() private pure returns (AssetVaultStorage storage $) {
        assembly {
            $.slot := ASSET_VAULT_STORAGE_LOCATION
        }
    }

    // Events

    // Errors

    /// @notice Indicates that the caller is not the wallet
    error UnauthorizedCall();

    // Modifiers

    /// @notice Only the user wallet can call this function
    modifier onlyWallet() {
        if (msg.sender != wallet) {
            revert UnauthorizedCall();
        }

        _;
    }

    // Functions

    /// @notice Address of the smart wallet that contains this AssetVault extension
    address public immutable wallet;

    /**
     * @notice Construct the AssetVault extension
     * @dev The sender of the transaction creates an AssetVault for themselves,
     *   and their address is saved as the public immutable variable `wallet`.
     */
    constructor() {
        wallet = msg.sender;
    }

    /**
     * @notice Returns the locked asset token balance for the given asset token
     * @param assetToken The asset token address
     * @return lockedBalance The locked asset token balance
     */
    function getLockedAssetTokenBalance(address assetToken) public view returns (uint256 lockedBalance) {
        YieldDistributionListItem storage distribution = _getAssetVaultStorage().yieldDistributions[assetToken];
        uint256 lockedAmount = distribution.yield.amount;

        while (lockedAmount > 0) {
            if (distribution.yield.expiresAt > block.timestamp) {
                lockedBalance += lockedAmount;
            }

            distribution = distribution.next[0];
            lockedAmount = distribution.yield.amount;
        }
    }

    /**
     * @notice Approve yield distribution for the given asset token
     * @dev This function can only be called by the wallet
     * @param assetToken The asset token address
     * @param beneficiary The beneficiary address
     * @param amount The yield amount
     * @param expiresAt The expiry timestamp
     */
    function approveYieldDistribution(
        address assetToken,
        address beneficiary,
        uint256 amount,
        uint256 expiresAt
    ) public onlyWallet {
        require(assetToken != address(0), "AssetVault: Invalid asset token address");
        require(beneficiary != address(0), "AssetVault: Invalid beneficiary address");
        require(amount > 0, "AssetVault: Invalid yield amount");
        require(expiresAt > block.timestamp, "AssetVault: Invalid yield expiry");

        Yield storage yieldAllowance = _getAssetVaultStorage().yieldAllowances[assetToken][beneficiary];
        yieldAllowance.amount = amount;
        yieldAllowance.expiresAt = expiresAt;
    }

    /**
     * @notice Accept yield distribution for the given asset token
     * @dev The beneficiary must call this function to accept the yield distribution
     * @param assetToken The asset token address
     * @param amount The yield amount
     * @param expiresAt The expiry timestamp
     */
    function acceptYieldDistribution(address assetToken, uint256 amount, uint256 expiresAt) external {
        address beneficiary = msg.sender;
        Yield storage yieldAllowance = _getAssetVaultStorage().yieldAllowances[assetToken][beneficiary];

        require(amount > 0, "AssetVault: Invalid yield amount");
        require(yieldAllowance.amount >= amount, "AssetVault: Insufficient yield allowance");
        require(yieldAllowance.expiresAt == expiresAt, "AssetVault: Invalid yield expiry");
        require(expiresAt > block.timestamp, "AssetVault: Yield expired");
        require(
            IAssetToken(assetToken).availableBalanceOf(address(this)) >= amount,
            "AssetVault: Insufficient available asset token balance"
        );

        yieldAllowance.amount -= amount;

        YieldDistributionListItem storage yieldListItem = _getAssetVaultStorage().yieldDistributions[assetToken];

        // find the last empty yield distribution
        while (yieldListItem.yield.amount > 0) {
            yieldListItem = yieldListItem.next[0];
        }

        yieldListItem.beneficiary = beneficiary;
        yieldListItem.yield.amount = amount;
        yieldListItem.yield.expiresAt = expiresAt;
    }

    /**
     * @notice Clear expired yield distributions for the given asset token
     * @param assetToken The asset token address
     */
    function clearYieldDistribution(address assetToken) external {
        YieldDistributionListItem storage yieldListItem = _getAssetVaultStorage().yieldDistributions[assetToken];

        while (yieldListItem.yield.amount > 0) {
            YieldDistributionListItem storage nextYieldDistributionListItem = yieldListItem.next[0];

            // clear expired yield distributions
            if (yieldListItem.yield.expiresAt <= block.timestamp) {
                yieldListItem.beneficiary = nextYieldDistributionListItem.beneficiary;
                yieldListItem.yield = nextYieldDistributionListItem.yield;
                // TODO test if linked list is updated correctly
                yieldListItem.next[0] = nextYieldDistributionListItem.next[0];
            } else {
                yieldListItem = nextYieldDistributionListItem;
            }

            if (gasleft() < 20_000) {
                return;
            }
        }
    }

    /**
     * @notice Distribute yield for the given asset token
     * @dev AssetVault will call transferYield function of the wallet
     * @param assetToken The asset token address
     * @param yieldCurrency The yield token address
     * @param yieldAmount The yield amount
     */
    function processYieldDistribution(
        address assetToken,
        address yieldCurrency,
        uint256 yieldAmount
    ) external onlyWallet {
        if (yieldAmount == 0) {
            return;
        }

        uint256 totalTokenAmount = IERC20(assetToken).balanceOf(msg.sender);

        YieldDistributionListItem storage yieldListItem = _getAssetVaultStorage().yieldDistributions[assetToken];
        uint256 lockedAmount = yieldListItem.yield.amount;

        while (lockedAmount > 0) {
            if (yieldListItem.yield.expiresAt > block.timestamp) {
                uint256 yieldShare = (yieldAmount * lockedAmount) / totalTokenAmount;

                ISmartWallet(wallet).transferYield(assetToken, yieldCurrency, yieldListItem.beneficiary, yieldShare);
            }

            yieldListItem = yieldListItem.next[0];
            lockedAmount = yieldListItem.yield.amount;
        }
    }

    /**
     * @notice Release yield distribution for the given asset token
     * @dev The beneficiary must call this function to release the yield distribution
     * @param assetToken The asset token address
     * @param expiresAt The expiry timestamp
     * @param releaseAmount The release amount
     */
    function releaseYieldDistribution(address assetToken, uint256 expiresAt, uint256 releaseAmount) external {
        YieldDistributionListItem storage yieldListItem = _getAssetVaultStorage().yieldDistributions[assetToken];
        uint256 yieldAmount = yieldListItem.yield.amount;

        while (yieldAmount > 0) {
            // clear expired yield distributions
            if (yieldListItem.beneficiary == msg.sender && yieldListItem.yield.expiresAt == expiresAt) {
                if (releaseAmount >= yieldAmount) {
                    releaseAmount -= yieldAmount;

                    // canceling the yield distribution completely
                    // will be cleared by clearYieldDistribution
                    yieldListItem.yield.expiresAt = block.timestamp - 1 days;

                    if (releaseAmount == 0) {
                        break;
                    }
                } else {
                    yieldListItem.yield.amount -= releaseAmount;
                    releaseAmount = 0;
                    break;
                }
            }

            if (gasleft() < 20_000) {
                return;
            }

            yieldListItem = yieldListItem.next[0];
            yieldAmount = yieldListItem.yield.amount;
        }

        require(releaseAmount == 0, "AssetVault: Invalid release amount");
    }

}
