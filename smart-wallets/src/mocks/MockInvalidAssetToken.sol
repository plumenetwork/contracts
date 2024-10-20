// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../interfaces/IAssetToken.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockInvalidAssetToken is IAssetToken {

    // small hack to be excluded from coverage report
    function test() public { }

    function getCurrencyToken() external pure override returns (IERC20) {
        return IERC20(address(0));
    }

    function accrueYield(
        address
    ) external pure override { }

    function allowance(address, address) external pure override returns (uint256) {
        return 0;
    }

    function approve(address, uint256) external pure override returns (bool) {
        return false;
    }

    function balanceOf(
        address
    ) external pure override returns (uint256) {
        return 0;
    }

    function claimYield(
        address
    ) external pure override returns (IERC20, uint256) {
        return (IERC20(address(0)), 0);
    }

    function depositYield(
        uint256
    ) external pure override { }

    function getBalanceAvailable(
        address
    ) external pure override returns (uint256) {
        return 0;
    }

    function requestYield(
        address
    ) external pure override { }

    function totalSupply() external pure override returns (uint256) {
        return 0;
    }

    function transfer(address, uint256) external pure override returns (bool) {
        return false;
    }

    function transferFrom(address, address, uint256) external pure override returns (bool) {
        return false;
    }

}
