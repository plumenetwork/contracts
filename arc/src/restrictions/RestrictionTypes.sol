// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title RestrictionTypes
 * @author qubitcrypto
 * @notice Library defining restriction type constants used across the system
 */
library RestrictionTypes {
    // -------------- Constants for Module Type IDs --------------
    bytes32 public constant TRANSFER_RESTRICTION_TYPE = keccak256("TRANSFER_RESTRICTION");
    bytes32 public constant YIELD_RESTRICTION_TYPE = keccak256("YIELD_RESTRICTION");
    bytes32 public constant GLOBAL_SANCTIONS_TYPE = keccak256("GLOBAL_SANCTIONS");
}