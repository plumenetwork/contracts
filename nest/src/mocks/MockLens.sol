// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ILens } from "../interfaces/ILens.sol";

import { MockAccountantWithRateProviders } from "./MockAccountantWithRateProviders.sol";
import { MockTeller } from "./MockTeller.sol";
import { MockVault } from "./MockVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";

contract MockLens is ILens {

    using FixedPointMathLib for uint256;

    function totalAssets(
        MockVault vault,
        MockAccountantWithRateProviders accountant
    ) external view returns (IERC20 asset, uint256 assets) {
        uint256 totalSupply = vault.totalSupply();
        uint256 rate = accountant.getRate();
        return (IERC20(address(0)), totalSupply.mulDivDown(rate, 10 ** 6)); // Using 6 decimals as per MockVault
    }

    function previewDeposit(
        IERC20 depositAsset,
        uint256 depositAmount,
        MockVault vault,
        MockAccountantWithRateProviders accountant
    ) external view returns (uint256 shares) {
        uint256 rate = accountant.getRate();
        return depositAmount.mulDivDown(10 ** 6, rate); // Using 6 decimals as per MockVault
    }

    function balanceOf(address account, MockVault vault) external view returns (uint256 shares) {
        return vault.tokenBalance(address(vault), account);
    }

    function balanceOfInAssets(
        address account,
        MockVault vault,
        MockAccountantWithRateProviders accountant
    ) external view returns (uint256 assets) {
        uint256 shares = vault.tokenBalance(address(vault), account);
        uint256 rate = accountant.getRate();
        return shares.mulDivDown(rate, 10 ** 6); // Using 6 decimals as per MockVault
    }

    function exchangeRate(
        MockAccountantWithRateProviders accountant
    ) external view returns (uint256 rate) {
        return accountant.getRate();
    }

    function checkUserDeposit(
        address account,
        IERC20 depositAsset,
        uint256 depositAmount,
        MockVault vault,
        MockTeller teller
    ) external view returns (bool) {
        if (depositAsset.balanceOf(account) < depositAmount) {
            return false;
        }
        if (depositAsset.allowance(account, address(vault)) < depositAmount) {
            return false;
        }
        if (teller.isPaused()) {
            return false;
        }
        if (!teller.isSupported(depositAsset)) {
            return false;
        }
        return true;
    }

}
