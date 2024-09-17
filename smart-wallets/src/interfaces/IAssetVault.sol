// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IAssetVault {

    function updateYieldAllowance(
        IERC20 assetToken,
        address beneficiary,
        uint256 amount,
        uint256 expiration
    ) external;
    function redistributeYield(IERC20 assetToken, IERC20 yieldToken, uint256 yieldTokenAmount) external;

    function getBalanceLocked(IERC20 assetToken) external view returns (uint256 balanceLocked);
    function acceptYieldAllowance(IERC20 assetToken, uint256 amount, uint256 expiration) external;
    function renounceYieldDistribution(
        IERC20 assetToken,
        uint256 amount,
        uint256 expiration
    ) external returns (uint256 amountRenounced);
    function clearYieldDistributions(IERC20 assetToken) external;

}
