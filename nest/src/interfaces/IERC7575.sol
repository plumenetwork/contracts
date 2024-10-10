// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IERC7575 is IERC165, IERC4626 {

    /// @notice Address of the underlying `share` receivd on deposit into the vault
    function share() external view returns (address shareTokenAddress);

}
