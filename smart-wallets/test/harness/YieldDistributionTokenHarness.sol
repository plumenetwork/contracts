// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { YieldDistributionToken } from "../../src/token/YieldDistributionToken.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

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

    function exposed_depositYield(uint256 currencyTokenAmount) external {
        _depositYield(currencyTokenAmount);
    }

    // silence warnings
    function requestYield(address) external override {
        ++requestCounter;
    }

}
