// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { PlumeStakingStorage } from "./PlumeStakingStorage.sol";
// Import errors/events if needed by logic
import "./PlumeErrors.sol";
import "./PlumeEvents.sol";

/**
 * @title PlumeValidatorLogic
 * @notice Internal library containing shared logic for validator management and checks.
 */
library PlumeValidatorLogic {

    using PlumeStakingStorage for PlumeStakingStorage.Layout;

    /**
     * @notice Adds a staker to the validator's list and the user's validator list if not already present.
     * @dev Also ensures the staker is added to the global stakers list if they are new.
     * @param $ The PlumeStaking storage layout.
     * @param staker The address of the staker.
     * @param validatorId The ID of the validator.
     */
    function addStakerToValidator(PlumeStakingStorage.Layout storage $, address staker, uint16 validatorId) internal {
        // This replaces _addStakerToValidator from ValidatorFacet
        if (!$.userHasStakedWithValidator[staker][validatorId]) {
            $.userValidators[staker].push(validatorId);
            $.userHasStakedWithValidator[staker][validatorId] = true;
        }
        if (!$.isStakerForValidator[validatorId][staker]) {
            $.validatorStakers[validatorId].push(staker);
            $.isStakerForValidator[validatorId][staker] = true;
        }
        // Call the library version of the helper function
        addStakerIfNew($, staker);
    }

    /**
     * @notice Adds a staker to the global stakers list if they have a stake and are not already listed.
     * @param $ The PlumeStaking storage layout.
     * @param staker The address of the staker.
     */
    function addStakerIfNew(PlumeStakingStorage.Layout storage $, address staker) internal {
        // This replaces _addStakerIfNew from ValidatorFacet
        // Check global stake info, not validator specific
        if ($.stakeInfo[staker].staked > 0 && !$.isStaker[staker]) {
            $.stakers.push(staker);
            $.isStaker[staker] = true;
            // emit PlumeEvents.StakerAdded(staker);
        }
    }

    /**
     * @notice Removes a staker from the validator's list if they have no stake left with this validator.
     * @dev This should be called after unstaking when a user's stake with a validator reaches zero.
     * @param $ The PlumeStaking storage layout.
     * @param staker The address of the staker.
     * @param validatorId The ID of the validator.
     */
    function removeStakerFromValidator(
        PlumeStakingStorage.Layout storage $,
        address staker,
        uint16 validatorId
    ) internal {
        // Only proceed if the user has no stake left with this validator
        if ($.userValidatorStakes[staker][validatorId].staked == 0 && $.isStakerForValidator[validatorId][staker]) {
            // Remove staker from validator's staker list by replacing with the last element
            address[] storage stakers = $.validatorStakers[validatorId];
            for (uint256 i = 0; i < stakers.length; i++) {
                if (stakers[i] == staker) {
                    // Replace with the last element and remove the last element
                    stakers[i] = stakers[stakers.length - 1];
                    stakers.pop();
                    break;
                }
            }

            // Update the mapping to show staker is no longer staking with this validator
            $.isStakerForValidator[validatorId][staker] = false;

            // Optionally, also remove validator from user's validator list if needed
            // (only if we want to keep this list accurate)
            if ($.userHasStakedWithValidator[staker][validatorId]) {
                uint16[] storage userValidators = $.userValidators[staker];
                for (uint256 i = 0; i < userValidators.length; i++) {
                    if (userValidators[i] == validatorId) {
                        userValidators[i] = userValidators[userValidators.length - 1];
                        userValidators.pop();
                        break;
                    }
                }
                $.userHasStakedWithValidator[staker][validatorId] = false;
            }
        }
    }

}
