// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { InvalidAmount, InvalidMaxCommissionRate, CooldownTooShortForSlashVote } from "./lib/PlumeErrors.sol";
import { PlumeStakingStorage } from "./lib/PlumeStakingStorage.sol";
import { OwnableInternal } from "@solidstate/access/ownable/OwnableInternal.sol";
import { ISolidStateDiamond, SolidStateDiamond } from "@solidstate/proxy/diamond/SolidStateDiamond.sol";

/*
 * ╔═══════════════════════════════════════════════════════════════════════════════╗
 * ║                                                                               ║
 * ║                          ✦ ✦ ✦ ✦ ✦ ✦ ✦ ✦ ✦ ✦ ✦                                ║
 * ║                                                                               ║
 * ║                   I N  L O V I N G   M E M O R Y   O F                        ║
 * ║                                                                               ║
 * ║                      ╭─────────────────────────────╮                          ║
 * ║                      │                             │                          ║
 * ║                      │        E U G E N E          │                          ║
 * ║                      │          S H E N            │                          ║
 * ║                      │                             │                          ║
 * ║                      ╰─────────────────────────────╯                          ║
 * ║                                                                               ║
 * ║                              ◆ ◇ ◆ ◇ ◆ ◇ ◆                                    ║
 * ║                                                                               ║
 * ║        ┌───────────────────────────────────────────────────────────┐          ║
 * ║        │                                                           │          ║
 * ║        │  "Every second spent developing this contract is          │          ║
 * ║        │               dedicated to Eugene Shen"                   │          ║
 * ║        │                                                           │          ║
 * ║        └───────────────────────────────────────────────────────────┘          ║
 * ║                                                                               ║
 * ║                      ∞ Forever in our hearts and code ∞                       ║
 * ║                                                                               ║
 * ║                          ✦ ✦ ✦ ✦ ✦ ✦ ✦ ✦ ✦ ✦ ✦                                ║
 * ║                                                                               ║
 * ╚═══════════════════════════════════════════════════════════════════════════════╝
 */

/**
 * @title PlumeStaking Diamond Proxy
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Main entry point for the Plume Staking Diamond, inheriting SolidStateDiamond.
 */
contract PlumeStaking is SolidStateDiamond {

    function initializePlume(
        address initialOwner, // Keep parameter for flexibility, though constructor sets deployer
        uint256 minStake,
        uint256 cooldown,
        uint256 maxSlashVoteDuration,
        uint256 maxValidatorCommission
    ) external virtual onlyOwner {
        // Although SolidStateDiamond constructor sets owner, allow transferring if needed.
        PlumeStakingStorage.Layout storage $ = PlumeStakingStorage.layout();

        // Add an initialization check
        require(!$.initialized, "PlumeStaking: Already initialized");

        // Add check for minStake
        if (minStake == 0) {
            revert InvalidAmount(minStake);
        }

        // --- NEW VALIDATION ---
        if (cooldown == 0) {
            revert InvalidAmount(cooldown);
        }
        if (maxSlashVoteDuration == 0) {
            revert InvalidAmount(maxSlashVoteDuration);
        }
        if (cooldown <= maxSlashVoteDuration) {
            revert CooldownTooShortForSlashVote(cooldown, maxSlashVoteDuration);
        }
        if (maxValidatorCommission > PlumeStakingStorage.REWARD_PRECISION / 2) { // Max 50%
            revert InvalidMaxCommissionRate(maxValidatorCommission, PlumeStakingStorage.REWARD_PRECISION / 2);
        }
        // --- END NEW VALIDATION ---

        if (initialOwner != address(0) && initialOwner != owner()) {
            // Use the internal transfer function from Ownable/SafeOwnable
            // Note: SolidStateDiamond inherits SafeOwnable -> Ownable -> OwnableInternal
            _transferOwnership(initialOwner);
        }

        $.minStakeAmount = minStake;
        $.cooldownInterval = cooldown;
        $.maxSlashVoteDurationInSeconds = maxSlashVoteDuration;
        $.maxAllowedValidatorCommission = maxValidatorCommission;
        $.maxCommissionCheckpoints = 500; // Set a sensible default limit
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
