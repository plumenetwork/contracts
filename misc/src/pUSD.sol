// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract pUSD is ERC20 {
    // @dev This is a simple ERC20 contract for Plume USD on Plume Testnet
    constructor() ERC20("Plume USD", "pUSD") {
        _mint(msg.sender, 1_000_000_000 * 10 ** decimals());
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

