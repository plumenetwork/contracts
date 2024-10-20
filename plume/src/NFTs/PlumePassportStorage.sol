// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

library PlumePassportStorage {
    struct Storage {
        address admin;
        uint256[] tokenIds;
        string[] tokenURIs;
        mapping(address => bool) hasMinted;
        bytes32 plumePassportMerkleRoot;
    }

    function getStorage() internal pure returns (Storage storage ps) {
        bytes32 position = keccak256("plumepassport.storage");
        assembly {
            ps.slot := position
        }
    }
}
