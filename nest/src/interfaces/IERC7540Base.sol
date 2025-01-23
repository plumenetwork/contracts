// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title IERC7540
 * @notice Interface for ERC7540 standard which extends ERC4626 with controller functionality
 */
interface IERC7540 is IERC4626, IERC165 {

    function deposit(uint256 assets, address receiver, address controller) external returns (uint256 shares);

    function mint(uint256 shares, address receiver, address controller) external returns (uint256 assets);

    function withdraw(uint256 assets, address receiver, address controller) external returns (uint256 shares);

    function redeem(uint256 shares, address receiver, address controller) external returns (uint256 assets);

}
