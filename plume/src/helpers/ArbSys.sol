// SPDX-License-Identifier: UNLICENSED

/**
 * This code was adapted from the OffchainLabs/nitro-contracts repository:
 * https://github.com/OffchainLabs/nitro-contracts.
 * Specifically, the ArbSys contract at commit 2ba206505edd15ad1e177392c454e89479959ca5:
 * https://github.com/OffchainLabs/nitro-contracts/blob/7396313311ab17cb30e2eef27cccf96f0a9e8f7f/src/precompiles/ArbSys.sol
 *
 */
pragma solidity >=0.4.21 <0.9.0;

/**
 * @title Precompiled contract that exists in every Arbitrum chain at address(100),
 * 0x0000000000000000000000000000000000000064. Exposes a variety of system-level functionality.
 */
interface ArbSys {

    /**
     * @notice Get Arbitrum block number (distinct from L1 block number; Arbitrum genesis block has block number 0)
     * @return block number as int
     */
    function arbBlockNumber() external view returns (uint256);

    /**
     * @notice Get Arbitrum block hash (reverts unless currentBlockNum-256 <= arbBlockNum < currentBlockNum)
     * @return block hash
     */
    function arbBlockHash(
        uint256 arbBlockNum
    ) external view returns (bytes32);

}