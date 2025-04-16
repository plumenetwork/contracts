// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { PlumeStakingStorage } from "./lib/PlumeStakingStorage.sol";
import { OwnableInternal } from "@solidstate/access/ownable/Ownable.sol";
import { ISolidStateDiamond, SolidStateDiamond } from "@solidstate/proxy/diamond/SolidStateDiamond.sol";

/**
 * @title PlumeStaking Diamond Proxy
 * @notice Main entry point for the Plume Staking Diamond, inheriting SolidStateDiamond.
 */
contract PlumeStaking is SolidStateDiamond {

    // Note: SolidStateDiamond's constructor sets msg.sender as the owner.

    /**
     * @notice Custom initializer for Plume-specific settings.
     * @dev Can only be called once by the owner.
     * @param initialOwner The address to grant initial ownership to (can be address(0) to keep deployer).
     * @param minStake Initial minimum stake amount.
     * @param cooldown Initial cooldown period.
     */
    function initializePlume(
        address initialOwner, // Keep parameter for flexibility, though constructor sets deployer
        uint256 minStake,
        uint256 cooldown
    ) external virtual onlyOwner {
        // Although SolidStateDiamond constructor sets owner, allow transferring if needed.
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        // Add an initialization check
        require(!$.initialized, "PlumeStaking: Already initialized");

        if (initialOwner != address(0) && initialOwner != owner()) {
            // Use the internal transfer function from Ownable/SafeOwnable
            // Note: SolidStateDiamond inherits SafeOwnable -> Ownable -> OwnableInternal
            _transferOwnership(initialOwner);
        }

        $.minStakeAmount = minStake;
        $.cooldownInterval = cooldown;

        // Mark as initialized
        $.initialized = true;
    }

    // --- View Functions ---

    /**
     * @notice Checks if the Plume-specific initialization has been performed.
     */
    function isInitialized() external view returns (bool) {
        return PlumeStakingStorage.layout().initialized;
    }

}
