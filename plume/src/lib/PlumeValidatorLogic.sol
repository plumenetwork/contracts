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
     * @notice Get validator info from storage
     * @param $ The storage layout reference
     * @param validatorId The ID of the validator to get info for
     * @return The validator info struct
     */
    function getValidatorInfo(
        PlumeStakingStorage.Layout storage $,
        uint16 validatorId
    ) internal view returns (PlumeStakingStorage.ValidatorInfo storage) {
        return $.validators[validatorId];
    }

    /**
     * @notice Check if a validator is active
     * @param $ The storage layout reference
     * @param validatorId The ID of the validator to check
     * @return True if the validator is active, false otherwise
     */
    function isValidatorActive(PlumeStakingStorage.Layout storage $, uint16 validatorId) internal view returns (bool) {
        return $.validators[validatorId].active;
    }

    /**
     * @notice Get the total amount staked with a validator
     * @param $ The storage layout reference
     * @param validatorId The ID of the validator
     * @return The total amount staked with the validator
     */
    function getValidatorTotalStaked(
        PlumeStakingStorage.Layout storage $,
        uint16 validatorId
    ) internal view returns (uint256) {
        return $.validatorTotalStaked[validatorId];
    }

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
            // === Store index before pushing ===
            uint256 index = $.validatorStakers[validatorId].length;
            $.validatorStakers[validatorId].push(staker);
            $.isStakerForValidator[validatorId][staker] = true;
            $.userIndexInValidatorStakers[staker][validatorId] = index; // <<< Store the index
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
        // Only proceed if the user has no stake left with this validator AND they were previously a staker
        if ($.userValidatorStakes[staker][validatorId].staked == 0 && $.isStakerForValidator[validatorId][staker]) {
            // --- Swap and Pop from validatorStakers array ---
            address[] storage stakersList = $.validatorStakers[validatorId];
            uint256 listLength = stakersList.length;

            // Ensure list is not empty before proceeding
            if (listLength > 0) {
                // 1. Get the index of the staker to remove
                uint256 indexToRemove = $.userIndexInValidatorStakers[staker][validatorId];

                // Check if index is valid (sanity check)
                if (indexToRemove < listLength && stakersList[indexToRemove] == staker) {
                    // 2. Get the address of the last staker in the list
                    address lastStaker = stakersList[listLength - 1];

                    // 3. If the staker to remove is NOT the last element, swap it with the last element
                    if (indexToRemove != listLength - 1) {
                        stakersList[indexToRemove] = lastStaker;
                        // 4. Update the index mapping for the moved (last) staker
                        $.userIndexInValidatorStakers[lastStaker][validatorId] = indexToRemove;
                    }

                    // 5. Pop the last element (which is either the one we want to remove, or a duplicate of the one we
                    // moved)
                    stakersList.pop();
                } else {
                    // This case should ideally not happen if storage is consistent
                    // Handle error or log? For now, just skip the swap/pop for safety.
                    // console.log("Inconsistency: Staker index not found or mismatch in removeStakerFromValidator");
                }
            }

            // --- Cleanup Mappings ---
            // Update the mapping to show staker is no longer staking with this validator
            $.isStakerForValidator[validatorId][staker] = false;
            // Delete the stored index for the removed staker
            delete $.userIndexInValidatorStakers[staker][validatorId];

            // --- Remove validator from user's list (if needed) ---
            if ($.userHasStakedWithValidator[staker][validatorId]) {
                uint16[] storage userValidators = $.userValidators[staker];
                // Use swap and pop for the user's list as well (assuming order doesn't matter)
                for (uint256 i = 0; i < userValidators.length; i++) {
                    if (userValidators[i] == validatorId) {
                        userValidators[i] = userValidators[userValidators.length - 1];
                        userValidators.pop();
                        break; // Found and removed
                    }
                }
                $.userHasStakedWithValidator[staker][validatorId] = false;
            }
        }
    }

    // /**
    //  * @notice Adds a validator ID to a user's list of staked validators if not already present.
    //  * @dev Internal function to manage the user's list of validators.
    //  * @param $ The PlumeStaking storage layout.
    //  * @param user The address of the staker.
    //  * @param validatorId The ID of the validator being staked with.
    //  */
    // function addStakerToValidatorList(
    //     PlumeStakingStorage.Layout storage $,
    //     address user,
    //     uint16 validatorId
    // ) internal {
    //     uint16[] storage validatorList = $.userValidatorsList[user];
    //     // Check if the validator is already in the list
    //     for (uint256 i = 0; i < validatorList.length; i++) {
    //         if (validatorList[i] == validatorId) {
    //             return; // Already exists, do nothing
    //         }
    //     }
    //     // If not found, add it
    //     validatorList.push(validatorId);
    // }

}
