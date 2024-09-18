// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { ERC20Pausable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";

/**
 * @title pUSD
 * @author Eugene Y. Q. Shen
 * @notice ERC20 token that is the native stablecoin of Plume Network
 * @dev Owner can mint and burn tokens at will on Plume Devnet
 */
contract pUSD is ERC20, ERC20Burnable, ERC20Pausable, AccessControl {

    // Constants

    /// @notice Role for the minter of pUSD
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    /// @notice Role for the pauser of pUSD
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // Constructor

    /**
     * @notice Initialize pUSD
     * @param owner Address of the owner of pUSD
     */
    constructor(address owner) ERC20("Plume USD Stablecoin", "pUSD") {
        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(PAUSER_ROLE, owner);
        _grantRole(MINTER_ROLE, owner);
    }

    // Override Functions

    /**
     * @notice Update the balance of `from` and `to` after token transfer
     * @param from Address to transfer tokens from
     * @param to Address to transfer tokens to
     * @param value Amount of tokens to transfer
     */
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Pausable) {
        super._update(from, to, value);
    }

    /// @notice Number of decimals of pUSD
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    // Admin Functions

    /// @notice Pause the contract, only the pauser can call this
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpause the contract, only the pauser can call this
    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @notice Mint new tokens, only the minter can call this
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

}
