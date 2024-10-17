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

    function setUp() public {
        owner = address(this);
        executor = address(0x123);

        signedOperations = new SignedOperations();

        // Deploy a mock ERC20 token
        currencyToken = new ERC20Mock();
    }

    /*
    function testExecuteSignedOperationsSuccess() public {
        // Prepare test data
        bytes32 nonce = keccak256("testnonce");
        bytes32 nonceDependency = bytes32(0);
        uint256 expiration = block.timestamp + 1 days;
        address[] memory targets = new address[](1);
        bytes[] memory calls = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        // Simulate signature components (use ECDSA for real tests)
        uint8 v = 27;
        bytes32 r = bytes32(0);
        bytes32 s = bytes32(0);

        targets[0] = address(currencyToken);
        calls[0] = abi.encodeWithSignature("transfer(address,uint256)", executor, 100);
        values[0] = 0;

        // Execute signed operations
    signedOperations.executeSignedOperations(targets, calls, values, nonce, nonceDependency, expiration, v, r, s);

        // Check that nonce is marked as used
        assertTrue(signedOperations.isNonceUsed(nonce));
    }

    function testRevertExpiredSignature() public {
        // Prepare test data for expired signature
        bytes32 nonce = keccak256("testnonce");
        bytes32 nonceDependency = bytes32(0);
        uint256 expiration = block.timestamp - 1 days;
        address[] memory targets = new address[](1);
        bytes[] memory calls = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        uint8 v = 27;
        bytes32 r = bytes32(0);
        bytes32 s = bytes32(0);

        targets[0] = address(currencyToken);
        calls[0] = abi.encodeWithSignature("transfer(address,uint256)", executor, 100);
        values[0] = 0;

        vm.expectRevert(abi.encodeWithSelector(SignedOperations.ExpiredSignature.selector, nonce, expiration));
    signedOperations.executeSignedOperations(targets, calls, values, nonce, nonceDependency, expiration, v, r, s);
    }

    function testRevertInvalidNonce() public {
        // Set nonce to be already used
        bytes32 nonce = keccak256("usednonce");
        signedOperations.cancelSignedOperations(nonce);

        // Prepare test data
        bytes32 nonceDependency = bytes32(0);
        uint256 expiration = block.timestamp + 1 days;
        address[] memory targets = new address[](1);
        bytes[] memory calls = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        uint8 v = 27;
        bytes32 r = bytes32(0);
        bytes32 s = bytes32(0);

        targets[0] = address(currencyToken);
        calls[0] = abi.encodeWithSignature("transfer(address,uint256)", executor, 100);
        values[0] = 0;

        vm.expectRevert(abi.encodeWithSelector(SignedOperations.InvalidNonce.selector, nonce));
    signedOperations.executeSignedOperations(targets, calls, values, nonce, nonceDependency, expiration, v, r, s);
    }


    function testCancelSignedOperations() public {
        bytes32 nonce = keccak256("testnonce");

        // Cancel signed operations
        signedOperations.cancelSignedOperations(nonce);

        // Ensure that the nonce is marked as used
        assertTrue(signedOperations.isNonceUsed(nonce));
    }
    */

}
