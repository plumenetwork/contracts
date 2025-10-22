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
        raffle.addPrize("Gold", "Shiny", 0, 1, "0");
        (string memory n, string memory d, uint256 t,,,,,, uint256 quantity, uint256 drawn, string memory formId) = raffle
            .getPrizeDetails(1);
        assertEq(n, "Gold");
        assertEq(d, "Shiny");
        assertEq(t, 0);
        assertEq(quantity, 1);
        assertEq(drawn, 0);
    }

    function testSpendRaffleSuccess() public {
        vm.prank(ADMIN);
        raffle.addPrize("A", "A", 0, 1, "0");
        spinStub.setBalance(USER, 10);
        vm.prank(USER);
        raffle.spendRaffle(1, 5);
        assertEq(spinStub.balances(USER), 5);
        (, , uint256 pool,,,,,,,, ) = raffle.getPrizeDetails(1);
        assertEq(pool, 5);
    }

    function testSpendRaffleInsufficient() public {
        vm.prank(ADMIN);
        raffle.addPrize("A", "A", 0, 1,"0");
        spinStub.setBalance(USER, 1);
        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(Raffle.InsufficientTickets.selector)
        );
        raffle.spendRaffle(1, 2);
    }

    function testRequestWinnerEmitsEvents() public {
        vm.prank(ADMIN);
        raffle.addPrize("A", "A", 0, 1,"0");
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
        assertEq(L[0].topics[0], keccak256("WinnerSelected(uint256,address,uint256)"));
    }

    function testClaimPrizeSuccess() public {
        vm.prank(ADMIN);
        raffle.addPrize("A", "A", 0, 1,"0");

        // Add tickets
        spinStub.setBalance(USER, 1);
        vm.prank(USER);
        raffle.spendRaffle(1, 1);

        // Verify tickets were spent
        (, , uint256 pool,,,,,,,, ) = raffle.getPrizeDetails(1);
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

        Raffle.Winner[] memory winners = raffle.getPrizeWinners(1);
        assertFalse(winners[0].claimed, "Winner claimed beforehand is true");

        // Claim prize
        vm.prank(USER);
        raffle.claimPrize(1, 0);

        winners = raffle.getPrizeWinners(1);
        assertTrue(winners[0].claimed, "Winner claimed after is false");
        assertEq(winners[0].winnerAddress, USER, "Winner should be user after");

    }

    function testClaimPrizeNotWinner() public {
        vm.prank(ADMIN);
        raffle.addPrize("A", "A", 0, 1,"0");

        // Ensure we spend tickets so total is > 0
        spinStub.setBalance(USER, 2); // Increase to 2 tickets
        vm.prank(USER);
        raffle.spendRaffle(1, 2); // Spend 2 tickets

        // Verify tickets were spent
        (, , uint256 pool,,,,,,,, ) = raffle.getPrizeDetails(1);
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
        raffle.claimPrize(1, 0);
    }
    
    function testRemovePrizeFlow() public {
        vm.prank(ADMIN);
        raffle.addPrize("Test","Desc",1, 1,"0");
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
        raffle.addPrize("A","A",1, 1,"0");
        vm.prank(USER);
        vm.expectRevert("Must spend at least 1 ticket");
        raffle.spendRaffle(1,0);
    }

    function testSpendRaffleMultipleEntriesAndTotalUsers() public {
        vm.prank(ADMIN);
        raffle.addPrize("A","A",1, 1,"0");
        // First entry
        spinStub.setBalance(USER,5);
        vm.prank(USER);
        raffle.spendRaffle(1,2);
        (,,,,,, uint256 users1,,,,) = raffle.getPrizeDetails(1);
        assertEq(users1, 1);
        // Second entry same user
        spinStub.setBalance(USER,5);
        vm.prank(USER);
        raffle.spendRaffle(1,3);
        (,,,,,, uint256 users2,,,,) = raffle.getPrizeDetails(1);
        assertEq(users2, 1, "totalUsers should not increment for repeat entry");
    }

    function testGetPrizeDetailsAllPrizes() public {
        vm.prank(ADMIN);
        raffle.addPrize("A","A",1, 2,"0");
        vm.prank(ADMIN);
        raffle.addPrize("B","B",1, 2,"0");

        spinStub.setBalance(USER,15);

        vm.prank(USER);
        raffle.spendRaffle(1,2); // 2 tickets into prize 1

        vm.prank(USER);
        raffle.spendRaffle(1,3); // 3 tickets into prize 1 (again)

        vm.prank(USER);
        raffle.spendRaffle(2,1); // 1 ticket into prize 2

        // First entry
        spinStub.setBalance(USER2,15);

        vm.prank(USER2);
        raffle.spendRaffle(1,4); // 4 tickets into prize 1

        vm.prank(USER2);
        raffle.spendRaffle(2,6); // 6 tickets into prize 2

        (Raffle.PrizeWithTickets[] memory prizes) = raffle.getPrizeDetails();
        assertEq(prizes[0].totalUsers, 2, "totalUsers should not increment for repeat entry");
        assertEq(prizes[1].totalUsers, 2, "totalUsers should not increment for repeat entry");
        assertEq(prizes[0].totalTickets, 9, "totalTickets should not increment for repeat entry");
        assertEq(prizes[1].totalTickets, 7, "totalTickets should not increment for repeat entry");
    }

    function testRequestWinnerEmptyPoolReverts() public {
        vm.prank(ADMIN);
        raffle.addPrize("A","A",1, 1,"0");
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(Raffle.EmptyTicketPool.selector));
        raffle.requestWinner(1);
    }

    function testRequestWinnerAllWinnersDrawnReverts() public {
        vm.prank(ADMIN);
        raffle.addPrize("A","A",1, 1,"0");
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

        // second request should revert with AllWinnersDrawn since quantity is 1
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(Raffle.AllWinnersDrawn.selector));
        raffle.requestWinner(1);
    }

    function testHandleWinnerSelectionSetsWinner() public {
        vm.prank(ADMIN);
        raffle.addPrize("A","A",1, 1,"0");
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
        rng[0] = 5; // 5 % 3 + 1 = 3
        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(req, rng);

        Raffle.Winner[] memory winners = raffle.getPrizeWinners(1);
        assertEq(winners.length, 1);
        assertEq(winners[0].winnerAddress, USER);
        assertEq(winners[0].winningTicketIndex, 3);
    }

    function testGetUserWins() public {
        vm.prank(ADMIN);
        raffle.addPrize("A","A",1, 1,"0");
        spinStub.setBalance(USER,4);
        vm.prank(USER); raffle.spendRaffle(1,2);
        vm.prank(USER); raffle.spendRaffle(1,1);
   
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

        // Claim the prize
        vm.prank(USER); 
        raffle.claimPrize(1, 0);
        
        uint256[] memory userWins = raffle.getUserWinnings(USER);
        assertEq(userWins.length, 1);
        assertEq(userWins[0], 1);
    }

    // Test that getWinner returns the correct winner
    // Test with 2 users across 2 prizes
    function testGetWinner() public {
        // Draw winner with ticket #2 (USER)
        vm.prank(ADMIN);
        raffle.addPrize("Test Prize", "A test prize", 100, 1,"0");
        
        // Add tickets for USER
        spinStub.setBalance(USER, 5);
        vm.prank(USER);
        raffle.spendRaffle(1, 3); // USER: tickets 1-3
        
        // Add tickets for USER2
        spinStub.setBalance(USER2, 5);
        vm.prank(USER2);
        raffle.spendRaffle(1, 2); // USER2: tickets 4-5
        
        // request prize ID1 winner
        uint256 requestId = requestWinnerForPrize(1);
        
        uint256[] memory rng = new uint256[](1);
        rng[0] = 1; // Will result in ticket #2 - USER
        
        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(requestId, rng);

        // Verify winner is USER
        address winner = raffle.getWinner(1, 0);
        assertEq(winner, USER);
        
        // Test with ticket #4 (USER2)
        vm.prank(ADMIN);
        raffle.addPrize("Second Prize", "Another prize", 100, 1,"0");
        
        spinStub.setBalance(USER, 2);
        vm.prank(USER);
        raffle.spendRaffle(2, 2); // USER: tickets 1-2
        
        spinStub.setBalance(USER2, 2);
        vm.prank(USER2);
        raffle.spendRaffle(2, 2); // USER2: tickets 3-4
        
        requestId = requestWinnerForPrize(2);
        
        rng[0] = 3; // Will result in ticket #4 - USER2
        
        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(requestId, rng);

        // Verify winner is USER2
        winner = raffle.getWinner(2, 0);
        assertEq(winner, USER2);
    }

    function testEditPrize() public {
        // Add a prize first
        vm.prank(ADMIN);
        raffle.addPrize("Original", "Original description", 100, 1,"0");
        
        // Add some tickets to verify they remain after edit
        spinStub.setBalance(USER, 5);
        vm.prank(USER);
        raffle.spendRaffle(1, 5);
        
        // Record the number of tickets before editing
        (, , uint256 poolBefore,,,,,,,,) = raffle.getPrizeDetails(1);
        assertEq(poolBefore, 5, "Tickets should be in the pool");
        
        // Edit the prize
        vm.recordLogs();
        vm.prank(ADMIN);
        raffle.editPrize(1, "Updated", "Updated description", 200, 2, "0");
        
        // Verify the edit event was emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundEvent = false;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("PrizeEdited(uint256,string,string,uint256,uint256)")) {
                foundEvent = true;
                break;
            }
        }
        assertTrue(foundEvent, "PrizeEdited event not found");
        
        // Verify the prize details were updated but tickets remain
        (string memory n, string memory d, uint256 poolAfter, bool active, , , , , uint256 quantity, ,) = 
            raffle.getPrizeDetails(1);
        
        assertEq(n, "Updated", "Name should be updated");
        assertEq(d, "Updated description", "Description should be updated");
        assertEq(poolAfter, 5, "Ticket pool should remain unchanged");
        assertTrue(active, "Prize should remain active");
        assertEq(quantity, 2, "Quantity should be updated");
        
        // Verify we can still request a winner with the updated prize
        vm.prank(ADMIN);
        raffle.requestWinner(1);
    }

    function testEditPrizeGuards() public {
        // Add and remove a prize
        vm.prank(ADMIN);
        raffle.addPrize("Original", "Original description", 100, 1, "0");
        vm.prank(ADMIN);
        raffle.removePrize(1);
        
        // Try to edit inactive prize
        vm.prank(ADMIN);
        vm.expectRevert("Prize not available");
        raffle.editPrize(1, "Updated", "Updated description", 200, 1, "0");

        // Try to edit as non-admin
        vm.prank(USER);
        vm.expectRevert(); // Just expect any revert
        raffle.editPrize(1, "Updated", "Updated description", 200, 1, "0");
    }

    function testClaimPrizeAlreadyClaimedReverts() public {
        // Setup - add prize and spend raffle
        vm.prank(ADMIN);
        raffle.addPrize("Prize", "Test prize", 100, 1, "0");
        
        spinStub.setBalance(USER2, 1);
        vm.prank(USER2);
        raffle.spendRaffle(1, 1);
        
        uint256 req = requestWinnerForPrize(1);
        
        // Select winner
        uint256[] memory rng = new uint256[](1);
        rng[0] = 0; // Will select USER2
        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(req, rng);
        
        // First claim should succeed
        vm.prank(USER2);
        raffle.claimPrize(1, 0);
        
        // Second claim should revert
        vm.prank(USER2);
        vm.expectRevert(abi.encodeWithSelector(Raffle.WinnerClaimed.selector));
        raffle.claimPrize(1, 0);
    }

    function testSetPrizeActiveGuards() public {
        // Setup test prize
        vm.prank(ADMIN);
        raffle.addPrize("Prize", "Test prize", 100, 1, "0");
        
        // Add tickets
        spinStub.setBalance(USER, 3);
        vm.prank(USER);
        raffle.spendRaffle(1, 3);
        
        uint256 req = requestWinnerForPrize(1);
        
        // Select winner
        uint256[] memory rng = new uint256[](1);
        rng[0] = 1; // Will select USER's ticket
        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(req, rng);
        
        // Prize is now inactive because all winners are drawn
        (,,, bool active,,,,,,,) = raffle.getPrizeDetails(1);
        assertFalse(active, "Prize should be inactive after all winners drawn");
        
        // Try to set it back to active should revert because all winners are selected
        vm.prank(ADMIN);
        vm.expectRevert("All winners already selected");
        raffle.setPrizeActive(1, true);
    }

    function testWinnerFlowNoSetWinner() public {
        // Setup prize and tickets
        vm.prank(ADMIN);
        raffle.addPrize("Test Prize", "A test prize", 100, 1, "0");
        
        // Add tickets for USER
        spinStub.setBalance(USER, 5);
        vm.prank(USER);
        raffle.spendRaffle(1, 3); // USER: tickets 1-3
        
        // Add tickets for USER2
        spinStub.setBalance(USER2, 5);
        vm.prank(USER2);
        raffle.spendRaffle(1, 2); // USER2: tickets 4-5
        
        uint256 requestId = requestWinnerForPrize(1);
        
        // Set winning ticket to #4 (USER2)
        uint256[] memory rng = new uint256[](1);
        rng[0] = 3; // Will result in ticket #4 -> (3 % 5) + 1 = 4
        
        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(requestId, rng);
        
        // Verify winner is USER2
        address winner = raffle.getWinner(1, 0);
        assertEq(winner, USER2, "Winner should be USER2 after handleWinnerSelection");
    }

    function testSetWinnerIsDeprecated() public {
        vm.prank(ADMIN);
        vm.expectRevert("setWinner is deprecated, winner is set in handleWinnerSelection");
        raffle.setWinner(1);
    }

    function testPrizeDeleteAddDoesNotOverwriteActivePrize() public {
        // create ids 1-3 
        vm.prank(ADMIN); raffle.addPrize("A", "one",   0, 1, "0"); // id-1
        vm.prank(ADMIN); raffle.addPrize("B", "two",   0, 1, "0"); // id-2
        vm.prank(ADMIN); raffle.addPrize("C", "three", 0, 1, "0"); // id-3

        // remove id-2 ───────────────────────────────────────────────────────
        vm.prank(ADMIN); raffle.removePrize(2);

        // sanity: id-3 is still "C"
        (string memory before,,,,,,,,,, ) = raffle.getPrizeDetails(3);
        assertEq(before, "C");

        // add another prize (should become id-4)
        vm.prank(ADMIN); raffle.addPrize("D", "four", 0, 1, "0"); // BUG: re-uses id-3

        // EXPECTATION: id-3 still "C"
        (string memory aft,,,,,,,,,, ) = raffle.getPrizeDetails(3);
        assertEq(aft,"C","addPrize re-issued id-3 and overwrote live prize");
    }

    function testMultipleWinners() public {
        vm.prank(ADMIN);
        raffle.addPrize("Multi-Winner Prize", "Desc", 100, 2, "0");

        spinStub.setBalance(USER, 5);
        vm.prank(USER);
        raffle.spendRaffle(1, 3); // User tickets 1-3
        
        spinStub.setBalance(USER2, 5);
        vm.prank(USER2);
        raffle.spendRaffle(1, 2); // User2 tickets 4-5

        // Request and draw first winner (USER2)
        uint256 req1 = requestWinnerForPrize(1);
        uint256[] memory rng1 = new uint256[](1);
        rng1[0] = 4; // Ticket #5 -> USER2
        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(req1, rng1);

        // Check first winner
        assertEq(raffle.getWinner(1, 0), USER2);
        (,,, bool isActive1,,,,,, uint256 drawn1,) = raffle.getPrizeDetails(1);
        assertTrue(isActive1, "Prize should still be active");
        assertEq(drawn1, 1, "Should have 1 winner drawn");

        // Request and draw second winner (USER)
        uint256 req2 = requestWinnerForPrize(1);
        uint256[] memory rng2 = new uint256[](1);
        rng2[0] = 1; // Ticket #2 -> USER
        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(req2, rng2);

        // Check second winner
        assertEq(raffle.getWinner(1, 1), USER);
        (,,, bool isActive2,,,,,, uint256 drawn2,) = raffle.getPrizeDetails(1);
        assertFalse(isActive2, "Prize should be inactive after all winners drawn");
        assertEq(drawn2, 2, "Should have 2 winners drawn");

        // Try to request another winner
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(Raffle.AllWinnersDrawn.selector));
        raffle.requestWinner(1);
    }

    function test_MultiWinner_Claiming_Is_Isolated() public {
        vm.prank(ADMIN);
        raffle.addPrize("Multi-Winner Prize", "Desc", 100, 2, "0");

        spinStub.setBalance(USER, 5);
        vm.prank(USER);
        raffle.spendRaffle(1, 3); // User tickets 1-3
        
        spinStub.setBalance(USER2, 5);
        vm.prank(USER2);
        raffle.spendRaffle(1, 2); // User2 tickets 4-5

        // Request and draw first winner (USER2)
        uint256 req1 = requestWinnerForPrize(1);
        uint256[] memory rng1 = new uint256[](1);
        rng1[0] = 4; // Ticket #5 -> USER2
        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(req1, rng1);

        // Request and draw second winner (USER)
        uint256 req2 = requestWinnerForPrize(1);
        uint256[] memory rng2 = new uint256[](1);
        rng2[0] = 1; // Ticket #2 -> USER
        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(req2, rng2);

        // USER2 (winner index 0) claims their prize
        vm.prank(USER2);
        raffle.claimPrize(1, 0);

        // Verify state
        Raffle.Winner[] memory winners = raffle.getPrizeWinners(1);
        assertTrue(winners[0].claimed, "Winner 0 (USER2) should have claimed status true");
        assertFalse(winners[1].claimed, "Winner 1 (USER) should still have claimed status false");

        // USER (winner index 1) claims their prize
        vm.prank(USER);
        raffle.claimPrize(1, 1);
        
        // Verify state again
        winners = raffle.getPrizeWinners(1);
        assertTrue(winners[0].claimed, "Winner 0 (USER2) should remain claimed");
        assertTrue(winners[1].claimed, "Winner 1 (USER) should now be claimed");
    }

    function test_MultiWinner_Same_User_Wins_Twice() public {
        vm.prank(ADMIN);
        raffle.addPrize("Prize", "Desc", 100, 2, "0");

        spinStub.setBalance(USER, 5);
        vm.prank(USER);
        raffle.spendRaffle(1, 5); // All 5 tickets belong to USER

        // Draw first winner
        uint256 req1 = requestWinnerForPrize(1);
        uint256[] memory rng1 = new uint256[](1);
        rng1[0] = 1; // Ticket #2
        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(req1, rng1);

        // Draw second winner
        uint256 req2 = requestWinnerForPrize(1);
        uint256[] memory rng2 = new uint256[](1);
        rng2[0] = 3; // Ticket #4
        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(req2, rng2);

        // Verify both winners are the same user
        Raffle.Winner[] memory winners = raffle.getPrizeWinners(1);
        assertEq(winners.length, 2, "Should have two winners");
        assertEq(winners[0].winnerAddress, USER, "Winner 1 should be USER");
        assertEq(winners[1].winnerAddress, USER, "Winner 2 should be USER");

        // USER claims the first win (index 0)
        vm.prank(USER);
        raffle.claimPrize(1, 0);

        // Verify claim states
        winners = raffle.getPrizeWinners(1);
        assertTrue(winners[0].claimed, "First win should be claimed");
        assertFalse(winners[1].claimed, "Second win should not be claimed yet");

        // USER claims the second win (index 1)
        vm.prank(USER);
        raffle.claimPrize(1, 1);

        // Verify both are claimed
        winners = raffle.getPrizeWinners(1);
        assertTrue(winners[1].claimed, "Second win should now be claimed");
    }

    function test_MultiWinner_Edit_Prize_Increase_Quantity() public {
        vm.prank(ADMIN);
        raffle.addPrize("Prize", "Desc", 100, 1, "0");

        spinStub.setBalance(USER, 2);
        vm.prank(USER);
        raffle.spendRaffle(1, 2);

        // Draw one winner
        uint256 req1 = requestWinnerForPrize(1);
        uint256[] memory rng1 = new uint256[](1);
        rng1[0] = 0;
        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(req1, rng1);

        // Prize should now be inactive
        (,,,bool isActive,,,,,,,) = raffle.getPrizeDetails(1);
        assertFalse(isActive, "Prize should be inactive after 1/1 winners drawn");

        // Attempt to edit prize after it's inactive, should revert
        vm.prank(ADMIN);
        vm.expectRevert("Prize not available");
        raffle.editPrize(1, "Prize", "Desc", 100, 2, "0");
    }

    function test_MultiWinner_Edit_Prize_Decrease_Quantity() public {
        vm.prank(ADMIN);
        raffle.addPrize("Prize", "Desc", 100, 3, "0");

        spinStub.setBalance(USER, 2);
        vm.prank(USER);
        raffle.spendRaffle(1, 2);

        // Draw one winner
        uint256 req1 = requestWinnerForPrize(1);
        uint256[] memory rng1 = new uint256[](1);
        rng1[0] = 0;
        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(req1, rng1);

        // Prize should still be active
        (,,,bool isActive,,,,,,,) = raffle.getPrizeDetails(1);
        assertTrue(isActive, "Prize should still be active after 1/3 winners drawn");

        // Edit prize to decrease quantity to 1
        vm.prank(ADMIN);
        raffle.editPrize(1, "Prize", "Desc", 100, 1, "0");
        
        // Now requesting a winner should fail as we've already drawn 1.
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(Raffle.AllWinnersDrawn.selector));
        raffle.requestWinner(1);
    }

    function test_MultiWinner_Binary_Search_With_Large_Pool() public {
        vm.prank(ADMIN);
        raffle.addPrize("Large Pool Prize", "Desc", 100, 1, "0");
        
        uint256 totalTickets;
        address[] memory users = new address[](50);

        // 50 users each spend a different number of tickets
        for (uint i = 0; i < 50; i++) {
            address user = address(uint160(uint(keccak256(abi.encodePacked("user", i)))));
            users[i] = user;
            uint256 ticketsToSpend = i + 1;
            totalTickets += ticketsToSpend;

            spinStub.setBalance(user, ticketsToSpend);
            vm.prank(user);
            raffle.spendRaffle(1, ticketsToSpend);
        }

        (,,uint256 ticketsInPool,,,,,,,,) = raffle.getPrizeDetails(1);
        assertEq(ticketsInPool, totalTickets, "Total tickets in pool is incorrect");

        // Request a winner, RNG selects a ticket in the middle of the ranges
        uint256 winningTicket = totalTickets - 100; // Somewhere in the upper-middle
        address expectedWinner;

        // Manually calculate who the winner should be based on our ranges
        uint256 cumulative = 0;
        for (uint i = 0; i < 50; i++) {
            cumulative += (i + 1);
            if (winningTicket <= cumulative) {
                expectedWinner = users[i];
                break;
            }
        }
        require(expectedWinner != address(0), "Could not determine expected winner");

        uint256 req = requestWinnerForPrize(1);
        uint256[] memory rng = new uint256[](1);
        rng[0] = winningTicket - 1; // Since VRF is 0-indexed and tickets are 1-indexed
        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(req, rng);

        // Verify the contract's binary search found the correct winner
        address actualWinner = raffle.getWinner(1, 0);
        assertEq(actualWinner, expectedWinner, "Winner from large pool is incorrect");
    }

    /// Helper to request a winner and return the request ID
    function requestWinnerForPrize(uint256 prizeId) internal returns (uint256) {
        vm.recordLogs();
        vm.prank(ADMIN);
        raffle.requestWinner(prizeId);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        uint256 req = 0;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("WinnerRequested(uint256,uint256)")) {
                req = uint256(logs[i].topics[2]);
                break;
            }
        }
        require(req != 0, "Request ID not found in logs");
        return req;
    }

    function test_Cancel_Request_Success() public {
        // Setup prize and tickets
        vm.prank(ADMIN);
        raffle.addPrize("Test Prize", "Desc", 100, 1,"0");
        spinStub.setBalance(USER, 5);
        vm.prank(USER);
        raffle.spendRaffle(1, 5);

        vm.prank(ADMIN);
        // 1. Request a winner, putting the prize in a pending state
        raffle.requestWinner(1);

        // We can't check internal state directly, so we verify by behavior.
        // Trying to request again should fail.
        vm.expectRevert(abi.encodeWithSelector(Raffle.WinnerRequestPending.selector, 1));
        vm.prank(ADMIN);
        raffle.requestWinner(1);
        
vm.prank(ADMIN);
        // 2. Admin cancels the pending request
        raffle.cancelWinnerRequest(1);

        // 3. Now, requesting a winner again should succeed
        uint256 reqId = requestWinnerForPrize(1);
        assertTrue(reqId > 0, "Should be able to request a winner after cancellation");
        vm.stopPrank();
    }

    function test_Cancel_Request_Fails_For_Non_Admin() public {
        // Setup prize and tickets
        vm.prank(ADMIN);
        raffle.addPrize("Test Prize", "Desc", 100, 1,"0");
        spinStub.setBalance(USER, 5);
        vm.prank(USER);
        raffle.spendRaffle(1, 5);

        // Request a winner to create a pending state
        vm.prank(ADMIN);
        raffle.requestWinner(1);

        // Attempt to cancel from a non-admin account
        vm.prank(USER);
        vm.expectRevert(); // Revert due to onlyRole(ADMIN_ROLE)
        raffle.cancelWinnerRequest(1);
    }

    function test_Cancel_Request_Fails_When_Not_Pending() public {
        // Setup prize
        vm.prank(ADMIN);
        raffle.addPrize("Test Prize", "Desc", 100, 1,"0");

        // Attempt to cancel should revert with our specific error message
        vm.prank(ADMIN);
        vm.expectRevert("No request pending for this prize");
        raffle.cancelWinnerRequest(1);
    }
}

