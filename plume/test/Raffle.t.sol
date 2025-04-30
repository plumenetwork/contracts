// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../src/spin/Raffle.sol";
import "forge-std/Test.sol"; 
import {ADMIN, USER, USER2, SUPRA_ORACLE, DEPOSIT_CONTRACT, PlumeTestBase, SUPRA_OWNER, ARB_SYS_ADDRESS, ArbSysMock, SpinStub} from "./TestUtils.sol";

// --------------------------------------
// Raffle flow tests
// --------------------------------------
contract RaffleFlowTest is PlumeTestBase {
    Raffle public raffle;
    SpinStub public spinStub;

    function setUp() public {
        // Set up Arbitrum mock and fork
        setupFork();
        setupArbSys();

        // Deploy spin stub and raffle contracts
        spinStub = new SpinStub();
        raffle = new Raffle();
        
        // Whitelist raffle contract with Supra Oracle
        whitelistContract(ADMIN, address(raffle));

        // Initialize raffle with spinStub and SUPRA_ORACLE
        vm.prank(ADMIN);
        raffle.initialize(address(spinStub), SUPRA_ORACLE);
    }

    // Happy path test
    function testAddAndGetPrizeDetails() public {
        vm.prank(ADMIN);
        raffle.addPrize("Gold", "Shiny", 0);
        (string memory n, string memory d, uint256 t, , address w, , ) = raffle
            .getPrizeDetails(1);
        assertEq(n, "Gold");
        assertEq(d, "Shiny");
        assertEq(t, 0);
        assertEq(w, address(0));
    }

    function testSpendRaffleSuccess() public {
        vm.prank(ADMIN);
        raffle.addPrize("A", "A", 0);
        spinStub.setBalance(USER, 10);
        vm.prank(USER);
        raffle.spendRaffle(1, 5);
        assertEq(spinStub.balances(USER), 5);
        (, , uint256 pool, , , , ) = raffle.getPrizeDetails(1);
        assertEq(pool, 5);
    }

    function testSpendRaffleInsufficient() public {
        vm.prank(ADMIN);
        raffle.addPrize("A", "A", 0);
        spinStub.setBalance(USER, 1);
        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(Raffle.InsufficientTickets.selector)
        );
        raffle.spendRaffle(1, 2);
    }

    function testRequestWinnerEmitsEvents() public {
        vm.prank(ADMIN);
        raffle.addPrize("A", "A", 0);
        spinStub.setBalance(USER, 3);
        vm.prank(USER);
        raffle.spendRaffle(1, 3);

        vm.recordLogs();
        vm.prank(ADMIN);
        raffle.requestWinner(1);
        Vm.Log[] memory L = vm.getRecordedLogs();
        
        // Find the WinnerRequested event
        uint256 req = 0;
        for (uint i = 0; i < L.length; i++) {
            if (L[i].topics[0] == keccak256("WinnerRequested(uint256,uint256)")) {
                req = uint256(L[i].topics[2]);
                break;
            }
        }
        require(req != 0, "WinnerRequested event not found");

        uint256[] memory r = new uint256[](1);
        r[0] = 1;
        vm.recordLogs();
        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(req, r);
        L = vm.getRecordedLogs();
        assertEq(L[0].topics[0], keccak256("WinnerSelected(uint256,uint256)"));
    }

    function testClaimPrizeSuccess() public {
        vm.prank(ADMIN);
        raffle.addPrize("A", "A", 0);

        // Add tickets
        spinStub.setBalance(USER, 1);
        vm.prank(USER);
        raffle.spendRaffle(1, 1);

        // Verify tickets were spent
        (, , uint256 pool, , , , ) = raffle.getPrizeDetails(1);
        assertEq(pool, 1, "Tickets should be added to the pool");

        // Request winner
        vm.recordLogs();
        vm.prank(ADMIN);
        raffle.requestWinner(1);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Find request ID
        uint256 req = 0;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("WinnerRequested(uint256,uint256)")) {
                req = uint256(logs[i].topics[2]);
                break;
            }
        }
        require(req != 0, "Request ID not found in logs");

        // Select winner
        uint256[] memory rng = new uint256[](1);
        rng[0] = 0; // Will select USER
        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(req, rng);

        // Set winner
        vm.prank(ADMIN);
        raffle.setWinner(1);

        // Claim prize
        vm.prank(USER);
        raffle.claimPrize(1);

    }

    function testClaimPrizeNotWinner() public {
        vm.prank(ADMIN);
        raffle.addPrize("A", "A", 0);

        // Ensure we spend tickets so total is > 0
        spinStub.setBalance(USER, 2); // Increase to 2 tickets
        vm.prank(USER);
        raffle.spendRaffle(1, 2); // Spend 2 tickets

        // Verify tickets were spent
        (, , uint256 pool, , , , ) = raffle.getPrizeDetails(1);
        assertEq(pool, 2, "Tickets should be in the pool");

        vm.recordLogs();
        vm.prank(ADMIN);
        raffle.requestWinner(1);
        Vm.Log[] memory L1 = vm.getRecordedLogs();

        // Find the WinnerRequested event to get the request ID
        uint256 req = 0;
        for (uint i = 0; i < L1.length; i++) {
            if (L1[i].topics[0] == keccak256("WinnerRequested(uint256,uint256)")) {
                req = uint256(L1[i].topics[2]);
                break;
            }
        }
        require(req != 0, "WinnerRequested event not found");

        // Generate a random number that will select a winning ticket
        // We have 2 tickets (index 1-2), and USER owns both
        uint256[] memory r = new uint256[](1);
        r[0] = 0; // 0 % 2 + 1 = 1 (first ticket)

        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(req, r);

        // Try to claim with a different address
        vm.prank(USER2);
        vm.expectRevert(Raffle.NotAWinner.selector);
        raffle.claimPrize(1);
    }
    
    function testRemovePrizeFlow() public {
        vm.prank(ADMIN);
        raffle.addPrize("Test","Desc",1);
        // Remove prize
        vm.prank(ADMIN);
        raffle.removePrize(1);
        // Now spendRaffle should revert PrizeInactive
        spinStub.setBalance(USER,1);
        vm.prank(USER);
        vm.expectRevert("Prize not available");
        raffle.spendRaffle(1,1);
        // requestWinner should revert PrizeInactive
        vm.prank(ADMIN);
        vm.expectRevert();
        raffle.requestWinner(1);
    }

    function testSpendRaffleZeroTicketsReverts() public {
        vm.prank(ADMIN);
        raffle.addPrize("A","A",1);
        vm.prank(USER);
        vm.expectRevert("Must spend at least 1 ticket");
        raffle.spendRaffle(1,0);
    }

    function testSpendRaffleMultipleEntriesAndTotalUsers() public {
        vm.prank(ADMIN);
        raffle.addPrize("A","A",1);
        // First entry
        spinStub.setBalance(USER,5);
        vm.prank(USER);
        raffle.spendRaffle(1,2);
        (, , , , , , uint256 users1) = raffle.getPrizeDetails(1);
        assertEq(users1, 1);
        // Second entry same user
        spinStub.setBalance(USER,5);
        vm.prank(USER);
        raffle.spendRaffle(1,3);
        (, , , , , , uint256 users2) = raffle.getPrizeDetails(1);
        assertEq(users2, 1, "totalUsers should not increment for repeat entry");
    }

    function testRequestWinnerEmptyPoolReverts() public {
        vm.prank(ADMIN);
        raffle.addPrize("A","A",1);
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(Raffle.EmptyTicketPool.selector));
        raffle.requestWinner(1);
    }

    function testRequestWinnerAlreadyDrawnReverts() public {
        vm.prank(ADMIN);
        raffle.addPrize("A","A",1);
        // add tickets
        spinStub.setBalance(USER,1);
        vm.prank(USER);
        raffle.spendRaffle(1,1);
        
        // first draw
        vm.recordLogs();
        vm.prank(ADMIN);
        raffle.requestWinner(1);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        // Find request ID in logs
        uint256 req = 0;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("WinnerRequested(uint256,uint256)")) {
                req = uint256(logs[i].topics[2]);
                break;
            }
        }
        require(req != 0, "Request ID not found in logs");
        
        uint256[] memory rng = new uint256[](1);
        rng[0] = 0;
        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(req, rng);
        
        // Check that winnerIndex is set
        (, , , , , uint256 winnerIdx, ) = raffle.getPrizeDetails(1);
        assertEq(winnerIdx, 1, "Winner index should be set");
        
        // After handleWinnerSelection, add:
        vm.prank(ADMIN);
        raffle.setWinner(1);

        // Now claim the prize to set winner and make active=false
        vm.prank(USER);
        raffle.claimPrize(1);
        
        // Verify prize no longer active
        (, , , bool active, , , ) = raffle.getPrizeDetails(1);
        assertFalse(active, "Prize should be inactive after claiming");
        
        // second request should revert with "Prize not available" since we've claimed it
        vm.prank(ADMIN);
        vm.expectRevert("Prize not available");
        raffle.requestWinner(1);
    }

    function testHandleWinnerSelectionSetsWinnerIndex() public {
        vm.prank(ADMIN);
        raffle.addPrize("A","A",1);
        spinStub.setBalance(USER,3);
        vm.prank(USER);
        raffle.spendRaffle(1,3);
        
        vm.recordLogs();
        vm.prank(ADMIN);
        raffle.requestWinner(1);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        uint256 req = 0;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("WinnerRequested(uint256,uint256)")) {
                req = uint256(logs[i].topics[2]);
                break;
            }
        }
        require(req != 0, "Request ID not found in logs");

        uint256[] memory rng = new uint256[](1);
        rng[0] = 5;
        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(req, rng);

        (, , , , , uint256 winnerIdx, ) = raffle.getPrizeDetails(1);
        assertEq(winnerIdx, 3);
    }

    function testGetUserEntries() public {
        vm.prank(ADMIN);
        raffle.addPrize("A","A",1);
        spinStub.setBalance(USER,4);
        vm.prank(USER); raffle.spendRaffle(1,2);
        vm.prank(USER); raffle.spendRaffle(1,1);

        // getUserEntries(user) - check initial state
        (
            uint256[] memory ids, 
            uint256[] memory counts, 
            uint256[] memory unclaimedWins,
            uint256[] memory claimedWins
        ) = raffle.getUserEntries(USER);
        
        assertEq(ids.length, 1);
        assertEq(counts[0], 3);  // 2 + 1 tickets spent
        assertEq(unclaimedWins.length, 0);
        assertEq(claimedWins.length, 0);

        // draw and claim so wins get populated
        vm.recordLogs();
        vm.prank(ADMIN); 
        raffle.requestWinner(1);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        // Find request ID in logs
        uint256 req = 0;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("WinnerRequested(uint256,uint256)")) {
                req = uint256(logs[i].topics[2]);
                break;
            }
        }
        require(req != 0, "Request ID not found in logs");
        
        uint256[] memory rng = new uint256[](1); 
        rng[0] = 1;
        vm.prank(SUPRA_ORACLE); 
        raffle.handleWinnerSelection(req, rng);

        vm.prank(ADMIN);
        raffle.setWinner(1);

        // Check unclaimed wins before claiming
        (ids, counts, unclaimedWins, claimedWins) = raffle.getUserEntries(USER);
        assertEq(unclaimedWins.length, 1);
        assertEq(unclaimedWins[0], 1);
        assertEq(claimedWins.length, 0);

        // Claim the prize
        vm.prank(USER); 
        raffle.claimPrize(1);

        // Check claimed wins after claiming
        (ids, counts, unclaimedWins, claimedWins) = raffle.getUserEntries(USER);
        assertEq(ids.length, 1);
        assertEq(counts[0], 3);
        assertEq(unclaimedWins.length, 0);
        assertEq(claimedWins.length, 1);
        assertEq(claimedWins[0], 1);
    }

    // Test that getWinner returns the correct winner
    // Test with 2 users across 2 prizes
    function testGetWinner() public {
        // Draw winner with ticket #2 (USER1)
        vm.prank(ADMIN);
        raffle.addPrize("Test Prize", "A test prize", 100);
        
        // Add tickets for USER
        spinStub.setBalance(USER, 5);
        vm.prank(USER);
        raffle.spendRaffle(1, 3); // USER: tickets 1-3
        
        // Add tickets for USER2
        spinStub.setBalance(USER2, 5);
        vm.prank(USER2);
        raffle.spendRaffle(1, 2); // USER2: tickets 4-5
        
        // request prize ID1 winner
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
        rng[0] = 1; // Will result in ticket #2 - USER
        
        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(requestId, rng);
        
        // Add setWinner call before claiming
        vm.prank(ADMIN);
        raffle.setWinner(1);

        // Verify winner is USER
        address winner = raffle.getWinner(1);
        assertEq(winner, USER);
        
        // Test with ticket #4 (USER2)
        vm.prank(ADMIN);
        raffle.addPrize("Second Prize", "Another prize", 100);
        
        spinStub.setBalance(USER, 2);
        vm.prank(USER);
        raffle.spendRaffle(2, 2); // USER: tickets 1-2
        
        spinStub.setBalance(USER2, 2);
        vm.prank(USER2);
        raffle.spendRaffle(2, 2); // USER2: tickets 3-4
        
        vm.recordLogs();
        vm.prank(ADMIN);
        raffle.requestWinner(2);
        
        // Extract the request ID from logs for second prize
        logs = vm.getRecordedLogs();
        requestId = 0;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("WinnerRequested(uint256,uint256)")) {
                requestId = uint256(logs[i].topics[2]);
                break;
            }
        }
        require(requestId != 0, "Request ID not found in logs");
        
        rng[0] = 3; // Will result in ticket #4 - USER2
        
        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(requestId, rng);
        
        // Add setWinner call before claiming
        vm.prank(ADMIN);
        raffle.setWinner(2);

        // Verify winner is USER2
        winner = raffle.getWinner(2);
        assertEq(winner, USER2);
    }

    function testEditPrize() public {
        // Add a prize first
        vm.prank(ADMIN);
        raffle.addPrize("Original", "Original description", 100);
        
        // Add some tickets to verify they remain after edit
        spinStub.setBalance(USER, 5);
        vm.prank(USER);
        raffle.spendRaffle(1, 5);
        
        // Record the number of tickets before editing
        (, , uint256 poolBefore, , , , ) = raffle.getPrizeDetails(1);
        assertEq(poolBefore, 5, "Tickets should be in the pool");
        
        // Edit the prize
        vm.recordLogs();
        vm.prank(ADMIN);
        raffle.editPrize(1, "Updated", "Updated description", 200);
        
        // Verify the edit event was emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundEvent = false;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("PrizeEdited(uint256,string,string,uint256)")) {
                foundEvent = true;
                break;
            }
        }
        assertTrue(foundEvent, "PrizeEdited event not found");
        
        // Verify the prize details were updated but tickets remain
        (string memory n, string memory d, uint256 poolAfter, bool active, address w, , ) = 
            raffle.getPrizeDetails(1);
        
        assertEq(n, "Updated", "Name should be updated");
        assertEq(d, "Updated description", "Description should be updated");
        assertEq(poolAfter, 5, "Ticket pool should remain unchanged");
        assertTrue(active, "Prize should remain active");
        assertEq(w, address(0), "Winner should remain unchanged");
        
        // Verify we can still request a winner with the updated prize
        vm.prank(ADMIN);
        raffle.requestWinner(1);
    }

    function testEditPrizeGuards() public {
        // Add and remove a prize
        vm.prank(ADMIN);
        raffle.addPrize("Original", "Original description", 100);
        vm.prank(ADMIN);
        raffle.removePrize(1);
        
        // Try to edit inactive prize
        vm.prank(ADMIN);
        vm.expectRevert("Prize not available");
        raffle.editPrize(1, "Updated", "Updated description", 200);

        // Try to edit as non-admin
        vm.prank(USER);
        vm.expectRevert(); // Just expect any revert
        raffle.editPrize(1, "Updated", "Updated description", 200);
    }

    function testClaimPrizeAlreadyClaimedReverts() public {
        // Setup - add prize and spend raffle
        vm.prank(ADMIN);
        raffle.addPrize("Prize", "Test prize", 100);
        
        spinStub.setBalance(USER2, 1);
        vm.prank(USER2);
        raffle.spendRaffle(1, 1);
        
        // Request winner
        vm.recordLogs();
        vm.prank(ADMIN);
        raffle.requestWinner(1);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        // Find request ID
        uint256 req = 0;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("WinnerRequested(uint256,uint256)")) {
                req = uint256(logs[i].topics[2]);
                break;
            }
        }
        require(req != 0, "Request ID not found in logs");
        
        // Select winner
        uint256[] memory rng = new uint256[](1);
        rng[0] = 0; // Will select USER2
        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(req, rng);
        
        // After handleWinnerSelection, add:
        vm.prank(ADMIN);
        raffle.setWinner(1);
        
        // First claim should succeed
        vm.prank(USER2);
        raffle.claimPrize(1);
        
        // Second claim should revert with "Prize not available"
        vm.prank(USER2);
        vm.expectRevert(abi.encodeWithSelector(Raffle.WinnerClaimed.selector));
        raffle.claimPrize(1);
    }

    function testSetInactiveWinnerAlreadySetReverts() public {
        // Setup test prize
        vm.prank(ADMIN);
        raffle.addPrize("Prize", "Test prize", 100);
        
        // Add tickets
        spinStub.setBalance(USER, 3);
        vm.prank(USER);
        raffle.spendRaffle(1, 3);
        
        // Request winner
        vm.recordLogs();
        vm.prank(ADMIN);
        raffle.requestWinner(1);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        // Find request ID
        uint256 req = 0;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("WinnerRequested(uint256,uint256)")) {
                req = uint256(logs[i].topics[2]);
                break;
            }
        }
        require(req != 0, "Request ID not found in logs");
        
        // Select winner
        uint256[] memory rng = new uint256[](1);
        rng[0] = 1; // Will select USER's ticket
        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(req, rng);
        
        // After handleWinnerSelection, add:
        vm.prank(ADMIN);
        raffle.setWinner(1);

        // Verify the winner index is set
        (, , , , , uint256 winnerIdx, ) = raffle.getPrizeDetails(1);
        assertGt(winnerIdx, 0, "Winner index should be set");
        
        // Claim the prize first time (this will set winner and deactivate the prize)
        vm.prank(USER);
        raffle.claimPrize(1);
        
        // Verify prize is now inactive and has winner set
        (, , , bool active, address winner, , ) = raffle.getPrizeDetails(1);
        assertFalse(active, "Prize should be inactive after claiming");
        assertEq(winner, USER, "Winner should be set to USER");
        
        // Manually set the prize back to active while keeping the winner set
        vm.prank(ADMIN);
        vm.expectRevert("Winner already selected");
        raffle.setPrizeActive(1, true);
        
    }

    function testWinnerFlow() public {
        // Setup prize and tickets
        vm.prank(ADMIN);
        raffle.addPrize("Test Prize", "A test prize", 100);
        
        // Add tickets for USER
        spinStub.setBalance(USER, 5);
        vm.prank(USER);
        raffle.spendRaffle(1, 3); // USER: tickets 1-3
        
        // Add tickets for USER2
        spinStub.setBalance(USER2, 5);
        vm.prank(USER2);
        raffle.spendRaffle(1, 2); // USER2: tickets 4-5
        
        // Request winner
        vm.recordLogs();
        vm.prank(ADMIN);
        raffle.requestWinner(1);
        
        // Extract request ID from logs
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 requestId = 0;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("WinnerRequested(uint256,uint256)")) {
                requestId = uint256(logs[i].topics[2]);
                break;
            }
        }
        require(requestId != 0, "Request ID not found in logs");
        
        // Set winning ticket to #2 (USER)
        uint256[] memory rng = new uint256[](1);
        rng[0] = 4; // Will result in ticket #4 - USER2
        
        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(requestId, rng);
        
        // Winner should not be set yet
        address winnerBefore = raffle.getWinner(1);
        assertEq(winnerBefore, address(0), "Winner should not be set before setWinner");
        
        // Set winner
        vm.prank(ADMIN);
        raffle.setWinner(1);
        
        // Verify winner is USER
        address winner = raffle.getWinner(1);
        assertEq(winner, USER2, "Winner should be USER after setWinner");
    }

    function testSetWinner() public {
        // Setup prize
        vm.prank(ADMIN);
        raffle.addPrize("Test Prize", "A test prize", 100);
        
        // Add tickets
        spinStub.setBalance(USER, 1);
        vm.prank(USER);
        raffle.spendRaffle(1, 1);
        
        // Try to set winner before winner index is set
        vm.prank(ADMIN);
        vm.expectRevert("Winner index not set");
        raffle.setWinner(1);
        
        // Request winner and get request ID from logs
        vm.recordLogs();
        vm.prank(ADMIN);
        raffle.requestWinner(1);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        uint256 requestId = 0;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("WinnerRequested(uint256,uint256)")) {
                requestId = uint256(logs[i].topics[2]);
                break;
            }
        }
        require(requestId != 0, "Request ID not found in logs");
        
        // Select winner
        uint256[] memory rng = new uint256[](1);
        rng[0] = 0;
        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(requestId, rng);
        
        // Try to set winner as non-admin
        vm.prank(USER);
        vm.expectRevert();
        raffle.setWinner(1);

        // Set winner
        vm.prank(ADMIN);
        raffle.setWinner(1);
        
        // Try to set winner again
        vm.prank(ADMIN);
        vm.expectRevert("Winner already set");
        raffle.setWinner(1);
        
        // Verify winner
        assertEq(raffle.getWinner(1), USER);
    }

    function testPrizeDeleteAddDoesNotOverwriteActivePrize() public {
        // create ids 1-3 
        vm.prank(ADMIN); raffle.addPrize("A", "one",   0); // id-1
        vm.prank(ADMIN); raffle.addPrize("B", "two",   0); // id-2
        vm.prank(ADMIN); raffle.addPrize("C", "three", 0); // id-3

        // remove id-2 ───────────────────────────────────────────────────────
        vm.prank(ADMIN); raffle.removePrize(2);

        // sanity: id-3 is still "C"
        (string memory before,, , , , ,) = raffle.getPrizeDetails(3);
        assertEq(before, "C");

        // add another prize (should become id-4)
        vm.prank(ADMIN); raffle.addPrize("D", "four", 0); // BUG: re-uses id-3

        // EXPECTATION: id-3 still "C"
        (string memory aft,, , , , ,) = raffle.getPrizeDetails(3);
        assertEq(aft,"C","addPrize re-issued id-3 and overwrote live prize");
    }

}


