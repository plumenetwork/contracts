// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Faucet } from "../src/Faucet.sol";
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

    // Constants
    uint256 public constant ETH_BASE_DRIP_AMOUNT = 0.001 ether; // Used for getDripAmount("PLUME")
    uint256 public constant ETH_FLIGHT_DRIP_AMOUNT = 0.00001 ether; // Used for getDripAmount("PLUME", flightClass)
    uint256 public constant TOKEN_DRIP_AMOUNT = 1e9; // $1000 USDT (6 decimals)

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
    }

    // Test basic initialization
    function test_Initialization() public {
        assertEq(faucet.getTokenAddress("PLUME"), ETH_ADDRESS);
        assertEq(faucet.getDripAmount("PLUME"), ETH_BASE_DRIP_AMOUNT);
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

        // Verify the discrepancy between base and flight class 1 drip amounts
        assertEq(faucet.getDripAmount("PLUME"), ETH_BASE_DRIP_AMOUNT);
        assertEq(faucet.getDripAmount("PLUME", 1), ETH_FLIGHT_DRIP_AMOUNT);

        // Test drip amounts for different flight classes
        // Class 1 (Economy): 1x
        assertEq(faucet.getDripAmount("PLUME", 1), ETH_FLIGHT_DRIP_AMOUNT);

        // Class 2 (Plus): 1.1x
        assertEq(faucet.getDripAmount("PLUME", 2), (ETH_FLIGHT_DRIP_AMOUNT * 110) / 100);

        // Class 3 (Premium): 1.25x
        assertEq(faucet.getDripAmount("PLUME", 3), (ETH_FLIGHT_DRIP_AMOUNT * 125) / 100);

        // Class 4 (Business): 2x
        assertEq(faucet.getDripAmount("PLUME", 4), (ETH_FLIGHT_DRIP_AMOUNT * 200) / 100);

        // Class 5 (First): 3x
        assertEq(faucet.getDripAmount("PLUME", 5), (ETH_FLIGHT_DRIP_AMOUNT * 300) / 100);

        // Class 6 (Private): 5x
        assertEq(faucet.getDripAmount("PLUME", 6), (ETH_FLIGHT_DRIP_AMOUNT * 500) / 100);
    }

    // Test invalid flight class using view function
    function test_RevertWhen_InvalidFlightClassView() public {
        vm.expectRevert(abi.encodeWithSelector(Faucet.InvalidFlightClass.selector, 7));
        faucet.getDripAmount("PLUME", 7); // This should revert with InvalidFlightClass
    }

}
