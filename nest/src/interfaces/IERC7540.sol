// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IERC7575 } from "./IERC7575.sol";

interface IERC7540 is IERC165, IERC4626, IERC7575 {

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
     * @notice Emitted when an operator is granted or revoked permissions to manage requests for a controller
     * @param controller Controller to be managed by the operator
     * @param operator Operator for which permissions were updated
     * @param approved True if the operator was granted permissions; false if the operator was revoked
     */
    event OperatorSet(address indexed controller, address indexed operator, bool approved);

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

    /// @inheritdoc IERC4626
    function redeem(uint256 shares, address receiver, address controller) external returns (uint256 assets);

    // Getter View Functions

    /**
     * @notice Check if an operator has permissions to manage requests for a controller
     * @param controller Controller to be managed by the operator
     * @param operator Operator for which to check permissions
     * @return status True if the operator has permissions; false otherwise
     */
    function isOperator(address controller, address operator) external view returns (bool status);

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

    // Unimplemented Functions

    /**
     * @notice Fulfill a request to buy shares by minting shares to the receiver
     * @param shares Amount of shares to receive
     * @param receiver Address to receive the shares
     * @param controller Controller of the request
     */
    function mint(uint256 shares, address receiver, address controller) external returns (uint256 assets);

    /// @inheritdoc IERC4626
    function withdraw(uint256 assets, address receiver, address controller) external returns (uint256 shares);

    /**
     * @notice Grant or revoke permissions for an operator to manage requests for a controller
     * @param controller Controller to be managed by the operator
     * @param approved True to grant permissions; false to revoke permissions
     * @return success True if the operator permissions were updated; false otherwise
     */
    function setOperator(address controller, bool approved) external returns (bool success);

}
