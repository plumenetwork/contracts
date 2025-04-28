// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { PlumeStakingStorage } from "./lib/PlumeStakingStorage.sol";
import { OwnableInternal } from "@solidstate/access/ownable/Ownable.sol";
import { ISolidStateDiamondProxy, SolidStateDiamondProxy } from "@solidstate/proxy/diamond/SolidStateDiamondProxy.sol";

/**
 * @title PlumeStaking Diamond Proxy
 * @notice Main entry point for the Plume Staking Diamond, inheriting SolidStateDiamondProxy.
 */


contract PlumeStaking is SolidStateDiamondProxy {

    function initializePlume(
        address initialOwner, // Keep parameter for flexibility, though constructor sets deployer
        uint256 minStake,
        uint256 cooldown
    ) external virtual onlyOwner {
        // Although SolidStateDiamondProxy constructor sets owner, allow transferring if needed.
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        // Add an initialization check
        require(!$.initialized, "PlumeStaking: Already initialized");

        if (initialOwner != address(0) && initialOwner != owner()) {
            // Use the internal transfer function from Ownable/SafeOwnable
            // Note: SolidStateDiamondProxy inherits SafeOwnable -> Ownable -> OwnableInternal
            _transferOwnership(initialOwner);
        }

        $.minStakeAmount = minStake;
        $.cooldownInterval = cooldown;

        // Mark as initialized
        $.initialized = true;

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
