// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IAccountantWithRateProviders } from "../interfaces/IAccountantWithRateProviders.sol";

import { IRateProvider } from "../interfaces/IRateProvider.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";

contract MockAccountantWithRateProviders is IAccountantWithRateProviders {

    using FixedPointMathLib for uint256;

    AccountantState private _accountantState;
    mapping(ERC20 => RateProviderData) private _rateProviderData;

    ERC20 public immutable base;
    uint8 public immutable decimals;
    address public immutable vault;

    constructor(address _vault, address _base, uint96 startingExchangeRate) {
        vault = _vault;
        base = ERC20(_base);
        decimals = ERC20(_base).decimals();

        _accountantState.exchangeRate = startingExchangeRate;
        _accountantState.allowedExchangeRateChangeUpper = 1.1e4; // 110%
        _accountantState.allowedExchangeRateChangeLower = 0.9e4; // 90%
        _accountantState.minimumUpdateDelayInSeconds = 1 hours;
        _accountantState.managementFee = 0.1e4; // 0.1%
    }

    function accountantState() external view returns (AccountantState memory) {
        return _accountantState;
    }

    function rateProviderData(
        ERC20 token
    ) external view returns (RateProviderData memory) {
        return _rateProviderData[token];
    }

    // Admin functions
    function pause() external {
        _accountantState.isPaused = true;
        emit Paused();
    }

    function unpause() external {
        _accountantState.isPaused = false;
        emit Unpaused();
    }

    function updateDelay(
        uint32 minimumUpdateDelayInSeconds
    ) external {
        uint32 oldDelay = _accountantState.minimumUpdateDelayInSeconds;
        _accountantState.minimumUpdateDelayInSeconds = minimumUpdateDelayInSeconds;
        emit DelayInSecondsUpdated(oldDelay, minimumUpdateDelayInSeconds);
    }

    function updateUpper(
        uint16 allowedExchangeRateChangeUpper
    ) external {
        uint16 oldBound = _accountantState.allowedExchangeRateChangeUpper;
        _accountantState.allowedExchangeRateChangeUpper = allowedExchangeRateChangeUpper;
        emit UpperBoundUpdated(oldBound, allowedExchangeRateChangeUpper);
    }

    function updateLower(
        uint16 allowedExchangeRateChangeLower
    ) external {
        uint16 oldBound = _accountantState.allowedExchangeRateChangeLower;
        _accountantState.allowedExchangeRateChangeLower = allowedExchangeRateChangeLower;
        emit LowerBoundUpdated(oldBound, allowedExchangeRateChangeLower);
    }

    function updateManagementFee(
        uint16 managementFee
    ) external {
        uint16 oldFee = _accountantState.managementFee;
        _accountantState.managementFee = managementFee;
        emit ManagementFeeUpdated(oldFee, managementFee);
    }

    function updatePayoutAddress(
        address payoutAddress
    ) external {
        address oldPayout = _accountantState.payoutAddress;
        _accountantState.payoutAddress = payoutAddress;
        emit PayoutAddressUpdated(oldPayout, payoutAddress);
    }

    // Match the interface signature exactly
    function setRateProviderData(ERC20 asset, bool isPeggedToBase, address rateProvider) external override {
        _rateProviderData[asset] =
            RateProviderData({ isPeggedToBase: isPeggedToBase, rateProvider: IRateProvider(rateProvider) });
        emit RateProviderUpdated(address(asset), isPeggedToBase, rateProvider);
    }

    function updateExchangeRate(
        uint96 newExchangeRate
    ) external {
        uint96 oldRate = _accountantState.exchangeRate;
        _accountantState.exchangeRate = newExchangeRate;
        emit ExchangeRateUpdated(oldRate, newExchangeRate, uint64(block.timestamp));
    }

    function claimFees(
        ERC20 feeAsset
    ) external {
        emit FeesClaimed(address(feeAsset), 0);
    }

    // Rate functions
    function getRate() external view returns (uint256 rate) {
        return _accountantState.exchangeRate;
    }

    function getRateSafe() external view returns (uint256 rate) {
        require(!_accountantState.isPaused, "Accountant: paused");
        return _accountantState.exchangeRate;
    }

    function getRateInQuote(
        ERC20 quote
    ) external view returns (uint256 rateInQuote) {
        if (address(quote) == address(base)) {
            return _accountantState.exchangeRate;
        }
        RateProviderData memory data = _rateProviderData[quote];
        return data.isPeggedToBase ? _accountantState.exchangeRate : data.rateProvider.getRate();
    }

    function getRateInQuoteSafe(
        ERC20 quote
    ) external view returns (uint256 rateInQuote) {
        require(!_accountantState.isPaused, "Accountant: paused");
        return this.getRateInQuote(quote);
    }

}
