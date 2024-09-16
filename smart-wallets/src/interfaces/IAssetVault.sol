// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/**
 * @title IAssetVault
 * @author Eugene Y. Q. Shen
 * @notice Interface for the Asset Vault
 */
interface IAssetVault {

    /**
     * @notice Returns the locked asset token balance for the given asset token
     * @param assetToken The asset token address
     * @return lockedBalance The locked asset token balance
     */
    function getLockedAssetTokenBalance(address assetToken) external view returns (uint256 lockedBalance);

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
    ) external;

    /**
     * @notice Accept yield distribution for the given asset token
     * @dev The beneficiary must call this function to accept the yield distribution
     * @param assetToken The asset token address
     * @param amount The yield amount
     * @param expiresAt The expiry timestamp
     */
    function acceptYieldDistribution(address assetToken, uint256 amount, uint256 expiresAt) external;

    /**
     * @notice Clear expired yield distributions for the given asset token
     * @param assetToken The asset token address
     */
    function clearYieldDistribution(address assetToken) external;

    /**
     * @notice Distribute yield for the given asset token
     * @dev AssetVault will call transferYield function of the wallet
     * @param assetToken The asset token address
     * @param yieldCurrency The yield token address
     * @param yieldAmount The yield amount
     */
    function processYieldDistribution(address assetToken, address yieldCurrency, uint256 yieldAmount) external;

    /**
     * @notice Release yield distribution for the given asset token
     * @dev The beneficiary must call this function to release the yield distribution
     * @param assetToken The asset token address
     * @param expiresAt The expiry timestamp
     * @param releaseAmount The release amount
     */
    function releaseYieldDistribution(address assetToken, uint256 expiresAt, uint256 releaseAmount) external;

}
