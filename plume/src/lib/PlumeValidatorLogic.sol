// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { PlumeStakingStorage } from "./PlumeStakingStorage.sol";
// Import errors/events if needed by logic
import "./PlumeErrors.sol";
import "./PlumeEvents.sol";
import { console2 } from "forge-std/console2.sol";
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
    }

    /**
     * @notice Removes a staker from the validator's list if they have no stake left with this validator.
     * @dev This should be called after unstaking when a user's stake with a validator reaches zero.
     * @param $ The PlumeStaking storage layout.
     * @param staker The address of the staker.
     * @param validatorId The ID of the validator.
     */
    // File: plume/src/lib/PlumeValidatorLogic.sol

    function removeStakerFromValidator(
        PlumeStakingStorage.Layout storage $,
        address staker,
        uint16 validatorId
    ) internal {
        console2.log("PVL.removeStakerFromValidator --- ENTRY --- User: %s, ValidatorID: %s", staker, validatorId);

        // Part 1: Manage $.validatorStakers list (validator's list of its ACTIVE stakers)
        // This runs if active stake with this validator becomes zero AND they were previously listed as an active
        // staker for it.
        if ($.userValidatorStakes[staker][validatorId].staked == 0 && $.isStakerForValidator[validatorId][staker]) {
            console2.log(
                "PVL (Part 1): User %s, Val %s - Active stake is 0 and was in validatorStakers. Removing from validatorStakers.",
                staker,
                validatorId
            );

            address[] storage stakersList = $.validatorStakers[validatorId];
            uint256 listLength = stakersList.length;
            if (listLength > 0) {
                uint256 indexToRemove = $.userIndexInValidatorStakers[staker][validatorId];
                if (indexToRemove < listLength && stakersList[indexToRemove] == staker) {
                    address lastStaker = stakersList[listLength - 1];
                    if (indexToRemove != listLength - 1) {
                        stakersList[indexToRemove] = lastStaker;
                        $.userIndexInValidatorStakers[lastStaker][validatorId] = indexToRemove;
                    }
                    stakersList.pop();
                }
            }
            $.isStakerForValidator[validatorId][staker] = false; // Correctly marks they are no longer an ACTIVE staker
                // for this validator
            delete $.userIndexInValidatorStakers[staker][validatorId];
            console2.log(
                "PVL (Part 1): User %s, Val %s - Done with validatorStakers. isStakerForValidator is now false.",
                staker,
                validatorId
            );
        }

        // Part 2: Manage $.userValidators list (user's list of ANY association with a validator)
        // This runs if active stake for this validator is zero AND their cooldown amount for this validator is zero.
        bool hasActiveStakeForThisVal = $.userValidatorStakes[staker][validatorId].staked > 0;
        bool hasActiveCooldownForThisVal = $.userValidatorCooldowns[staker][validatorId].amount > 0;

        console2.log("PVL (Part 2 PRE-CHECK) - User:", staker);
        console2.log("PVL (Part 2 PRE-CHECK) - Val:", validatorId);
        console2.log("PVL (Part 2 PRE-CHECK) - HasActiveStake:", hasActiveStakeForThisVal);
        console2.log("PVL (Part 2 PRE-CHECK) - HasActiveCooldown:", hasActiveCooldownForThisVal);
        console2.log("PVL (Part 2 PRE-CHECK) - UserHasStakedMap:", $.userHasStakedWithValidator[staker][validatorId]);

        if (!hasActiveStakeForThisVal && !hasActiveCooldownForThisVal) {
            console2.log(
                "PVL (Part 2): User %s, Val %s - Conditions MET to remove from userValidators list (no active stake, no cooldown).",
                staker,
                validatorId
            );

            if ($.userHasStakedWithValidator[staker][validatorId]) {
                // Check if they are currently in the userValidators list (via this mapping)
                uint16[] storage userValidators_ = $.userValidators[staker];
                console2.log(
                    "PVL (Part 2): User %s, ValListLen BEFORE pop for val %s: %s",
                    staker,
                    validatorId,
                    userValidators_.length
                );

                bool removed = false;
                for (uint256 i = 0; i < userValidators_.length; i++) {
                    if (userValidators_[i] == validatorId) {
                        // Swap with last and pop
                        userValidators_[i] = userValidators_[userValidators_.length - 1];
                        userValidators_.pop();
                        removed = true;
                        console2.log(
                            "PVL (Part 2): User %s, ValListLen AFTER pop for val %s: %s",
                            staker,
                            validatorId,
                            userValidators_.length
                        );
                        break;
                    }
                }
                // Only set userHasStakedWithValidator to false if it was actually removed or if the list is now empty
                // for this validator
                // This mapping essentially tracks if the validatorId should be in $.userValidators[staker]
                if (removed) {
                    // Or if after potential pop, the validator is no longer findable.
                    $.userHasStakedWithValidator[staker][validatorId] = false;
                    console2.log(
                        "PVL (Part 2): Set userHasStakedWithValidator to FALSE for User %s, Val %s.",
                        staker,
                        validatorId
                    );
                } else {
                    console2.log(
                        "PVL (Part 2): Val %s not found in userValidators_ for User %s. userHasStakedWithValidator not changed.",
                        validatorId,
                        staker
                    );
                }
            } else {
                console2.log(
                    "PVL (Part 2): userHasStakedWithValidator is already FALSE for User %s, Val %s. Pop from userValidators skipped.",
                    staker,
                    validatorId
                );
            }
        } else {
            console2.log("PVL (Part 2) - val:", validatorId);
            console2.log("PVL (Part 2) - user:", staker);
            console2.log("PVL (Part 2) - HasActiveStake:", hasActiveStakeForThisVal);
            console2.log("PVL (Part 2) - HasActiveCooldown:", hasActiveCooldownForThisVal);
        }
    }

}
