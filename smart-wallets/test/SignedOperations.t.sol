// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { SmartWallet } from "../src/SmartWallet.sol";

import { AssetVault } from "../src/extensions/AssetVault.sol";
import { SignedOperations } from "../src/extensions/SignedOperations.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";

contract SignedOperationsTest is Test {

    SignedOperations signedOperations;
    ERC20Mock currencyToken;
    address owner;
    address executor;
    uint256 ownerPrivateKey;

    function setUp() public {
        ownerPrivateKey = 0xA11CE; // Replace with a valid private key
        owner = vm.addr(ownerPrivateKey);
        executor = address(0x123);

        vm.startPrank(owner);
        signedOperations = new SignedOperations();
        currencyToken = new ERC20Mock();
        vm.stopPrank();
    }

    function testRevertExpiredSignature() public {
        bytes32 nonce = keccak256("testnonce");
        bytes32 nonceDependency = bytes32(0);
        uint256 expiration = 1000; // Set a specific timestamp
        address[] memory targets = new address[](1);
        bytes[] memory calls = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        targets[0] = address(currencyToken);
        calls[0] = abi.encodeWithSignature("transfer(address,uint256)", executor, 100);
        values[0] = 0;

        bytes32 digest = _getDigest(targets, calls, values, nonce, nonceDependency, expiration);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        vm.warp(1001); // Set block.timestamp to after expiration
        vm.expectRevert(abi.encodeWithSelector(SignedOperations.ExpiredSignature.selector, nonce, expiration));
        signedOperations.executeSignedOperations(targets, calls, values, nonce, nonceDependency, expiration, v, r, s);
    }

    function testRevertInvalidNonce() public {
        bytes32 nonce = keccak256("usednonce");

        vm.prank(address(signedOperations));
        signedOperations.cancelSignedOperations(nonce);

        bytes32 nonceDependency = bytes32(0);
        uint256 expiration = block.timestamp + 1 days;
        address[] memory targets = new address[](1);
        bytes[] memory calls = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        targets[0] = address(currencyToken);
        calls[0] = abi.encodeWithSignature("transfer(address,uint256)", executor, 100);
        values[0] = 0;

        bytes32 digest = _getDigest(targets, calls, values, nonce, nonceDependency, expiration);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        vm.expectRevert(abi.encodeWithSelector(SignedOperations.InvalidNonce.selector, nonce));
        signedOperations.executeSignedOperations(targets, calls, values, nonce, nonceDependency, expiration, v, r, s);
    }

    function testCancelSignedOperations() public {
        bytes32 nonce = keccak256("testnonce");

        vm.prank(address(signedOperations));
        signedOperations.cancelSignedOperations(nonce);

        assertTrue(signedOperations.isNonceUsed(nonce));
    }

    function _getDigest(
        address[] memory targets,
        bytes[] memory calls,
        uint256[] memory values,
        bytes32 nonce,
        bytes32 nonceDependency,
        uint256 expiration
    ) internal view returns (bytes32) {
        bytes32 SIGNED_OPERATIONS_TYPEHASH = keccak256(
            "SignedOperations(address[] targets,bytes[] calls,uint256[] values,bytes32 nonce,bytes32 nonceDependency,uint256 expiration)"
        );

        bytes32 targetsHash = keccak256(abi.encode(targets));
        bytes32 callsHash = keccak256(abi.encode(calls));
        bytes32 valuesHash = keccak256(abi.encode(values));

        bytes32 structHash = keccak256(
            abi.encode(
                SIGNED_OPERATIONS_TYPEHASH, targetsHash, callsHash, valuesHash, nonce, nonceDependency, expiration
            )
        );

        bytes32 DOMAIN_SEPARATOR = _getDomainSeparator();

        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
    }

    function _getDomainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("Plume"),
                keccak256("1"),
                block.chainid,
                address(signedOperations)
            )
        );
    }

    //TODO: testExecuteSignedOperationsSuccess

}
