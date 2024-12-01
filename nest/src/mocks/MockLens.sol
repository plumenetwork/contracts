// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IAccountantWithRateProviders } from "../interfaces/IAccountantWithRateProviders.sol";
import { ILens } from "../interfaces/ILens.sol";
import { ITeller } from "../interfaces/ITeller.sol";
import { IVault } from "../interfaces/IVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";

contract MockLens is ILens {

    using FixedPointMathLib for uint256;

    function totalAssets(
        IVault vault,
        IAccountantWithRateProviders accountant
    ) external view override returns (IERC20 asset, uint256 assets) {
        uint256 totalSupply = vault.totalSupply();
        uint256 rate = accountant.getRate();
        return (IERC20(address(0)), totalSupply.mulDivDown(rate, 10 ** 6));
    }

    function previewDeposit(
        IERC20 depositAsset,
        uint256 depositAmount,
        IVault vault,
        IAccountantWithRateProviders accountant
    ) external view override returns (uint256 shares) {
        uint256 rate = accountant.getRate();
        return depositAmount.mulDivDown(10 ** 6, rate);
    }

    function balanceOf(address account, IVault vault) external view override returns (uint256 shares) {
        shares = vault.balanceOf(account);
    }

    function balanceOfInAssets(
        address account,
        IVault vault,
        IAccountantWithRateProviders accountant
    ) external view override returns (uint256 assets) {
        uint256 shares = vault.balanceOf(account);
        uint256 rate = accountant.getRate();
        uint8 shareDecimals = vault.decimals();

        assets = shares.mulDivDown(rate, 10 ** shareDecimals);
    }

    function exchangeRate(
        IAccountantWithRateProviders accountant
    ) external view override returns (uint256 rate) {
        return accountant.getRate();
    }

    function checkUserDeposit(
        address account,
        IERC20 depositAsset,
        uint256 depositAmount,
        IVault vault,
        ITeller teller
    ) external view override returns (bool) {
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
