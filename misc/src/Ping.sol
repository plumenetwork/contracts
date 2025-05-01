// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title Ping
 * @author Eugene Y. Q. Shen
 * @notice Users can ping this contract so that we have a block every 250 ms and
 *   VRF functions from Supra which update at the next block have lower latency.
 */
contract Ping {
    function ping() external {}
}
