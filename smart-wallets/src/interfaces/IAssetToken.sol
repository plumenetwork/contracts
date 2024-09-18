// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IYieldDistributionToken } from "./IYieldDistributionToken.sol";

interface IAssetToken is IYieldDistributionToken {

    function setTotalValue(uint256 totalValue) external;
    function enableWhitelist() external;
    function addToWhitelist(address user) external;
    function removeFromWhitelist(address user) external;
    function mint(address user, uint256 assetTokenAmount) external;
    function depositYield(uint256 timestamp, uint256 currencyTokenAmount) external;

    function getTotalValue() external view returns (uint256 totalValue);
    function isWhitelistEnabled() external view returns (bool enabled);
    function getWhitelist() external view returns (address[] memory whitelist);
    function isAddressWhitelisted(address user) external view returns (bool whitelisted);
    function getHolders() external view returns (address[] memory holders);
    function hasBeenHolder(address user) external view returns (bool held);
    function getPricePerToken() external view returns (uint256 price);
    function getBalanceAvailable(address user) external view returns (uint256 balanceAvailable);

    function totalYield() external view returns (uint256 amount);
    function claimedYield() external view returns (uint256 amount);
    function unclaimedYield() external view returns (uint256 amount);
    function totalYield(address user) external view returns (uint256 amount);
    function claimedYield(address user) external view returns (uint256 amount);
    function unclaimedYield(address user) external view returns (uint256 amount);

}
