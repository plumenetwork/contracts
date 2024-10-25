// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockYieldCurrency is ERC20 {

    // small hack to be excluded from coverage report
    function test() public { }

    constructor() ERC20("Yield Currency", "YC") { }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

}
