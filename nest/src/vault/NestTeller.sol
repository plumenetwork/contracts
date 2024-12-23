// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { NestBoringVaultModule } from "./NestBoringVaultModule.sol";
import { MultiChainLayerZeroTellerWithMultiAssetSupport } from "boringvault/base/Roles/crosschain/MultiChainLayerZeroTellerWithMultiAssetSupport.sol";

/**
 * @title NestTeller
 * @notice Teller implementation for the Nest vault
 * @dev A Teller that only allows deposits of a single `asset` that is
 * configured.
 */
contract NestTeller is NestBoringVaultModule, MultiChainLayerZeroTellerWithMultiAssetSupport {




    // Public State

    address public asset;
    uint256 public minimumMintPercentage; // Must be 4 decimals i.e. 9999 = 99.99%

    // Errors

    error Unimplemented();


    constructor(
        address _owner,
        address _vault,
        address _accountant,
        address _endpoint,
        address _asset,
        uint256 _minimumMintPercentage
    ) MultiChainLayerZeroTellerWithMultiAssetSupport(
        _owner,
        _vault,
        _accountant,
        _endpoint
    ) {
        asset = _asset;
        minimumMintPercentage = _minimumMintPercentage;
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
        if (controller != msg.sender) {
            revert InvalidController();
        }

        shares = deposit(IERC20(asset), assets, assets.mulDivDown(minimumMintPercentage, 10_000));

        emit Deposit(msg.sender, receiver, assets, shares);
        return shares;
    }

}
