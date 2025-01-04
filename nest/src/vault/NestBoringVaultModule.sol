// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { Auth, Authority } from "@solmate/auth/Auth.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";

import { IAccountantWithRateProviders } from "../interfaces/IAccountantWithRateProviders.sol";

import { IAtomicQueue } from "../interfaces/IAtomicQueue.sol";
import { IBoringVault } from "../interfaces/IBoringVault.sol";
import { IComponentToken } from "../interfaces/IComponentToken.sol";
import { ITeller } from "../interfaces/ITeller.sol";

/**
 * @title NestBoringVaultModule
 * @notice Base implementation for Nest vault modules
 * @dev Implements common functionality for both Teller and AtomicQueue
 */
abstract contract NestBoringVaultModule is Initializable, IComponentToken {

    using SafeCast for uint256;
    using FixedPointMathLib for uint256;

    // Public State
    IBoringVault public vault;
    IAccountantWithRateProviders public accountant;
    ITeller public teller;
    IAtomicQueue public atomicQueue;
    uint256 public _decimals;
    IERC20 public assetToken;

    // Custom Errors
    error InvalidReceiver();
    error InvalidController();
    error Unimplemented();
    error InvalidAmount();
    error InvalidOwner();
    error ZeroAddress(string _address);

    error InvalidMinimumMintPercentage();

    function _checkZeroAddress(address addr, string memory name) private pure {
        if (addr == address(0)) {
            revert ZeroAddress(name);
        }
    }

    function __NestBoringVaultModule_init(
        address _vault,
        address _accountant,
        address _teller,
        address _atomicQueue,
        IERC20 _asset
    ) internal onlyInitializing {
        _checkZeroAddress(_vault, "vault");
        _checkZeroAddress(_accountant, "accountant");
        _checkZeroAddress(_teller, "teller");
        _checkZeroAddress(_atomicQueue, "atomicQueue");
        _checkZeroAddress(address(_asset), "asset");

        vault = IBoringVault(_vault);
        accountant = IAccountantWithRateProviders(_accountant);
        teller = ITeller(_teller);
        atomicQueue = IAtomicQueue(_atomicQueue);
        _decimals = IBoringVault(_vault).decimals();

        assetToken = _asset;
    }

    function setAsset(
        IERC20 _asset
    ) external {
        assetToken = _asset;
    }

    function requestRedeem(
        uint256 shares,
        address controller,
        address owner
    ) public virtual override returns (uint256);

    /// @notice Address of the `asset` token
    function asset() public view virtual override returns (address) {
        return address(assetToken);
    }

    function totalSupply() public view virtual returns (uint256) {
        return vault.totalSupply();
    }

    function balanceOf(
        address owner
    ) public view virtual returns (uint256) {
        return vault.balanceOf(owner);
    }

    /**
     * @notice Total value held in the vault
     * @dev Example ERC20 implementation: return convertToAssets(totalSupply())
     */
    function totalAssets() public view virtual returns (uint256) {
        // WARNING: Would only reflect the totalAssets on this single vault, not
        // including the crosschain vaults.
        return convertToAssets(vault.totalSupply());
    }

    /**
     * @notice Total value held by the given owner
     * @dev Example ERC20 implementation: return convertToAssets(balanceOf(owner))
     * @param owner Address to query the balance of
     * @return assets Total value held by the owner
     */
    function assetsOf(
        address owner
    ) public view returns (uint256) {
        return convertToAssets(vault.balanceOf(owner));
    }

    function convertToShares(
        uint256 assets
    ) public view virtual returns (uint256) {
        return assets.mulDivDown(10 ** _decimals, accountant.getRateInQuote(ERC20(address(assetToken))));
    }

    function convertToAssets(
        uint256 shares
    ) public view virtual returns (uint256) {
        return shares.mulDivDown(accountant.getRateInQuote(ERC20(address(assetToken))), 10 ** _decimals);
    }

    // Default implementations that can be overridden
    function requestDeposit(uint256 assets, address controller, address owner) public virtual returns (uint256) {
        revert Unimplemented();
    }

    /**
     * @notice Fulfill a request to redeem assets by transferring assets to the receiver
     * @param shares Amount of shares that was redeemed by `requestRedeem`
     * @param receiver Address to receive the assets
     * @param controller Controller of the request
     */
    function redeem(uint256 shares, address receiver, address controller) public returns (uint256 assets) {
        // Redeem doesn't do anything anymore because as soon as the AtomicQueue
        // request is processed, the msg.sender will receive their this.asset
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
