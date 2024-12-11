// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title LoadTest
 * @author Eugene Y. Q. Shen
 * @notice Contract to load test Plume infra
 */
contract LoadTest {

    uint256 j = 1;
    mapping(bytes32 => uint256) public storageMap;

    /**
     * @notice Execute a large number of simple operations
     * @param iterations Number of iterations to execute
     */
    function testCompute(
        uint256 iterations
    ) external {
        for (uint256 i = 0; i < iterations; i++) {
            if (j > 1e16) {
                j = 1;
            } else {
                j *= 2;
            }
        }
    }

    /**
     * @notice Spend a large amount of gas on storage
     * @param iterations Number of iterations to execute
     */
    function testStorage(
        uint256 iterations
    ) external {
        for (uint256 i = 0; i < iterations; i++) {
            bytes32 key = keccak256(abi.encodePacked(msg.sender, block.timestamp, i));
            storageMap[key] = i;
        }
    }

}
