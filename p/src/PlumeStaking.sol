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
contract PlumeStaking is PlumeStakingBase, PlumeStakingValidator, PlumeStakingRewards, PlumeStakingAdmin {

    /**
     * @notice Initialize PlumeStaking
     * @param owner Address of the owner of PlumeStaking
     * @param pUSD_ Address of the pUSD token
     */
    function initialize(address owner, address pUSD_) public override initializer {
        super.initialize(owner, pUSD_);
    }

    /**
     * @notice Add a staker to a validator's staker list
     * @param staker Address of the staker
     * @param validatorId ID of the validator
     */
    function _addStakerToValidator(
        address staker,
        uint16 validatorId
    ) internal virtual override(PlumeStakingBase, PlumeStakingValidator) {
        PlumeStakingValidator._addStakerToValidator(staker, validatorId);
    }

    /**
     * @notice Update rewards for a user on a specific validator
     * @param user Address of the user
     * @param validatorId ID of the validator
     */
    function _updateRewardsForValidator(
        address user,
        uint16 validatorId
    ) internal virtual override(PlumeStakingBase, PlumeStakingValidator) {
        PlumeStakingValidator._updateRewardsForValidator(user, validatorId);
    }

    /**
     * @notice Update the reward per token value for a specific validator
     * @param token The address of the reward token
     * @param validatorId The ID of the validator
     */
    function _updateRewardPerTokenForValidator(
        address token,
        uint16 validatorId
    ) internal virtual override(PlumeStakingBase, PlumeStakingValidator) {
        PlumeStakingValidator._updateRewardPerTokenForValidator(token, validatorId);
    }

    /**
     * @notice Update rewards for all stakers of a validator
     * @param validatorId ID of the validator
     */
    function _updateRewardsForAllValidatorStakers(
        uint16 validatorId
    ) internal virtual override(PlumeStakingBase, PlumeStakingValidator) {
        PlumeStakingValidator._updateRewardsForAllValidatorStakers(validatorId);
    }

}
