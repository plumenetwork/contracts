// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { YieldDistributionToken } from "../../src/token/YieldDistributionToken.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { UserState } from "../../src/token/Types.sol";
import { console2 } from "forge-std/console2.sol";

contract YieldDistributionTokenHarness is YieldDistributionToken {

    // silence warnings
    uint256 requestCounter;

    constructor(
        address owner,
        string memory name,
        string memory symbol,
        IERC20 currencyToken,
        uint8 decimals_,
        string memory tokenURI
    ) YieldDistributionToken(owner, name, symbol, currencyToken, decimals_, tokenURI) { }

    function exposed_mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function exposed_burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function exposed_depositYield(
        uint256 currencyTokenAmount
    ) external {
        _depositYield(currencyTokenAmount);
    }

    function exposed_getTotalAmountSeconds() external view returns (uint256) {
        return _getYieldDistributionTokenStorage().totalAmountSeconds;
    }

    // silence warnings
    function requestYield(
        address
    ) external override {
        ++requestCounter;
    }

    function logUserState(address user, string memory prelog) external view {
        UserState memory userState = this.getUserState(user);
        console2.log("\n%s", prelog);
        console2.log("\tamountSeconds:", userState.amountSeconds);
        console2.log("\tamountSecondsDeduction:", userState.amountSecondsDeduction);
        console2.log("\tlastUpdate:", userState.lastUpdate);
        console2.log("\tlastDepositIndex:", userState.lastDepositIndex);
        console2.log("\tyieldAccrued:", userState.yieldAccrued);
        console2.log("\tyieldWithdrawn:", userState.yieldWithdrawn);
    }

}
