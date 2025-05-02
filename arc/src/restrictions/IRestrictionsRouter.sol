// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title IRestrictionsRouter Interface
 * @notice Interface for the central router that manages restriction module addresses.
 */
interface IRestrictionsRouter {

    /**
     * @notice Retrieves the address of a registered global module implementation.
     * @dev Returns address(0) if the typeId is not registered or is not global.
     * @param typeId The unique identifier for the module type (e.g., keccak256("GLOBAL_SANCTIONS")).
     * @return address The address of the global module implementation, or address(0).
     */
    function getGlobalModuleAddress(
        bytes32 typeId
    ) external view returns (address);

    // Potential future additions:
    // function getModuleInfo(bytes32 typeId) external view returns (bool isGlobal, address globalImplementation);

}
