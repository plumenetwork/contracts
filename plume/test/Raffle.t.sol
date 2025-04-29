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

    function testRemovePrize() public {
        vm.prank(ADMIN);
        raffle.addPrize("X", "X", 0);
        vm.prank(ADMIN);
        raffle.removePrize(1);
        (, , , bool active, , , ) = raffle.getPrizeDetails(1);
        assertFalse(active);
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

    function testRequestWinnerAndSelection() public {
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

        // Increase ticket amount to make sure the total is properly updated
        spinStub.setBalance(USER, 1);
        vm.prank(USER);
        raffle.spendRaffle(1, 1);

        // First verify tickets were spent
        (, , uint256 pool, , , , ) = raffle.getPrizeDetails(1);
        assertEq(pool, 1, "Tickets should be added to the pool");

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

        // Generate a random number that will select the user's ticket
        // Since we know there's only 1 ticket (index 1), we pass a value that will result in index 1
        uint256[] memory r = new uint256[](1);
        r[0] = 0; // 0 % 1 + 1 = 1

        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(req, r);

        vm.recordLogs();
        vm.prank(USER);
        raffle.claimPrize(1);
        Vm.Log[] memory L2 = vm.getRecordedLogs();

        // Verify the PrizeClaimed event
        bool foundEvent = false;
        for (uint i = 0; i < L2.length; i++) {
            if (L2[i].topics[0] == keccak256("PrizeClaimed(address,uint256)")) {
                foundEvent = true;
                break;
            }
        }
        assertTrue(foundEvent, "PrizeClaimed event not found");
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

    function testClaimPrizeDoubleClaimReverts() public {
        vm.prank(ADMIN);
        raffle.addPrize("A","A",1);
        spinStub.setBalance(USER,1);
        vm.prank(USER);
        raffle.spendRaffle(1,1);

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

        // first claim
        vm.prank(USER);
        raffle.claimPrize(1);
        // second claim should revert Prize not available
        vm.prank(USER);
        vm.expectRevert("Prize not available");
        raffle.claimPrize(1);
    }

    function testGetUserEntriesAndOverload() public {
        vm.prank(ADMIN);
        raffle.addPrize("A","A",1);
        spinStub.setBalance(USER,4);
        vm.prank(USER); raffle.spendRaffle(1,2);
        vm.prank(USER); raffle.spendRaffle(1,1);

        // getUserEntries(prizeId, user)
        (uint256 count, uint256[] memory wins) = raffle.getUserEntries(1, USER);
        assertEq(count, 3);
        assertEq(wins.length, 0);

        // draw and claim so that wins populated
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
        vm.prank(USER); 
        raffle.claimPrize(1);

        (count, wins) = raffle.getUserEntries(1, USER);
        assertEq(wins.length, 1);
        assertEq(wins[0], 1);

        // getUserEntries(user)
        (uint256[] memory ids, uint256[] memory counts, uint256[] memory wlist) = raffle.getUserEntries(USER);
        assertEq(ids.length, 1);
        assertEq(counts[0], 3);
        assertEq(wlist[0], 1);
    }

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
        rng[0] = 1; // Will result in ticket #2
        
        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(requestId, rng);
        
        // Verify winner is USER
        address winner = raffle.getWinner(1);
        assertEq(winner, USER);
        
        // Test with ticket #4 (USER2)
        vm.prank(ADMIN);
        raffle.addPrize("Second Prize", "Another prize", 100);
        
        spinStub.setBalance(USER, 2);
        vm.prank(USER);
        raffle.spendRaffle(2, 2);
        
        spinStub.setBalance(USER2, 2);
        vm.prank(USER2);
        raffle.spendRaffle(2, 2);
        
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
        
        rng[0] = 3; // Will result in ticket #4
        
        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(requestId, rng);
        
        // Verify winner is USER2
        winner = raffle.getWinner(2);
        assertEq(winner, USER2);
    }

    function testGetUserWinningStatus() public {
        // Setup prize
        vm.prank(ADMIN);
        raffle.addPrize("Test Prize", "A test prize", 100);
        
        // Add tickets for USER and USER2
        spinStub.setBalance(USER, 5);
        vm.prank(USER);
        raffle.spendRaffle(1, 3); // USER: tickets 1-3
        
        spinStub.setBalance(USER2, 5);
        vm.prank(USER2);
        raffle.spendRaffle(1, 2); // USER2: tickets 4-5
        
        // Draw winner with ticket #2 (USER) for prize 1
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
        rng[0] = 1; // Will result in ticket #2
        
        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(requestId, rng);
        
        // Check unclaimed wins for USER
        (uint256[] memory unclaimed, uint256[] memory claimed) = raffle.getUserWinningStatus(USER);
        assertEq(unclaimed.length, 1);
        assertEq(unclaimed[0], 1);
        assertEq(claimed.length, 0);
        
        // USER claims prize
        vm.prank(USER);
        raffle.claimPrize(1);
        
        // Check claimed wins updated
        (unclaimed, claimed) = raffle.getUserWinningStatus(USER);
        assertEq(unclaimed.length, 0);
        assertEq(claimed.length, 1);
        assertEq(claimed[0], 1);
        
        // No wins for USER2
        (unclaimed, claimed) = raffle.getUserWinningStatus(USER2);
        assertEq(unclaimed.length, 0);
        assertEq(claimed.length, 0);
        
        // Setup another prize where USER2 wins
        vm.prank(ADMIN);
        raffle.addPrize("Second Prize", "Another prize", 100);
        
        spinStub.setBalance(USER, 2);
        vm.prank(USER);
        raffle.spendRaffle(2, 2);
        
        spinStub.setBalance(USER2, 2);
        vm.prank(USER2);
        raffle.spendRaffle(2, 2);
        
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
        
        rng[0] = 3; // Will result in ticket #4 (USER2)
        
        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(requestId, rng);
        
        // Check USER2 now has unclaimed win
        (unclaimed, claimed) = raffle.getUserWinningStatus(USER2);
        assertEq(unclaimed.length, 1);
        assertEq(unclaimed[0], 2);
    }
}


