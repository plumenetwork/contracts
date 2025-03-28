// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { PlumeStakingAdmin } from "./modules/PlumeStakingAdmin.sol";
import { PlumeStakingBase } from "./modules/PlumeStakingBase.sol";
import { PlumeStakingRewards } from "./modules/PlumeStakingRewards.sol";
import { PlumeStakingValidator } from "./modules/PlumeStakingValidator.sol";

/**
 * @title PlumeStaking
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Main facade for PlumeStaking functionality
 * @dev This contract serves as the entry point to PlumeStaking functionality
 *      It inherits from the specialized modules to provide a complete interface
 */
contract PlumeStaking is PlumeStakingBase, PlumeStakingValidator, PlumeStakingRewards, PlumeStakingAdmin { }
