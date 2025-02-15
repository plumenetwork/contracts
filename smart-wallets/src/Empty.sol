// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/**
 * @title Empty
 * @author Eugene Y. Q. Shen
 * @notice Empty contract that has nothing in it and does nothing
 * @dev This empty contract is used as the initial implementation contract
 *   when deploying new proxy contracts ensure that the addresses all
 *   stay the same when using CREATE2 to deploy them on different chains.
 */
contract Empty {

    /// @dev The empty contract must have some code in it to get 100% test coverage
    uint256 immutable value = 0;

    /// @notice Construct the Empty contract
    constructor() { }

}
