// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/**
 * @title Empty
 * @author Eugene Y. Q. Shen
 * @notice Empty contract that has nothing in it and does nothing
 * @dev This empty contract is used as the initial implementation contract
 *   when deploying new proxy contracts to ensure that the addresses all
 *   stay the same when using CREATE2 to deploy them on different chains.
 */
contract Empty {

    constructor() { }

}
