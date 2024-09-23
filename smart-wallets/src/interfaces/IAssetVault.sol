// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAssetToken } from "../interfaces/IAssetToken.sol";

interface IAssetVault {

    function updateYieldAllowance(
        IAssetToken assetToken,
        address beneficiary,
        uint256 amount,
        uint256 expiration
    ) external;
    function redistributeYield(IAssetToken assetToken, IERC20 currencyToken, uint256 currencyTokenAmount) external;

    function wallet() external view returns (address wallet);
    function getBalanceLocked(IAssetToken assetToken) external view returns (uint256 balanceLocked);
    function acceptYieldAllowance(IAssetToken assetToken, uint256 amount, uint256 expiration) external;
    function renounceYieldDistribution(IAssetToken assetToken, uint256 amount, uint256 expiration) external returns (uint256 amountRenounced);
    function clearYieldDistributions(IAssetToken assetToken) external;

}
