// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockInvalidToken is ERC20 {

    constructor() ERC20("Invalid Token", "INVALID") {
        _mint(msg.sender, 1_000_000 * 10 ** decimals());
    }

    function decimals() public pure override returns (uint8) {
        return 12; // Different from USDC's 6 decimals
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

}
