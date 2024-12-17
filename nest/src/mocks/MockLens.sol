// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IAccountantWithRateProviders } from "../interfaces/IAccountantWithRateProviders.sol";

import { IBoringVault } from "../interfaces/IBoringVault.sol";
import { ILens } from "../interfaces/ILens.sol";
import { ITeller } from "../interfaces/ITeller.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import "forge-std/console2.sol";

contract MockLens is ILens {

    using FixedPointMathLib for uint256;

    mapping(uint256 => uint256) private previewDepositValues;
    mapping(uint256 => uint256) private previewRedeemValues;
    mapping(address => uint256) private balances;
    mapping(address => mapping(address => uint256)) private vaultBalances;
    mapping(IERC20 => bool) public supportedAssets;

    function setSupportedAsset(IERC20 asset, bool supported) external {
        supportedAssets[asset] = supported;
    }

    function totalAssets(
        IBoringVault vault,
        IAccountantWithRateProviders accountant
    ) external view override returns (IERC20 asset, uint256 assets) {
        uint256 totalSupply = vault.totalSupply();
        uint256 rate = accountant.getRate();
        return (IERC20(address(0)), totalSupply.mulDivDown(rate, 10 ** 6));
    }

    function previewDeposit(
        IERC20 depositAsset,
        uint256 depositAmount,
        IBoringVault vault,
        IAccountantWithRateProviders accountant
    ) external view override returns (uint256 shares) {
        // Check if we have a preset value
        if (previewDepositValues[depositAmount] != 0) {
            return previewDepositValues[depositAmount];
        }

        uint256 rate = accountant.getRate();

        try vault.decimals() returns (uint8 shareDecimals) {
            return depositAmount.mulDivDown(10 ** shareDecimals, rate);
        } catch {
            revert InvalidVault();
        }
    }

    function setPreviewDeposit(uint256 assets, uint256 shares) external {
        previewDepositValues[assets] = shares;
    }

    function setPreviewRedeem(uint256 shares, uint256 assets) external {
        previewRedeemValues[shares] = assets;
    }

    function setBalance(address account, uint256 balance) external {
        balances[account] = balance;
    }

    function balanceOf(address account, IBoringVault vault) external view override returns (uint256) {
        // First check if we have a preset balance
        if (balances[account] != 0) {
            return balances[account];
        }
        // Otherwise return the vault balance
        return vault.balanceOf(account);
    }

    function balanceOfInAssets(
        address account,
        IBoringVault vault,
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
        IBoringVault vault,
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
