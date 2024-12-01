// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { MockAccountantWithRateProviders } from "../mocks/MockAccountantWithRateProviders.sol";
import { MockTeller } from "../mocks/MockTeller.sol";
import { MockVault } from "../mocks/MockVault.sol";

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";

interface ILens {

    function totalAssets(
        MockVault vault,
        MockAccountantWithRateProviders accountant
    ) external view returns (IERC20 asset, uint256 assets);

    function previewDeposit(
        IERC20 depositAsset,
        uint256 depositAmount,
        MockVault vault,
        MockAccountantWithRateProviders accountant
    ) external view returns (uint256 shares);

    function balanceOf(address account, MockVault vault) external view returns (uint256 shares);

    function balanceOfInAssets(
        address account,
        MockVault vault,
        MockAccountantWithRateProviders accountant
    ) external view returns (uint256 assets);

    function exchangeRate(
        MockAccountantWithRateProviders accountant
    ) external view returns (uint256 rate);

    function checkUserDeposit(
        address account,
        IERC20 depositAsset,
        uint256 depositAmount,
        MockVault vault,
        MockTeller teller
    ) external view returns (bool);

}
