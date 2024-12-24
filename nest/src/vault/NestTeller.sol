// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { NestBoringVaultModule } from "./NestBoringVaultModule.sol";
import { MultiChainLayerZeroTellerWithMultiAssetSupport } from
    "@boringvault/src/base/Roles/crosschain/MultiChainLayerZeroTellerWithMultiAssetSupport.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Auth, Authority } from "@solmate/auth/Auth.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
/**
 * @title NestTeller
 * @notice Teller implementation for the Nest vault
 * @dev A Teller that only allows deposits of a single `asset` that is
 * configured.
 */

contract NestTeller is MultiChainLayerZeroTellerWithMultiAssetSupport, NestBoringVaultModule {

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
        IERC20 _asset,
        uint256 _minimumMintPercentage
    )
        MultiChainLayerZeroTellerWithMultiAssetSupport(_owner, _vault, _accountant, _endpoint)
        NestBoringVaultModule(_owner, _vault, _accountant, _asset)
    {
        minimumMintPercentage = _minimumMintPercentage;
    }

    // This is the IComponentToken deposit implementation
    function deposit(uint256 assets, address receiver, address controller) public override returns (uint256 shares) {
        if (receiver != msg.sender) {
            revert InvalidReceiver();
        }
        if (controller != msg.sender) {
            revert InvalidController();
        }

        // Call the parent's _erc20Deposit function directly
        shares = _erc20Deposit(
            ERC20(address(assetToken)), assets, assets.mulDivDown(minimumMintPercentage, 10_000), msg.sender
        );

        _afterPublicDeposit(msg.sender, ERC20(address(assetToken)), assets, shares, shareLockPeriod);

        return shares;
    }

    function requestRedeem(uint256 shares, address controller, address owner) public override returns (uint256) {
        // Implementation here - this should integrate with LayerZero cross-chain functionality
        revert Unimplemented();
    }

}
