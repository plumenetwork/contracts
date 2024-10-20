// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

library PlumeGoonStorage {
    struct Storage {
        address admin;
        bytes32 plumeGoonMerkleRoot;
        mapping(address => bool) hasMinted; 
    }

    function getStorage() internal pure returns (Storage storage ps) {
        bytes32 position = keccak256("plumegoon.storage");
        assembly {
            ps.slot := position
        }
    }
}
