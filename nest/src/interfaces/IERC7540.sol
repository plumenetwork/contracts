// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IComponentToken } from "./IComponentToken.sol";
import { IERC7575 } from "./IERC7575.sol";

interface IERC7540 is IERC165, IERC4626, IERC7575, IComponentToken {

    // Events

    /**
     * @notice Emitted when an operator is granted or revoked permissions to manage requests for a controller
     * @param controller Controller to be managed by the operator
     * @param operator Operator for which permissions were updated
     * @param approved True if the operator was granted permissions; false if the operator was revoked
     */
    event OperatorSet(address indexed controller, address indexed operator, bool approved);

    // User Functions

    /// @inheritdoc IComponentToken
    function redeem(
        uint256 shares,
        address receiver,
        address controller
    ) external override(IComponentToken, IERC4626) returns (uint256 assets);

    // Getter View Functions

    /// @inheritdoc IComponentToken
    function asset() external view override(IComponentToken, IERC4626) returns (address assetTokenAddress);

    /// @inheritdoc IComponentToken
    function totalAssets() external view override(IComponentToken, IERC4626) returns (uint256 totalManagedAssets);

    /// @inheritdoc IComponentToken
    function convertToShares(
        uint256 assets
    ) external view override(IComponentToken, IERC4626) returns (uint256 shares);

    /// @inheritdoc IComponentToken
    function convertToAssets(
        uint256 shares
    ) external view override(IComponentToken, IERC4626) returns (uint256 assets);

    /**
     * @notice Check if an operator has permissions to manage requests for a controller
     * @param controller Controller to be managed by the operator
     * @param operator Operator for which to check permissions
     * @return status True if the operator has permissions; false otherwise
     */
    function isOperator(address controller, address operator) external view returns (bool status);

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
