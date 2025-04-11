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

}
