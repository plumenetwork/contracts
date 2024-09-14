// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

interface IP is IERC20, IERC20Metadata, IERC20Permit {

    /**
     * @notice Mint new tokens
     * @dev Only the minter can mint new tokens
     * @param to The address to mint the tokens to
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) external;

    /**
     * @notice Burn tokens
     * @dev Only the burner can burn tokens
     * @param from The address to burn the tokens from
     * @param amount The amount of tokens to burn
     */
    function burn(address from, uint256 amount) external;

    /**
     * @notice Pause the contract
     * @dev Only the pauser can pause the contract
     */
    function pause() external;

    /**
     * @notice Unpause the contract
     * @dev Only the pauser can unpause the contract
     */
    function unpause() external;

}
