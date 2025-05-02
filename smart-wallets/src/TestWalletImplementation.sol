// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title TestWalletImplementation
 * @author Eugene Y. Q. Shen
 * @notice Sample contract to test upgrading the user wallet implementation
 */
contract TestWalletImplementation {

    /// @notice Value to be set by the user
    uint256 public value;

    /**
     * @notice Set the value
     * @param value_ Value to be set
     */
    function setValue(
        uint256 value_
    ) public {
        value = value_;
    }

}
