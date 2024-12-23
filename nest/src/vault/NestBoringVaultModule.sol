// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IComponentToken } from "../interfaces/IComponentToken.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title NestBoringVaultModule
 * @notice Base implementation for Nest vault modules
 * @dev Implements common functionality for both Teller and AtomicQueue
 */
abstract contract NestBoringVaultModule is IComponentToken {
    using SafeCast for uint256;

    // Public State
    address public vault;
    address public accountant;
    uint256 public decimals; // Always set to vault decimals 
    IERC20 public asset;

    // Errors
    error InvalidOwner();
    error InvalidController();
    error Unimplemented();

    // Constructor
    constructor(
        address _vault,
        address _accountant,
        IERC20 _asset
    ) {
        vault = _vault;
        accountant = _accountant;
        decimals = _vault.decimals();
        asset = _asset;
    }

    // Admin Setters
    function setVault(address _vault) requiresAuth external {
        vault = _vault;
        decimals = _vault.decimals();
    }

    function setAccountant(address _accountant) requiresAuth external {
        accountant = _accountant;
    }

    function setAsset(IERC20 _asset) requiresAuth external {
        asset = _asset;
    }

    // Virtual functions that must be implemented by children
    function requestRedeem(uint256 shares, address controller, address owner) public virtual returns (uint256);
    function deposit(uint256 assets, address receiver, address controller) public virtual returns (uint256);

    // Common implementations
    function asset() public view returns (address) {
        return address(asset);
    }

    function totalSupply() public view returns (uint256) {
        return vault.totalSupply();
    }

    function balanceOf(address owner) public view returns (uint256) {
        return vault.balanceOf(owner);
    }

    function totalAssets() public view returns (uint256) {
        return convertToAssets(vault.totalSupply());
    }

    function assetsOf(address owner) public view returns (uint256) {
        return convertToAssets(vault.balanceOf(owner));
    }

    function convertToShares(uint256 assets) public view virtual returns (uint256) {
        return assets.mulDivDown(10 ** decimals, accountant.getRateInQuote(asset));
    }

    function convertToAssets(uint256 shares) public view virtual returns (uint256) {
        return shares.mulDivDown(accountant.getRateInQuote(asset), 10 ** decimals);
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