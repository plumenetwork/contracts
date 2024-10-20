// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title USDTAsset
 * @author Eugene Y. Q. Shen
 * @notice Base asset for USDT ComponentToken
 */
contract USDTAsset is ERC20, Ownable {

    constructor(
        address owner_
    ) ERC20("USDTAsset", "USDT_") Ownable(owner_) { }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

}
