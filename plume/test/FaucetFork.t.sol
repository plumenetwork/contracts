// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Faucet } from "../src/Faucet.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

contract FaucetForkTest is Test {

    // Contract instances
    Faucet public faucet;

    // Addresses
    address public constant FAUCET_ADDRESS = 0xEBa7Ee4c64a91B5dDb4631a66E541299f978fdd0;
    address public constant ETH_ADDRESS = address(1);

    // Test accounts
    address public owner;
    address public user1;
    address public user2;

    // Owner's private key (from environment variable)
    uint256 private ownerPrivateKey;
    bool private hasOwnerKey;

    // Constants - keeping both to handle the discrepancy
    uint256 public constant ETH_BASE_DRIP_AMOUNT = 10 ether; // Used for getDripAmount("PLUME")
    uint256 public constant ETH_FLIGHT_DRIP_AMOUNT = 10 ether; // Used for getDripAmount("PLUME", flightClass)
    uint256 public constant TOKEN_DRIP_AMOUNT = 1e9; // $1000 USDT (6 decimals)

    // Store supported tokens
    string[] public supportedTokens;

    function setUp() public {
        // Fork mainnet
        vm.createSelectFork(vm.envString("PLUME_DEVNET_RPC_URL"));

        // Create test accounts
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Set up ETH balances
        vm.deal(user1, 1 ether);
        vm.deal(user2, 1 ether);

        // Get faucet instance
        faucet = Faucet(payable(FAUCET_ADDRESS));

        // Get the actual owner
        owner = faucet.getOwner();
        vm.label(owner, "actual_owner");

        // Try to get the owner's private key from environment variable
        try vm.envUint("FAUCET_OWNER_PRIVATE_KEY") returns (uint256 key) {
            ownerPrivateKey = key;
            hasOwnerKey = true;

            // Verify the key matches the actual owner
            address derivedAddress = vm.addr(ownerPrivateKey);
            if (derivedAddress != owner) {
                console2.log("Warning: Private key does not match contract owner");
                console2.log("Derived address:", derivedAddress);
                console2.log("Contract owner:", owner);
                hasOwnerKey = false;
            } else {
                console2.log("Found valid owner private key");
            }
        } catch {
            console2.log("No owner private key provided. Some tests will be skipped.");
            hasOwnerKey = false;
        }

        // Initialize supported tokens
        supportedTokens.push("PLUME");
        // Add any other supported tokens if known
    }

    // Helper function to sign messages
    function signMessage(
        address recipient,
        string memory token,
        uint256 flightClass,
        bytes32 salt
    ) internal view returns (bytes memory) {
        bytes32 message = keccak256(abi.encodePacked(recipient, token, flightClass, salt));
        bytes32 ethSignedMessage = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", message));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedMessage);
        return abi.encodePacked(r, s, v);
    }

    // Test basic initialization
    function test_Initialization() public {
        assertEq(faucet.getTokenAddress("PLUME"), ETH_ADDRESS);
        assertEq(faucet.getDripAmount("PLUME"), ETH_BASE_DRIP_AMOUNT);
        assertEq(faucet.getOwner(), owner);
    }

    // Test different flight classes
    function test_FlightClassMultipliers() public {
        assertEq(faucet.getDripAmount("PLUME", 1), ETH_FLIGHT_DRIP_AMOUNT, "Wrong drip amount for flight class 1");
    }

    // Test receiving ETH directly
    function test_ReceiveEth() public {
        uint256 initialBalance = address(faucet).balance;
        uint256 sendAmount = 1 ether;

        (bool success,) = address(faucet).call{ value: sendAmount }("");
        assertTrue(success, "ETH transfer failed");

        assertEq(address(faucet).balance, initialBalance + sendAmount);
    }

    // Skip signature-based tests since we don't have the actual owner's private key in a fork test
    // Instead, test what we can verify without needing signatures

    // Test that the contract returns correct view function results
    function test_ViewFunctions() public {
        // Test token address
        assertEq(faucet.getTokenAddress("PLUME"), ETH_ADDRESS);

        // Test drip amounts for different flight classes
        // Class 1 (Economy): 1x (multiplier = 100, normalized by /100)
        assertEq(faucet.getDripAmount("PLUME", 1), ETH_FLIGHT_DRIP_AMOUNT);

        // Class 2 (Plus): 1.1x (multiplier = 110, normalized by /100)
        assertEq(faucet.getDripAmount("PLUME", 2), (ETH_FLIGHT_DRIP_AMOUNT * 110) / 100);

        // Class 3 (Premium): 1.25x (multiplier = 125, normalized by /100)
        assertEq(faucet.getDripAmount("PLUME", 3), (ETH_FLIGHT_DRIP_AMOUNT * 125) / 100);

        // Class 4 (Business): 2x (multiplier = 200, normalized by /100)
        assertEq(faucet.getDripAmount("PLUME", 4), (ETH_FLIGHT_DRIP_AMOUNT * 200) / 100);

        // Class 5 (First): 3x (multiplier = 300, normalized by /100)
        assertEq(faucet.getDripAmount("PLUME", 5), (ETH_FLIGHT_DRIP_AMOUNT * 300) / 100);

        // Class 6 (Private): 5x (multiplier = 500, normalized by /100)
        assertEq(faucet.getDripAmount("PLUME", 6), (ETH_FLIGHT_DRIP_AMOUNT * 500) / 100);
    }

    // Test invalid flight class using view function
    function test_RevertWhen_InvalidFlightClassView() public {
        vm.expectRevert(abi.encodeWithSelector(Faucet.InvalidFlightClass.selector, 7));
        faucet.getDripAmount("PLUME", 7); // This should revert with InvalidFlightClass
    }

    // Test invalid token in view function
    function test_RevertWhen_InvalidTokenView() public {
        vm.expectRevert(abi.encodeWithSelector(Faucet.InvalidToken.selector));
        faucet.getDripAmount("NONEXISTENT", 1);
    }

    // Test nonce checking
    function test_NonceChecking() public {
        bytes32 randomNonce = bytes32(uint256(123_456_789));

        // Should return false for a random nonce
        assertFalse(faucet.isNonceUsed(randomNonce));
    }

    // Test unauthorized access to admin functions
    function test_RevertWhen_UnauthorizedAccess() public {
        // Try to call owner-only functions
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Faucet.Unauthorized.selector, user1, owner));
        faucet.setOwner(user2);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Faucet.Unauthorized.selector, user1, owner));
        faucet.setDripAmount("PLUME", 0.5 ether);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Faucet.Unauthorized.selector, user1, owner));
        faucet.addToken("TEST", address(0x123), 1 ether);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Faucet.Unauthorized.selector, user1, owner));
        faucet.withdrawToken("PLUME", 1 ether, payable(user1));
    }

    // Test contract balances
    function test_ContractBalances() public {
        // Verify the contract has ETH balance
        assertTrue(address(faucet).balance > 0, "Faucet should have ETH balance");

        // Check for other supported tokens if any are known
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            address tokenAddress = faucet.getTokenAddress(supportedTokens[i]);
            if (tokenAddress != ETH_ADDRESS && tokenAddress != address(0)) {
                IERC20Metadata token = IERC20Metadata(tokenAddress);
                uint256 balance = token.balanceOf(address(faucet));
                console2.log("Token balance for", supportedTokens[i], ":", balance);
            }
        }
    }

    // Test getTokenAddress with invalid token
    function test_GetTokenAddress_InvalidToken() public {
        assertEq(faucet.getTokenAddress("NONEXISTENT"), address(0));
    }

    // --- OWNER/SIGNATURE TESTS BELOW ---
    // These tests will only run if the owner private key is provided

    // Test getting tokens from faucet using signature
    function test_GetToken() public {
        vm.skip(!hasOwnerKey); // Skip if owner private key not available

        // Get initial balances
        uint256 initialEthBalance = user1.balance;

        // Prepare signature for ETH
        bytes32 salt1 = bytes32(uint256(100));
        bytes memory signature1 = signMessage(
            user1,
            "PLUME",
            1, // Economy class
            salt1
        );

        // Get ETH from faucet
        vm.prank(user1);
        faucet.getToken("PLUME", 1, salt1, signature1);

        // Verify ETH was received
        assertEq(user1.balance - initialEthBalance, ETH_FLIGHT_DRIP_AMOUNT);

        // Test for other tokens if available
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            string memory tokenName = supportedTokens[i];
            address tokenAddress = faucet.getTokenAddress(tokenName);

            if (tokenAddress != ETH_ADDRESS && tokenAddress != address(0)) {
                IERC20Metadata token = IERC20Metadata(tokenAddress);

                uint256 initialTokenBalance = token.balanceOf(user2);

                bytes32 salt2 = bytes32(uint256(200 + i));
                bytes memory signature2 = signMessage(user2, tokenName, 1, salt2);

                vm.prank(user2);
                faucet.getToken(tokenName, 1, salt2, signature2);

                uint256 expectedAmount = faucet.getDripAmount(tokenName, 1);
                assertEq(token.balanceOf(user2) - initialTokenBalance, expectedAmount);
            }
        }
    }

    // Test nonce reuse prevention
    function test_RevertWhen_NonceReused() public {
        vm.skip(!hasOwnerKey); // Skip if owner private key not available

        bytes32 salt = bytes32(uint256(300));
        bytes memory signature = signMessage(user1, "PLUME", 1, salt);

        // First call should succeed
        vm.prank(user1);
        faucet.getToken("PLUME", 1, salt, signature);

        // Second call with same nonce should fail
        vm.expectRevert(abi.encodeWithSelector(Faucet.InvalidNonce.selector));
        vm.prank(user1);
        faucet.getToken("PLUME", 1, salt, signature);
    }

    // Test different flight classes with real transfers
    function test_RealFlightClassMultipliers() public {
        vm.skip(!hasOwnerKey); // Skip if owner private key not available

        // Test each flight class
        uint256[] memory flightClasses = new uint256[](6);
        flightClasses[0] = 1; // Economy - 1x
        flightClasses[1] = 2; // Plus - 1.1x
        flightClasses[2] = 3; // Premium - 1.25x
        flightClasses[3] = 4; // Business - 2x
        flightClasses[4] = 5; // First - 3x
        flightClasses[5] = 6; // Private - 5x

        for (uint256 i = 0; i < flightClasses.length; i++) {
            uint256 flightClass = flightClasses[i];

            // Create a unique user for each flight class
            address user = makeAddr(string.concat("user_class_", vm.toString(flightClass)));
            vm.deal(user, 1 ether);

            uint256 initialBalance = user.balance;

            bytes32 salt = bytes32(uint256(400 + i));
            bytes memory signature = signMessage(user, "PLUME", flightClass, salt);

            vm.prank(user);
            faucet.getToken("PLUME", flightClass, salt, signature);

            uint256 expectedAmount = faucet.getDripAmount("PLUME", flightClass);
            assertEq(
                user.balance - initialBalance,
                expectedAmount,
                string.concat("Wrong amount for flight class ", vm.toString(flightClass))
            );
        }
    }

    // Test admin functions (requires owner private key)
    function test_AdminFunctions() public {
        vm.skip(!hasOwnerKey); // Skip if owner private key not available

        // Store original values to restore them later
        address originalOwner = faucet.getOwner();
        uint256 originalDripAmount = faucet.getDripAmount("PLUME");

        // 1. Test setting drip amount
        uint256 newDripAmount = 0.0005 ether;
        vm.prank(owner);
        faucet.setDripAmount("PLUME", newDripAmount);

        assertEq(faucet.getDripAmount("PLUME"), newDripAmount, "Failed to set new drip amount");

        // 2. Test adding a new token
        address mockTokenAddress = makeAddr("mockToken");
        uint256 mockTokenAmount = 5 * 10 ** 18;

        vm.prank(owner);
        faucet.addToken("MOCK_TOKEN", mockTokenAddress, mockTokenAmount);

        assertEq(faucet.getTokenAddress("MOCK_TOKEN"), mockTokenAddress, "Failed to add new token");
        assertEq(faucet.getDripAmount("MOCK_TOKEN"), mockTokenAmount, "Failed to set token drip amount");

        // 3. Test changing ownership temporarily
        vm.prank(owner);
        faucet.setOwner(user1);

        assertEq(faucet.getOwner(), user1, "Failed to change owner");

        // 4. Test withdrawing ETH (if there's enough balance)
        if (address(faucet).balance >= 0.01 ether) {
            uint256 initialBalance = user1.balance;
            uint256 withdrawAmount = 0.01 ether;

            vm.prank(user1); // Use the new owner
            faucet.withdrawToken("PLUME", withdrawAmount, payable(user1));

            assertEq(user1.balance - initialBalance, withdrawAmount, "Failed to withdraw ETH");
        }

        // Restore original values
        vm.prank(user1); // Current owner is user1
        faucet.setOwner(originalOwner);

        vm.prank(originalOwner);
        faucet.setDripAmount("PLUME", originalDripAmount);

        // Remove the test token
        vm.prank(originalOwner);
        faucet.addToken("MOCK_TOKEN", address(0), 0); // Set to 0 to effectively disable it
    }

    // Test invalid signature
    function test_RevertWhen_InvalidSignature() public {
        vm.skip(!hasOwnerKey); // Skip if owner private key not available

        // Use a different private key
        uint256 attackerPrivateKey = uint256(keccak256(abi.encodePacked("attacker")));
        bytes32 salt = bytes32(uint256(500));

        // Fix: Explicitly convert 1 to uint256
        bytes32 message = keccak256(abi.encodePacked(user1, "PLUME", uint256(1), salt));
        bytes32 ethSignedMessage = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", message));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attackerPrivateKey, ethSignedMessage);
        bytes memory invalidSignature = abi.encodePacked(r, s, v);

        vm.expectRevert(abi.encodeWithSelector(Faucet.InvalidSignature.selector));
        vm.prank(user1);
        faucet.getToken("PLUME", 1, salt, invalidSignature);
    }

}
