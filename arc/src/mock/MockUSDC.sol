// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockUSDC
 * @notice A mock USDC token for testing purposes
 */
contract MockUSDC is ERC20, Ownable {

    uint8 private _decimals = 6; // USDC uses 6 decimals

    constructor() ERC20("USD Coin (Mock)", "USDC") Ownable(msg.sender) { }

    /**
     * @notice Mint tokens to a specified address
     * @param to The address to mint tokens to
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @notice Burns tokens from the caller's address
     * @param amount The amount of tokens to burn
     */
    function burn(
        uint256 amount
    ) external {
        _burn(msg.sender, amount);
    }

    /**
     * @notice Override decimals to match USDC's 6 decimals
     */
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

}
