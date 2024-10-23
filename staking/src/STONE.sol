// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title STONE
 * @author Eugene Y. Q. Shen
 * @notice Sample STONE contract for testnet deployment
 */
contract STONE is ERC20, Ownable {

    constructor(address owner_) ERC20("StakeStone Ether", "STONE") Ownable(owner_) { }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

}
