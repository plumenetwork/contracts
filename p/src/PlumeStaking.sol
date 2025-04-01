// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { PlumeStakingManager } from "./modules/PlumeStakingManager.sol";

/**
 * @title PlumeStaking
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Main facade for PlumeStaking functionality
 * @dev This contract serves as the entry point to PlumeStaking functionality
 */
contract PlumeStaking is PlumeStakingManager {

    /**
     * @notice Initialize PlumeStaking
     * @param owner Address of the owner of PlumeStaking
     */
    function initialize(
        address owner
    ) public override initializer {
        super.initialize(owner);
    }

}
