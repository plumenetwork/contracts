// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IAccountantWithRateProviders } from "../interfaces/IAccountantWithRateProviders.sol";
import { IBoringVault } from "../interfaces/IBoringVault.sol";
import { IComponentToken } from "../interfaces/IComponentToken.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Auth, Authority } from "@solmate/auth/Auth.sol";

/**
 * @title NestBoringVaultModule
 * @notice Base implementation for Nest vault modules
 * @dev Implements common functionality for both Teller and AtomicQueue
 */
abstract contract NestBoringVaultModule is IComponentToken, Auth {

    using SafeCast for uint256;

    // Public State
    IBoringVault public immutable vaultContract;
    IAccountantWithRateProviders public immutable accountantContract;
    uint256 public immutable decimals;
    IERC20 public assetToken;

    // Errors
    error InvalidOwner();
    error InvalidController();
    error Unimplemented();

    // Constructor
    constructor(
        address _owner,
        address _vault,
        address _accountant,
        IERC20 _asset
    ) Auth(_owner, Authority(address(0))) {
        vaultContract = IBoringVault(_vault);
        accountantContract = IAccountantWithRateProviders(_accountant);
        decimals = vaultContract.decimals();
        assetToken = _asset;
    }

    // Admin Setters
    function setVault(
        address _vault
    ) external requiresAuth {
        decimals = vaultContract.decimals();
    }

    function setAsset(
        IERC20 _asset
    ) external requiresAuth {
        assetToken = _asset;
    }

    // Virtual functions that must be implemented by children
    function deposit(uint256 assets, address receiver, address controller) public virtual override returns (uint256);
    function requestRedeem(
        uint256 shares,
        address controller,
        address owner
    ) public virtual override returns (uint256);

    // Common implementations
    function asset() public view virtual override returns (address) {
        return address(assetToken);
    }

    function totalSupply() public view returns (uint256) {
        return super.vault.totalSupply();
    }

    function balanceOf(
        address owner
    ) public view returns (uint256) {
        return super.vault.balanceOf(owner);
    }

    function totalAssets() public view returns (uint256) {
        return convertToAssets(super.vault.totalSupply());
    }

    function assetsOf(
        address owner
    ) public view returns (uint256) {
        return convertToAssets(super.vault.balanceOf(owner));
    }

    function convertToShares(
        uint256 assets
    ) public view virtual returns (uint256) {
        return assets.mulDivDown(10 ** decimals, super.accountant.getRateInQuote(asset));
    }

    function convertToAssets(
        uint256 shares
    ) public view virtual returns (uint256) {
        return shares.mulDivDown(super.accountant.getRateInQuote(asset), 10 ** decimals);
    }

    // Default implementations that can be overridden
    function requestDeposit(uint256 assets, address controller, address owner) public virtual returns (uint256) {
        revert Unimplemented();
    }

    function redeem(uint256 shares, address receiver, address controller) public virtual returns (uint256) {
        revert Unimplemented();
    }

    function pendingDepositRequest(uint256 requestId, address controller) public view virtual returns (uint256) {
        revert Unimplemented();
    }

    function claimableDepositRequest(uint256 requestId, address controller) public view virtual returns (uint256) {
        revert Unimplemented();
    }

    function pendingRedeemRequest(uint256 requestId, address controller) public view virtual returns (uint256) {
        revert Unimplemented();
    }

    function claimableRedeemRequest(uint256 requestId, address controller) public view virtual returns (uint256) {
        revert Unimplemented();
    }

}
