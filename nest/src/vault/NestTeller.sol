// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { MultiChainLayerZeroTellerWithMultiAssetSupport } from "@nucleus-boring-vault/base/Roles/MultiChainLayerZeroTellerWithMultiAssetSupport.sol";

contract NestTeller is MultiChainLayerZeroTellerWithMultiAssetSupport {

    address public asset;
    uint256 public minimumMint = _minimumMint;

    constructor(
        address _owner,
        address _vault,
        address _accountant,
        address _endpoint,
        address _asset,
        uint256 _minimumMint
    ) MultiChainLayerZeroTellerWithMultiAssetSupport(
        _owner,
        _vault,
        _accountant,
        _endpoint
    ) {
        asset = _asset;
        minimumMint = _minimumMint;
    }

    error Unimplemented();

    function setAsset(address _asset) requiresAuth external {
        asset = _asset;
    }

    function setMinimumMint(uint256 _minimumMint) requiresAuth external {
        minimumMint = _minimumMint;
    }

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
        // Ensure receiver is msg.sender
        if (receiver != msg.sender) {
            revert InvalidReceiver();
        }
        // Ensure controller is msg.sender
        if (controller != msg.sender) {
            revert InvalidController();
        }

        shares = deposit(
            IERC20(this.asset), // depositAsset
            assets, // depositAmount
            this.minimumMint // minimumMint
        );
        emit Deposit(msg.sender, receiver, assets, shares);
        return shares;
    }
}