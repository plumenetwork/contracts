// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { Auth, Authority } from "@solmate/auth/Auth.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";

import { MultiChainLayerZeroTellerWithMultiAssetSupport } from
    "@boringvault/src/base/Roles/CrossChain/MultiChainLayerZeroTellerWithMultiAssetSupport.sol";

import { IAccountantWithRateProviders } from "../interfaces/IAccountantWithRateProviders.sol";
import { IBoringVault } from "../interfaces/IBoringVault.sol";
import { ITeller } from "../interfaces/ITeller.sol";
import { NestBoringVaultModule } from "./NestBoringVaultModule.sol";
import { console } from "forge-std/console.sol";

/**
 * @title NestTeller
 * @notice Teller implementation for the Nest vault
 * @dev A Teller that only allows deposits of a single `asset` that is
 * configured.
 */
contract NestTeller is NestBoringVaultModule, MultiChainLayerZeroTellerWithMultiAssetSupport {

    using SafeCast for uint256;
    using FixedPointMathLib for uint256;

    uint256 private nonce;

    // Public State
    uint256 public minimumMintPercentage; // Must be 4 decimals i.e. 9999 = 99.99%

    constructor(
        address _owner,
        address _vault,
        address _accountant,
        address _endpoint,
        address _asset,
        uint256 _minimumMintPercentage
    )
        NestBoringVaultModule(_owner, _vault, _accountant, IERC20(_asset))
        MultiChainLayerZeroTellerWithMultiAssetSupport(_owner, _vault, _accountant, _endpoint)
    {
        // vault, accountant checks from MultiChainLayerZeroTellerWithMultiAssetSupport->TellerWithMultiAssetSupport
        // owner, endpoint checks from MultiChainLayerZeroTellerWithMultiAssetSupport->OAppAuth

        if (_asset == address(0)) {
            revert ZeroAsset();
        }
        if (_minimumMintPercentage == 0 || _minimumMintPercentage > 10_000) {
            revert InvalidMinimumMintPercentage();
        }

        minimumMintPercentage = _minimumMintPercentage;
    }

    /**
     * @notice Transfer assets from the owner into the vault and submit a request to buy shares
     * @param assets Amount of `asset` to deposit
     * @param controller Controller of the request
     * @param owner Source of the assets to deposit
     * @return requestId Discriminator between non-fungible requests
     */
    function requestDeposit(
        uint256 assets,
        address controller,
        address owner
    ) public override returns (uint256 requestId) {
        revert Unimplemented();
    }

    /**
     * @notice Fulfill a request to buy shares by minting shares to the receiver
     * @param assets Amount of `asset` that was deposited by `requestDeposit`
     * @param receiver Address to receive the shares
     * @param controller Controller of the request
     */
    function deposit(uint256 assets, address receiver, address controller) public override returns (uint256 shares) {
        if (receiver != msg.sender) {
            revert InvalidReceiver();
        }
        if (controller != msg.sender) {
            revert InvalidController();
        }

        shares =
            ITeller(address(this)).deposit(IERC20(asset()), assets, assets.mulDivDown(minimumMintPercentage, 10_000));

        return shares;
    }

    function requestRedeem(uint256 shares, address controller, address owner) public override returns (uint256) {
        // Implementation here - this should integrate with LayerZero cross-chain functionality
        revert Unimplemented();
    }

}
