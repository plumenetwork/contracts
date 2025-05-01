// test/RaffleMigrationTest.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../src/spin/Raffle.sol";
import "forge-std/Test.sol";
import {ADMIN, USER, USER2, USER3, SUPRA_ORACLE, DEPOSIT_CONTRACT, SUPRA_OWNER, ARB_SYS_ADDRESS, PlumeTestBase, SpinStub} from "./TestUtils.sol";

contract RaffleMigrationTests is PlumeTestBase {
    Raffle public raffle;
    SpinStub public spinStub;
    
    function setUp() public {
        // Set up fork and ArbSys mock
        setupFork();
        setupArbSys();
        
        // Deploy SpinStub and Raffle
        spinStub = new SpinStub();
        raffle = new Raffle();
        
        // Whitelist raffle contract
        whitelistContract(ADMIN, address(raffle));
        
        // Initialize raffle contract
        vm.prank(ADMIN);
        raffle.initialize(address(spinStub), SUPRA_ORACLE);
        
        // Create test prize
        vm.prank(ADMIN);
        raffle.addPrize("Migration Test", "A prize for migration testing", 100);
    }
    
    function testMigrateTickets() public {
        // Create arrays for migration
        address[] memory users = new address[](3);
        users[0] = USER;
        users[1] = USER2;
        users[2] = USER3;
        
        uint256[] memory tickets = new uint256[](3);
        tickets[0] = 5;  // USER: 5 tickets
        tickets[1] = 3;  // USER2: 3 tickets
        tickets[2] = 2;  // USER3: 2 tickets
        
        // Migrate tickets
        vm.prank(ADMIN);
        raffle.migrateTickets(1, users, tickets);
        
        // Verify total tickets
        assertEq(raffle.totalTickets(1), 10);
        
        // Verify unique users count
        uint256 uniqueUsers;
        (,,,,,,uniqueUsers, ) = raffle.getPrizeDetails(1);
        assertEq(uniqueUsers, 3);
        
        // Test getWinner to verify ranges are properly set
        vm.recordLogs();
        vm.prank(ADMIN);
        raffle.requestWinner(1);
        
        // Extract the request ID from logs
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 requestId = 0;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("WinnerRequested(uint256,uint256)")) {
                requestId = uint256(logs[i].topics[2]);
                break;
            }
        }
        require(requestId != 0, "Request ID not found in logs");
        
        uint256[] memory rng = new uint256[](1);
        
        // Test USER winning (ticket in range 1-5)
        rng[0] = 3; // Will result in ticket #4
        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(requestId, rng);

        vm.prank(ADMIN);
        raffle.setWinner(1);

        assertEq(raffle.getWinner(1), USER);
    }

    // New test for multiple migrations
    function testMultipleMigrations() public {
        // First migration
        address[] memory users1 = new address[](2);
        users1[0] = USER;
        users1[1] = USER2;
        
        uint256[] memory tickets1 = new uint256[](2);
        tickets1[0] = 5;  // USER: 5 tickets
        tickets1[1] = 3;  // USER2: 3 tickets
        
        vm.prank(ADMIN);
        raffle.migrateTickets(1, users1, tickets1);
        
        // Verify first migration
        assertEq(raffle.totalTickets(1), 8);
        
        // Second migration
        address[] memory users2 = new address[](2);
        users2[0] = USER3;
        users2[1] = USER;  // USER appears in both migrations
        
        uint256[] memory tickets2 = new uint256[](2);
        tickets2[0] = 4;  // USER3: 4 tickets
        tickets2[1] = 2;  // USER: 2 more tickets
        
        vm.prank(ADMIN);
        raffle.migrateTickets(1, users2, tickets2);
        
        // Verify total after second migration
        assertEq(raffle.totalTickets(1), 14);  // 8 + 6
        
        // Verify unique users (should be 3 since USER appears twice)
        uint256 uniqueUsers;
        (,,,,,,uniqueUsers, ) = raffle.getPrizeDetails(1);
        assertEq(uniqueUsers, 3);
    }
    
    function testMigrateTicketsWithZeroValues() public {
        // Create arrays with some zero values
        address[] memory users = new address[](4);
        users[0] = USER;
        users[1] = USER2;
        users[2] = address(0); // Zero address
        users[3] = USER3;
        
        uint256[] memory tickets = new uint256[](4);
        tickets[0] = 5;  // USER: 5 tickets
        tickets[1] = 0;  // USER2: 0 tickets (should be skipped)
        tickets[2] = 3;  // Zero address: 3 tickets
        tickets[3] = 2;  // USER3: 2 tickets
        
        // Migrate tickets
        vm.prank(ADMIN);
        raffle.migrateTickets(1, users, tickets);
        
        // Verify total tickets (USER2 should be skipped)
        assertEq(raffle.totalTickets(1), 10);
        
        // Verify unique users (USER2 should not be counted)
        uint256 uniqueUsers;
        (,,,,,,uniqueUsers, ) = raffle.getPrizeDetails(1);
        assertEq(uniqueUsers, 3);
    }
    
    function testMigrateTicketsArrayLengthMismatchReverts() public {
        address[] memory users = new address[](2);
        users[0] = USER;
        users[1] = USER2;
        
        uint256[] memory tickets = new uint256[](3); // Different length
        tickets[0] = 1;
        tickets[1] = 2;
        tickets[2] = 3;
        
        vm.prank(ADMIN);
        vm.expectRevert("Array length mismatch");
        raffle.migrateTickets(1, users, tickets);
    }
    
    function testMigrateTicketsInactivePrizeReverts() public {
        // Remove prize
        vm.prank(ADMIN);
        raffle.removePrize(1);
        
        address[] memory users = new address[](1);
        users[0] = USER;
        uint256[] memory tickets = new uint256[](1);
        tickets[0] = 1;
        
        vm.prank(ADMIN);
        vm.expectRevert("Prize not available");
        raffle.migrateTickets(1, users, tickets);
    }
    
    function testMigrateTicketsOnlyAdmin() public {
        address[] memory users = new address[](1);
        users[0] = USER;
        uint256[] memory tickets = new uint256[](1);
        tickets[0] = 1;
        
        vm.prank(USER); // Not admin
        vm.expectRevert();
        raffle.migrateTickets(1, users, tickets);
    }
}