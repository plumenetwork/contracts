// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IAccountantWithRateProviders } from "./IAccountantWithRateProviders.sol";

import { IBoringVault } from "./IBoringVault.sol";
import { ITeller } from "./ITeller.sol";

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";

interface ILens {

    error InvalidVault();

    function totalAssets(
        IBoringVault vault,
        IAccountantWithRateProviders accountant
    ) external view returns (IERC20 asset, uint256 assets);

    function previewDeposit(
        IERC20 depositAsset,
        uint256 depositAmount,
        IBoringVault vault,
        IAccountantWithRateProviders accountant
    ) external view returns (uint256 shares);

    function balanceOf(address account, IBoringVault vault) external view returns (uint256 shares);

    function balanceOfInAssets(
        address account,
        IBoringVault vault,
        IAccountantWithRateProviders accountant
    ) external view returns (uint256 assets);

    function exchangeRate(
        IAccountantWithRateProviders accountant
    ) external view returns (uint256 rate);

    function checkUserDeposit(
        address account,
        IERC20 depositAsset,
        uint256 depositAmount,
        IBoringVault vault,
        ITeller teller
    ) external view returns (bool);

}
