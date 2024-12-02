// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IAccountantWithRateProviders } from "./IAccountantWithRateProviders.sol";

import { IVault } from "./IBoringVault.sol";
import { ITeller } from "./ITeller.sol";

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";

interface ILens {

    function totalAssets(
        IVault vault,
        IAccountantWithRateProviders accountant
    ) external view returns (IERC20 asset, uint256 assets);

    function previewDeposit(
        IERC20 depositAsset,
        uint256 depositAmount,
        IVault vault,
        IAccountantWithRateProviders accountant
    ) external view returns (uint256 shares);

    function balanceOf(address account, IVault vault) external view returns (uint256 shares);

    function balanceOfInAssets(
        address account,
        IVault vault,
        IAccountantWithRateProviders accountant
    ) external view returns (uint256 assets);

    function exchangeRate(
        IAccountantWithRateProviders accountant
    ) external view returns (uint256 rate);

    function checkUserDeposit(
        address account,
        IERC20 depositAsset,
        uint256 depositAmount,
        IVault vault,
        ITeller teller
    ) external view returns (bool);

}
