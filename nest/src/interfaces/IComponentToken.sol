// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IComponentToken {

    // Events

    /**
     * @notice Emitted when the owner of some assets submits a request to buy shares
     * @param controller Controller of the request
     * @param owner Source of the assets to deposit
     * @param requestId Discriminator between non-fungible requests
     * @param sender Address that submitted the request
     * @param assets Amount of `asset` to deposit
     */
    event DepositRequest(
        address indexed controller, address indexed owner, uint256 indexed requestId, address sender, uint256 assets
    );

    /**
     * @notice Emitted when the owner of some shares submits a request to redeem assets
     * @param controller Controller of the request
     * @param owner Source of the shares to redeem
     * @param requestId Discriminator between non-fungible requests
     * @param sender Address that submitted the request
     * @param shares Amount of shares to redeem
     */
    event RedeemRequest(
        address indexed controller, address indexed owner, uint256 indexed requestId, address sender, uint256 shares
    );

    /**
     * @notice Emitted when a deposit request is complete
     * @param sender Controller of the request
     * @param owner Source of the assets to deposit
     * @param assets Amount of `asset` that has been deposited
     * @param shares Amount of shares that has been received in exchange
     */
    // event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    /**
     * @notice Emitted when a redeem request is complete
     * @param sender Controller of the request
     * @param receiver Address to receive the assets
     * @param owner Source of the shares to redeem
     * @param assets Amount of `asset` that has been received in exchange
     * @param shares Amount of shares that has been redeemed
     */
    // event Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256
    // shares);

    // User Functions

    /**
     * @notice Transfer assets from the owner into the vault and submit a request to buy shares
     * @param assets Amount of `asset` to deposit
     * @param controller Controller of the request
     * @param owner Source of the assets to deposit
     * @return requestId Discriminator between non-fungible requests
     */
    function requestDeposit(uint256 assets, address controller, address owner) external returns (uint256 requestId);

    /**
     * @notice Fulfill a request to buy shares by minting shares to the receiver
     * @param assets Amount of `asset` that was deposited by `requestDeposit`
     * @param receiver Address to receive the shares
     * @param controller Controller of the request
     */
    function deposit(uint256 assets, address receiver, address controller) external returns (uint256 shares);

    /**
     * @notice Transfer shares from the owner into the vault and submit a request to redeem assets
     * @param shares Amount of shares to redeem
     * @param controller Controller of the request
     * @param owner Source of the shares to redeem
     * @return requestId Discriminator between non-fungible requests
     */
    function requestRedeem(uint256 shares, address controller, address owner) external returns (uint256 requestId);

    /**
     * @notice Fulfill a request to redeem assets by transferring assets to the receiver
     * @param shares Amount of shares that was redeemed by `requestRedeem`
     * @param receiver Address to receive the assets
     * @param controller Controller of the request
     */
    function redeem(uint256 shares, address receiver, address controller) external returns (uint256 assets);

    // Getter View Functions

    /// @notice Address of the `asset` token
    function asset() external view returns (address assetTokenAddress);

    /**
     * @notice Total value held in the vault
     * @dev Example ERC20 implementation: return convertToAssets(totalSupply())
     */
    function totalAssets() external view returns (uint256 totalManagedAssets);

    /**
     * @notice Total value held by the given owner
     * @dev Example ERC20 implementation: return convertToAssets(balanceOf(owner))
     * @param owner Address to query the balance of
     * @return assets Total value held by the owner
     */
    function assetsOf(
        address owner
    ) external view returns (uint256 assets);

    /**
     * @notice Equivalent amount of shares for the given amount of assets
     * @param assets Amount of `asset` to convert
     * @return shares Amount of shares that would be received in exchange
     */
    function convertToShares(
        uint256 assets
    ) external view returns (uint256 shares);

    /**
     * @notice Equivalent amount of assets for the given amount of shares
     * @param shares Amount of shares to convert
     * @return assets Amount of `asset` that would be received in exchange
     */
    function convertToAssets(
        uint256 shares
    ) external view returns (uint256 assets);

    /**
     * @notice Total amount of assets sent to the vault as part of pending deposit requests
     * @param requestId Discriminator between non-fungible requests
     * @param controller Controller of the requests
     * @return assets Amount of pending deposit assets for the given requestId and controller
     */
    function pendingDepositRequest(uint256 requestId, address controller) external view returns (uint256 assets);

    /**
     * @notice Total amount of assets sitting in the vault as part of claimable deposit requests
     * @param requestId Discriminator between non-fungible requests
     * @param controller Controller of the requests
     * @return assets Amount of claimable deposit assets for the given requestId and controller
     */
    function claimableDepositRequest(uint256 requestId, address controller) external view returns (uint256 assets);

    /**
     * @notice Total amount of shares sent to the vault as part of pending redeem requests
     * @param requestId Discriminator between non-fungible requests
     * @param controller Controller of the requests
     * @return shares Amount of pending redeem shares for the given requestId and controller
     */
    function pendingRedeemRequest(uint256 requestId, address controller) external view returns (uint256 shares);

    /**
     * @notice Total amount of assets sitting in the vault as part of claimable redeem requests
     * @param requestId Discriminator between non-fungible requests
     * @param controller Controller of the requests
     * @return shares Amount of claimable redeem shares for the given requestId and controller
     */
    function claimableRedeemRequest(uint256 requestId, address controller) external view returns (uint256 shares);

}
