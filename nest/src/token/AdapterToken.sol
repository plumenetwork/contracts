// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { ComponentToken } from "../ComponentToken.sol";

import { IAggregateToken } from "../interfaces/IAggregateToken.sol";
import { IComponentToken } from "../interfaces/IComponentToken.sol";

/// @notice Example of an interface for the external contract that manages the external asset
interface IExternalContract {

    /// @notice Notify the external contract that a deposit has been requested
    function requestDeposit(
        uint256 assets
    ) external;
    /// @notice Notify the external contract that a redeem has been requested
    function requestRedeem(
        uint256 shares
    ) external;
    /// @notice Convert from quantity of assets to quantity of shares
    function convertToShares(
        uint256 assets
    ) external pure returns (uint256 shares);
    /// @notice Convert from quantity of shares to quantity of assets
    function convertToAssets(
        uint256 shares
    ) external pure returns (uint256 assets);

}

/**
 * @title AdapterToken
 * @author Eugene Y. Q. Shen
 * @notice Implementation of the abstract ComponentToken that interfaces with external assets.
 */
contract USDT is ComponentToken {

    // Storage

    /// @custom:storage-location erc7201:plume.storage.AdapterToken
    struct AdapterTokenStorage {
        /// @dev Address of the Nest Staking contract
        IAggregateToken nestStakingContract;
        /// @dev Address of the external contract that manages the external asset
        IExternalContract externalContract;
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.AdapterToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ADAPTER_TOKEN_STORAGE_LOCATION =
        0xb94ddb3268639eae8606689fcefbcb8a18c8a94fc82eefd097206f0c02fe9100;

    function _getAdapterTokenStorage() private pure returns (AdapterTokenStorage storage $) {
        assembly {
            $.slot := ADAPTER_TOKEN_STORAGE_LOCATION
        }
    }

    // Initializer

    /**
     * @notice Prevent the implementation contract from being initialized or reinitialized
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the AdapterToken
     * @param owner Address of the owner of the AdapterToken
     * @param name Name of the AdapterToken
     * @param symbol Symbol of the AdapterToken
     * @param asset_ Asset used to mint and burn the AdapterToken
     * @param nestStakingContract Address of the Nest Staking contract
     * @param externalContract Address of the external contract that manages the external asset
     */
    function initialize(
        address owner,
        string memory name,
        string memory symbol,
        IERC20 asset_,
        IAggregateToken nestStakingContract,
        IExternalContract externalContract
    ) public initializer {
        super.initialize(owner, name, symbol, asset_, true, true);
        AdapterTokenStorage storage $ = _getAdapterTokenStorage();
        $.nestStakingContract = nestStakingContract;
        $.externalContract = externalContract;
    }

    // Override Functions

    /// @inheritdoc IERC4626
    function convertToShares(
        uint256 assets
    ) public view override(ComponentToken) returns (uint256 shares) {
        return _getAdapterTokenStorage().externalContract.convertToShares(assets);
    }

    /// @inheritdoc IERC4626
    function convertToAssets(
        uint256 shares
    ) public view override(ComponentToken) returns (uint256 assets) {
        return _getAdapterTokenStorage().externalContract.convertToAssets(shares);
    }

    /// @inheritdoc IComponentToken
    function requestDeposit(
        uint256 assets,
        address controller,
        address owner
    ) public override(ComponentToken) returns (uint256 requestId) {
        AdapterTokenStorage storage $ = _getAdapterTokenStorage();
        if (msg.sender != address($.nestStakingContract)) {
            revert Unauthorized(msg.sender, address($.nestStakingContract));
        }
        requestId = super.requestDeposit(assets, controller, owner);
        $.externalContract.requestDeposit(assets);
    }

    /// @inheritdoc IComponentToken
    function requestRedeem(
        uint256 shares,
        address controller,
        address owner
    ) public override(ComponentToken) returns (uint256 requestId) {
        AdapterTokenStorage storage $ = _getAdapterTokenStorage();
        if (msg.sender != address($.nestStakingContract)) {
            revert Unauthorized(msg.sender, address($.nestStakingContract));
        }
        requestId = super.requestRedeem(shares, controller, owner);
        $.externalContract.requestRedeem(shares);
    }

    /// @inheritdoc IComponentToken
    function deposit(
        uint256 assets,
        address receiver,
        address controller
    ) public override(ComponentToken) returns (uint256 shares) {
        AdapterTokenStorage storage $ = _getAdapterTokenStorage();
        if (msg.sender != address($.externalContract)) {
            revert Unauthorized(msg.sender, address($.externalContract));
        }
        if (receiver != address($.nestStakingContract)) {
            revert Unauthorized(receiver, address($.nestStakingContract));
        }
        return super.deposit(assets, receiver, controller);
    }

    /// @inheritdoc IComponentToken
    function redeem(
        uint256 shares,
        address receiver,
        address controller
    ) public override(ComponentToken) returns (uint256 assets) {
        AdapterTokenStorage storage $ = _getAdapterTokenStorage();
        if (msg.sender != address($.externalContract)) {
            revert Unauthorized(msg.sender, address($.externalContract));
        }
        if (receiver != address($.nestStakingContract)) {
            revert Unauthorized(receiver, address($.nestStakingContract));
        }
        return super.redeem(shares, receiver, controller);
    }

}
