// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { WETH } from "solady/tokens/WETH.sol";

contract WPLUME is WETH {
    function name() public pure override returns (string memory) {
        return "Wrapped Plume";
    }
    function symbol() public pure override returns (string memory) {
        return "WPLUME";
    }
}