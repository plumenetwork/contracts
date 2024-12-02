// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IRateProvider } from "./IRateProvider.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";

interface IAccountantWithRateProviders {

    struct AccountantState {
        address payoutAddress;
        uint128 feesOwedInBase;
        uint128 totalSharesLastUpdate;
        uint96 exchangeRate;
        uint16 allowedExchangeRateChangeUpper;
        uint16 allowedExchangeRateChangeLower;
        uint64 lastUpdateTimestamp;
        bool isPaused;
        uint32 minimumUpdateDelayInSeconds;
        uint16 managementFee;
    }

    struct RateProviderData {
        bool isPeggedToBase;
        IRateProvider rateProvider;
    }

    function accountantState() external view returns (AccountantState calldata);
    function rateProviderData(
        ERC20 token
    ) external view returns (RateProviderData calldata);

    function base() external view returns (ERC20);
    function decimals() external view returns (uint8);
    function vault() external view returns (address);

    function pause() external;
    function unpause() external;
    function updateDelay(
        uint32 minimumUpdateDelayInSeconds
    ) external;
    function updateUpper(
        uint16 allowedExchangeRateChangeUpper
    ) external;
    function updateLower(
        uint16 allowedExchangeRateChangeLower
    ) external;
    function updateManagementFee(
        uint16 managementFee
    ) external;
    function updatePayoutAddress(
        address payoutAddress
    ) external;
    function setRateProviderData(ERC20 asset, bool isPeggedToBase, address rateProvider) external;
    function updateExchangeRate(
        uint96 newExchangeRate
    ) external;
    function claimFees(
        ERC20 feeAsset
    ) external;

    function getRate() external view returns (uint256 rate);
    function getRateSafe() external view returns (uint256 rate);
    function getRateInQuote(
        ERC20 quote
    ) external view returns (uint256 rateInQuote);
    function getRateInQuoteSafe(
        ERC20 quote
    ) external view returns (uint256 rateInQuote);

    event Paused();
    event Unpaused();
    event DelayInSecondsUpdated(uint32 oldDelay, uint32 newDelay);
    event UpperBoundUpdated(uint16 oldBound, uint16 newBound);
    event LowerBoundUpdated(uint16 oldBound, uint16 newBound);
    event ManagementFeeUpdated(uint16 oldFee, uint16 newFee);
    event PayoutAddressUpdated(address oldPayout, address newPayout);
    event RateProviderUpdated(address asset, bool isPegged, address rateProvider);
    event ExchangeRateUpdated(uint96 oldRate, uint96 newRate, uint64 currentTime);
    event FeesClaimed(address indexed feeAsset, uint256 amount);

}
