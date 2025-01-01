// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AtomicQueue } from "@nucleus-boring-vault/base/AtomicQueue.sol";
import { IComponentToken } from "../interfaces/IComponentToken.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title NestAtomicQueue
 * @notice AtomicQueue implementation for the Nest vault
 * @dev An AtomicQueue that only allows withdraws into a single `asset` that is
 * configured.
 */
contract NestAtomicQueue is AtomicQueue, IComponentToken {
    using SafeCast for uint256;

    // Constants

    uint256 public constant REQUEST_ID = 0;

    // Public State

    address public vault;
    address public accountant;
    uint256 public decimals; // Always set to vault decimals 
    IERC20 public asset;
    uint256 public deadlinePeriod;
    uint256 public pricePercentage; // Must be 4 decimals i.e. 9999 = 99.99%

    // Errors

    error Unimplemented();

    // Constructor

    constructor(
        address _vault,
        address _accountant,
        IERC20 _asset,
        uint256 _deadlinePeriod,
        uint256 _pricePercentage
    ) {
        vault = _vault;
        accountant = _accountant;
        decimals = _vault.decimals(); // Enforce that decimals is always the BoringVault shares decimals 
        asset = _asset;
        deadlinePeriod = _deadlinePeriod;
        pricePercentage = _pricePercentage;
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

    // User Functions

    /**
     * @notice Transfer assets from the owner into the vault and submit a request to buy shares
     * @param assets Amount of `asset` to deposit
     * @param controller Controller of the request
     * @param owner Source of the assets to deposit
     * @return requestId Discriminator between non-fungible requests
     */
    function requestDeposit(uint256 assets, address controller, address owner) public returns (uint256 requestId) {
        revert Unimplemented();
    }

    /**
     * @notice Fulfill a request to buy shares by minting shares to the receiver
     * @param assets Amount of `asset` that was deposited by `requestDeposit`
     * @param receiver Address to receive the shares
     * @param controller Controller of the request
     */
    function deposit(uint256 assets, address receiver, address controller) public returns (uint256 shares) {
        revert Unimplemented();
    }

    /**
     * @notice Transfer shares from the owner into the vault and submit a request to redeem assets
     * @param shares Amount of shares to redeem
     * @param controller Controller of the request
     * @param owner Source of the shares to redeem
     * @return requestId Discriminator between non-fungible requests
     */
    function requestRedeem(uint256 shares, address controller, address owner) public returns (uint256 requestId) {
        if (owner != msg.sender) {
            revert InvalidOwner();
        }

        if (controller != msg.sender) {
            revert InvalidController();
        }

        // Create and submit atomic request
        IAtomicQueue.AtomicRequest memory request = IAtomicQueue.AtomicRequest({
            deadline: block.timestamp + deadlinePeriod,
            atomicPrice: accountant.getRateInQuote(asset).mulDivDown(pricePercentage, 10000).toUint88(), // Price per share in terms of asset
            offerAmount: uint96(shares),
            inSolve: false
        });

        updateAtomicRequest(IERC20(vault), asset, request);

        emit RequestRedeem(shares, controller, owner);

        return REQUEST_ID;
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

    // Getter View Functions

    /// @notice Address of the `asset` token
    function asset() public view returns (address assetTokenAddress) {
        return address(asset);
    }

    function totalSupply() public view returns (uint256 totalSupply) {
        return vault.totalSupply();
    }

    function balanceOf(address owner) public view returns (uint256 balance) {
        return vault.balanceOf(owner);
    }

    /**
     * @notice Total value held in the vault
     * @dev Example ERC20 implementation: return convertToAssets(totalSupply())
     */
    function totalAssets() public view returns (uint256 totalManagedAssets) {
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
    ) public view returns (uint256 assets) {
        return convertToAssets(vault.balanceOf(owner));
    }

    /// @inheritdoc ERC4626Upgradeable
    function convertToShares(
        uint256 assets
    ) public view virtual override(ComponentToken) returns (uint256 shares) {
        return assets.mulDivDown(10 ** decimals, this.accountant.getRateInQuote(this.asset));
    }

    /// @inheritdoc ERC4626Upgradeable

    // returns quote / share in quote decimals 
    function convertToAssets(
        uint256 shares
    ) public view virtual override(ComponentToken) returns (uint256 assets) {
        return shares.mulDivDown(accountant.getRateInQuote(asset), 10 ** decimals);
    }

    /**
     * @notice Total amount of assets sent to the vault as part of pending deposit requests
     * @param requestId Discriminator between non-fungible requests
     * @param controller Controller of the requests
     * @return assets Amount of pending deposit assets for the given requestId and controller
     */
    function pendingDepositRequest(uint256 requestId, address controller) public pure returns (uint256 assets) {
        revert Unimplemented();
    }

    /**
     * @notice Total amount of assets sitting in the vault as part of claimable deposit requests
     * @param requestId Discriminator between non-fungible requests
     * @param controller Controller of the requests
     * @return assets Amount of claimable deposit assets for the given requestId and controller
     */
    function claimableDepositRequest(uint256 requestId, address controller) public pure returns (uint256 assets) {
        revert Unimplemented();
    }

    /**
     * @notice Total amount of shares sent to the vault as part of pending redeem requests
     * @param requestId Discriminator between non-fungible requests
     * @param controller Controller of the requests
     * @return shares Amount of pending redeem shares for the given requestId and controller
     */
    function pendingRedeemRequest(uint256 requestId, address controller) public pure returns (uint256 shares) {
        revert Unimplemented();
    }

    /**
     * @notice Total amount of assets sitting in the vault as part of claimable redeem requests
     * @param requestId Discriminator between non-fungible requests
     * @param controller Controller of the requests
     * @return shares Amount of claimable redeem shares for the given requestId and controller
     */
    function claimableRedeemRequest(uint256 requestId, address controller) public pure returns (uint256 shares) {
        revert Unimplemented();
    }
}