// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface InYSV {

    // View Functions
    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external view returns (uint8);
    function balanceOf(
        address account
    ) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function asset() external view returns (address);
    function totalAssets() external view returns (uint256);
    function assetsOf(
        address owner
    ) external view returns (uint256);
    function convertToShares(
        uint256 assets
    ) external view returns (uint256);
    function convertToAssets(
        uint256 shares
    ) external view returns (uint256);

    // State-Changing Functions
    function deposit(uint256 assets, address receiver, address controller) external returns (uint256);
    function requestDeposit(uint256 assets, address controller, address owner) external returns (uint256);
    function requestRedeem(uint256 shares, address controller, address owner) external returns (uint256);

    // Admin Functions
    function initialize(
        address _vault,
        address _accountant,
        address _teller,
        address _atomicQueue,
        IERC20 _asset,
        uint256 _minimumMintPercentage,
        uint256 _deadlinePeriod,
        uint256 _pricePercentage
    ) external;

    // Events
    event RequestRedeem(uint256 shares, address controller, address owner);

}
