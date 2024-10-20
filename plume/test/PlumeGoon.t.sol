// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {PlumeGoon} from "../src/NFTs/PlumeGoon.sol";
import {Merkle} from "../lib/murky/src/Merkle.sol";

contract PlumeGoonTest is Test {
    PlumeGoon public plumeGoon;
    Merkle public merkle;
    bytes32 public merkleRoot;

    address[] public users = [
        address(0x123),
        address(0x456),
        address(0x789),
        address(0xabc),
        address(0xdef),
        address(0x12a),
        address(0x12b),
        address(0x12c)
    ];

    uint256[] public tokenIds = [1, 2, 3, 4, 5, 6, 7, 8];
    string[] public tokenURIs = [
        "https://example.com/token/1",
        "https://example.com/token/2",
        "https://example.com/token/3",
        "https://example.com/token/4",
        "https://example.com/token/5",
        "https://example.com/token/6",
        "https://example.com/token/7",
        "https://example.com/token/8"
    ];

    bytes32[] public leafNodes;
    bytes32[] public validProofUser1;
    bytes32[] public invalidProofUser1;

    function setUp() public {
        merkle = new Merkle();

        for (uint256 i = 0; i < users.length; i++) {
            leafNodes.push(keccak256(abi.encodePacked(users[i], tokenIds[i], tokenURIs[i])));
        }

        merkleRoot = merkle.getRoot(leafNodes);

        plumeGoon = new PlumeGoon();
        plumeGoon.initialize(
            address(this),
            "PlumeGoon", 
            "PGN", 
            merkleRoot, 
            address(this)
        );

        validProofUser1 = merkle.getProof(leafNodes, 0);

        invalidProofUser1 = [
            bytes32(0xabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdef1234)
        ];
    }

    function testCorrectMint() public {
        vm.startPrank(users[0]);

        plumeGoon.mintPlumeGoonNFT(tokenIds[0], tokenURIs[0], validProofUser1);

        assertEq(plumeGoon.ownerOf(tokenIds[0]), users[0]);

        vm.stopPrank();
    }

    function testInvalidProof() public {
        vm.startPrank(users[0]);

        vm.expectRevert(abi.encodeWithSignature("InvalidMerkleProof()"));
        plumeGoon.mintPlumeGoonNFT(tokenIds[1], tokenURIs[1], invalidProofUser1);

        vm.stopPrank();
    }

    function testInvalidUser() public {
        vm.startPrank(users[1]);

        vm.expectRevert(abi.encodeWithSignature("InvalidMerkleProof()"));
        plumeGoon.mintPlumeGoonNFT(tokenIds[1], tokenURIs[1], validProofUser1);

        vm.stopPrank();
    }
}
