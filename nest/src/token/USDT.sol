// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { ComponentToken } from "../ComponentToken.sol";
import { IComponentToken } from "../interfaces/IComponentToken.sol";

/**
 * @title USDT
 * @author Eugene Y. Q. Shen
 * @notice Implementation of the abstract ComponentToken for an infinite supply stablecoin.
 */
contract USDT is ComponentToken {

    // Initializer

    /**
     * @notice Prevent the implementation contract from being initialized or reinitialized
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize USDT
     * @param owner Address of the owner of USDT
     */
    function initialize(address owner, IERC20 asset_) public initializer {
        super.initialize(owner, "Tether USD", "USDT", asset_, false, false);
    }

    // Override Functions

    /**
     * @inheritdoc IERC4626
     * @dev 1:1 conversion rate between USDT and base asset
     */
    function convertToShares(
        uint256 assets
    ) public pure override(ComponentToken) returns (uint256 shares) {
        return assets;
    }

    /**
     * @inheritdoc IERC4626
     * @dev 1:1 conversion rate between USDT and base asset
     */
    function convertToAssets(
        uint256 shares
    ) public pure override(ComponentToken) returns (uint256 assets) {
        return shares;
    }

    /**
     * @inheritdoc IComponentToken
     * @dev 1:1 conversion rate between USDT and base asset
     * @dev To enable load testing with constant calldata, does not require msg.sender to equal controller
     */
    function deposit(
        uint256 assets,
        address receiver,
        address controller
    ) public override(ComponentToken) returns (uint256 shares) {
        if (assets == 0) {
            revert ZeroAmount(ZeroAmountParam.ASSETS);
        }

        if (!IERC20(asset()).transferFrom(controller, address(this), assets)) {
            revert InsufficientBalance(IERC20(asset()), controller, assets);
        }
        shares = convertToShares(assets);

        _mint(receiver, shares);

        emit Deposit(controller, receiver, assets, shares);
    }

}
