// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AssetToken } from "../token/AssetToken.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IAssetVault {

    function updateYieldAllowance(
        AssetToken assetToken,
        address beneficiary,
        uint256 amount,
        uint256 expiration
    ) external;
    function redistributeYield(AssetToken assetToken, ERC20 currencyToken, uint256 currencyTokenAmount) external;

    function getBalanceLocked(AssetToken assetToken) external view returns (uint256 balanceLocked);
    function acceptYieldAllowance(AssetToken assetToken, uint256 amount, uint256 expiration) external;
    function renounceYieldDistribution(
        AssetToken assetToken,
        uint256 amount,
        uint256 expiration
    ) external returns (uint256 amountRenounced);
    function clearYieldDistributions(AssetToken assetToken) external;

}
