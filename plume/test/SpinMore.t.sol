// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../src/spin/Spin.sol";
import "../src/spin/DateTime.sol";
import "forge-std/Test.sol";

/// @notice Stub for Supra VRF
contract StubSupra {
    event RequestSent(uint256 indexed nonce);
    uint256 private next = 1;
    function generateRequest(
        string calldata, uint8, uint256, uint256, address
    ) external returns (uint256) {
        uint256 n = next++;
        emit RequestSent(n);
        return n;
    }
}

contract SpinContractTests is Test {
    Spin public spin;
    DateTime public dt;
    StubSupra public vrfStub;

    address constant ADMIN = address(0x1);
    address payable constant USER = payable(address(0x2));
    address constant SUPRA = address(0x6D46C098996AD584c9C40D6b4771680f54cE3726);

    /// @dev Deploy and initialize Spin
    function setUp() public {
        // Deploy DateTime and set start point
        dt = new DateTime();
        vm.warp(dt.toTimestamp(2025, 4, 1, 0, 0, 0));

        // Deploy VRF stub and etch at SUPRA address
        vrfStub = new StubSupra();
        vm.etch(SUPRA, address(vrfStub).code);

        // Deploy Spin as ADMIN
        vm.prank(ADMIN);
        spin = new Spin();
        vm.prank(ADMIN);
        spin.initialize(SUPRA, address(dt));

        // Set campaign start date to now
        vm.prank(ADMIN);
        spin.setCampaignStartDate(block.timestamp);

        // Ensure spin is enabled
        vm.prank(ADMIN);
        spin.setEnableSpin(true);

        // Fund contract for payouts
        vm.deal(address(spin), 100 ether);
    }

    /// @notice startSpin should revert when enableSpin is false
    function testStartSpinDisabledReverts() public {
        vm.prank(ADMIN);
        spin.setEnableSpin(false);

        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(Spin.CampaignNotStarted.selector));
        spin.startSpin();
    }

    /// @notice Non-whitelisted daily cooldown enforcement
    function testDailyCooldownEnforced() public {
        // First spin
        vm.recordLogs();
        vm.prank(USER);
        spin.startSpin();
        
        Vm.Log[] memory logs = vm.getRecordedLogs();
        require(logs.length > 0, "No logs emitted");
        
        uint256 nonce = uint256(logs[0].topics[1]);
        uint256[] memory rng = new uint256[](1);
        rng[0] = 999_999;

        vm.prank(SUPRA);
        spin.handleRandomness(nonce, rng);

        // Attempt second spin same day
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(Spin.AlreadySpunToday.selector));
        spin.startSpin();
    }

    /// @notice Whitelisted users can spin multiple times a day
    function testWhitelistBypassesCooldown() public {
        // Whitelist USER
        vm.prank(ADMIN);
        spin.whitelist(USER);

        // First spin
        vm.recordLogs();
        vm.prank(USER);
        spin.startSpin();
        
        Vm.Log[] memory logs = vm.getRecordedLogs();
        require(logs.length > 0, "No logs emitted");
        
        // Check both events are emitted
        bool foundRequestSent = false;
        bool foundSpinRequested = false;
        uint256 nonce1 = 0;
        
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("RequestSent(uint256)")) {
                foundRequestSent = true;
                nonce1 = uint256(logs[i].topics[1]);
            }
            if (logs[i].topics[0] == keccak256("SpinRequested(uint256,address)")) {
                foundSpinRequested = true;
                assertEq(logs[i].topics[2], bytes32(uint256(uint160(address(USER)))), "User address in event doesn't match");
            }
        }
        
        assertTrue(foundRequestSent, "RequestSent event not emitted");
        assertTrue(foundSpinRequested, "SpinRequested event not emitted");
        
        // Complete first spin
        uint256[] memory rng = new uint256[](1);
        rng[0] = 999_999;
        vm.prank(SUPRA);
        spin.handleRandomness(nonce1, rng);

        // Second spin same day
        vm.recordLogs();
        vm.prank(USER);
        spin.startSpin();
        logs = vm.getRecordedLogs();
        
        // Check both events are emitted for second spin too
        foundRequestSent = false;
        foundSpinRequested = false;
        
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("RequestSent(uint256)")) {
                foundRequestSent = true;
            }
            if (logs[i].topics[0] == keccak256("SpinRequested(uint256,address)")) {
                foundSpinRequested = true;
                assertEq(logs[i].topics[2], bytes32(uint256(uint160(address(USER)))), "User address in event doesn't match");
            }
        }
        
        assertTrue(foundRequestSent, "RequestSent event not emitted for second spin");
        assertTrue(foundSpinRequested, "SpinRequested event not emitted for second spin");
    }

    /// @notice Pause and unpause behavior
    function testPauseUnpause() public {
        // Pause
        vm.prank(ADMIN);
        spin.pause();
        vm.prank(USER);
        vm.expectRevert();
        spin.startSpin();

        // Unpause
        vm.prank(ADMIN);
        spin.unpause();
        vm.prank(USER);
        vm.recordLogs();
        spin.startSpin();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        // Check both events are emitted
        bool foundRequestSent = false;
        bool foundSpinRequested = false;
        
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("RequestSent(uint256)")) {
                foundRequestSent = true;
            }
            if (logs[i].topics[0] == keccak256("SpinRequested(uint256,address)")) {
                foundSpinRequested = true;
                assertEq(logs[i].topics[2], bytes32(uint256(uint160(address(USER)))), "User address in event doesn't match");
            }
        }
        
        assertTrue(foundRequestSent, "RequestSent event not emitted after unpause");
        assertTrue(foundSpinRequested, "SpinRequested event not emitted after unpause");
    }

    /// @notice getWeeklyJackpot: before start and various weeks
    function testGetWeeklyJackpotRevertsWithoutStart() public {
        // Deploy fresh contract without setting start
        Spin fresh;
        vm.prank(ADMIN);
        fresh = new Spin();
        vm.prank(ADMIN);
        fresh.initialize(SUPRA, address(dt));

        vm.expectRevert(bytes("Campaign not started"));
        fresh.getWeeklyJackpot();
    }

    function testGetWeeklyJackpotValues() public {
        // week 0
        vm.warp(spin.getCampaignStartDate() + 3 days);
        (uint256 wk0, uint256 prize0, uint256 req0) = spin.getWeeklyJackpot();
        assertEq(wk0, 0);
        assertEq(prize0, 5000);
        assertEq(req0, 2);

        // week 5
        vm.warp(spin.getCampaignStartDate() + 5 * 7 days + 1 days);
        (uint256 wk5, uint256 prize5, uint256 req5) = spin.getWeeklyJackpot();
        assertEq(wk5, 5);
        assertEq(prize5, 20_000);
        assertEq(req5, 7);

        // week 12
        vm.warp(spin.getCampaignStartDate() + 12 * 7 days);
        (uint256 wk12, uint256 prize12, uint256 req12) = spin.getWeeklyJackpot();
        assertEq(wk12, 12);
        assertEq(prize12, 0);
        assertEq(req12, 0);
    }

    /// @notice currentStreak and _computeStreak behavior
    function testStreakComputationAcrossDays() public {
        // No previous spin => streak = 1
        assertEq(spin.currentStreak(USER), 1);

        // Spin day 1
        uint256 ts1 = block.timestamp;
        vm.recordLogs();
        vm.prank(USER);
        spin.startSpin();
        
        Vm.Log[] memory logs = vm.getRecordedLogs();
        require(logs.length > 0, "No logs emitted");
        
        uint256 nonce = uint256(logs[0].topics[1]);
        uint256[] memory rng = new uint256[](1);
        rng[0] = 999_999;
        
        vm.prank(SUPRA);
        spin.handleRandomness(nonce, rng);
        assertEq(spin.currentStreak(USER), 1);

        // Next day
        vm.warp(ts1 + 1 days + 1);
        assertEq(spin.currentStreak(USER), 2);

        // Skip a day
        vm.warp(ts1 + 3 days);
        assertEq(spin.currentStreak(USER), 1);
    }

    /// @notice updateRaffleTickets onlyRaffleContract
    function testUpdateRaffleTicketsAccessAndEffect() public {
        // Whitelist and give a ticket via RNG
        vm.prank(ADMIN);
        spin.whitelist(USER);
        
        vm.recordLogs();
        vm.prank(USER);
        spin.startSpin();
        
        Vm.Log[] memory logs = vm.getRecordedLogs();
        require(logs.length > 0, "No logs emitted");
        
        uint256 nonce = uint256(logs[0].topics[1]);
        uint256[] memory rng = new uint256[](1);
        rng[0] = 300_000;
        
        vm.prank(SUPRA);
        spin.handleRandomness(nonce, rng);
        
        // raffleTicketsBalance should be 8
        (, , , , uint256 bal, , ) = spin.getUserData(USER);
        assertEq(bal, 8);

        // Set this contract as raffleContract
        vm.prank(ADMIN);
        spin.setRaffleContract(address(this));

        // Expect event and new balance
        vm.recordLogs();
        spin.updateRaffleTickets(USER, 3);
        Vm.Log[] memory L = vm.getRecordedLogs();
        assertEq(L[0].topics[0], keccak256("RaffleTicketsUpdated(address,uint256,uint256)"));
        (, , , , uint256 newBal, , ) = spin.getUserData(USER);
        assertEq(newBal, 5);

        // Non-raffleContract caller should revert
        vm.prank(USER);
        vm.expectRevert();
        spin.updateRaffleTickets(USER, 1);
    }

    /// @notice withdraw flows and reverts
    function testWithdrawSuccessAndFailures() public {
        // Ensure contract has 100 ether
        assertEq(address(spin).balance, 100 ether);

        // Non-admin cannot withdraw
        vm.prank(USER);
        vm.expectRevert();
        spin.withdraw(USER, 1 ether);

        // Zero address fails
        vm.prank(ADMIN);
        vm.expectRevert(bytes("Invalid recipient address"));
        spin.withdraw(payable(address(0)), 1 ether);

        // Too much fails
        vm.prank(ADMIN);
        vm.expectRevert(bytes("Insufficient contract balance"));
        spin.withdraw(payable(ADMIN), 200 ether);

        // Successful
        vm.prank(ADMIN);
        spin.withdraw(payable(USER), 50 ether);
        assertEq(address(spin).balance, 50 ether);
        assertEq(USER.balance, 50 ether);
    }

    /// @notice handleRandomness should revert when called by non-SUPRA address
    function testHandleRandomnessAccessControl() public {
        vm.recordLogs();
        vm.prank(USER);
        spin.startSpin();
        
        Vm.Log[] memory logs = vm.getRecordedLogs();
        require(logs.length > 0, "No logs emitted");
        
        // Create a dummy nonce that will be considered valid
        uint256 nonce = 1;
        vm.mockCall(
            SUPRA,
            abi.encodeWithSelector(StubSupra.generateRequest.selector),
            abi.encode(nonce)
        );
        
        uint256[] memory rng = new uint256[](1);
        rng[0] = 999_999;
        
        // Call from non-SUPRA address should revert with access control
        vm.prank(USER);
        vm.expectRevert(); // Just expect a generic revert since error name might change
        spin.handleRandomness(nonce, rng);
    }

    /// @notice handleRandomness should revert with InvalidNonce for bogus nonce
    function testHandleRandomnessInvalidNonce() public {
        uint256[] memory rng = new uint256[](1);
        rng[0] = 999_999;
        
        // Bogus nonce should revert
        vm.prank(SUPRA);
        vm.expectRevert(abi.encodeWithSelector(Spin.InvalidNonce.selector));
        spin.handleRandomness(999, rng);
    }

    /// @notice Test Insufficient balance for jackpot payout
    function testInsufficientBalanceForPayout() public {
        // Empty the contract first
        vm.prank(ADMIN);
        spin.withdraw(payable(ADMIN), 100 ether);
        
        // Now use whitelisted user to get jackpot
        vm.prank(ADMIN);
        spin.whitelist(USER);
        
        // We need to set the streak high enough to win jackpot
        // Jump to a point where we're still in week 0
        uint256 startTs = spin.getCampaignStartDate();
        vm.warp(startTs + 1 days);
        
        // We need streak of 2 for week 0 jackpot
        // First spin to build history
        vm.recordLogs();
        vm.prank(USER);
        spin.startSpin();
        uint256 nonce1 = uint256(vm.getRecordedLogs()[0].topics[1]);
        uint256[] memory rng1 = new uint256[](1);
        rng1[0] = 900_000; // Something other than jackpot
        vm.prank(SUPRA);
        spin.handleRandomness(nonce1, rng1);
        
        // Move to next day and spin again to build streak
        vm.warp(startTs + 2 days);
        vm.recordLogs();
        vm.prank(USER);
        spin.startSpin();
        uint256 nonce2 = uint256(vm.getRecordedLogs()[0].topics[1]);
        uint256[] memory rng2 = new uint256[](1);
        rng2[0] = 900_000; // Something other than jackpot
        vm.prank(SUPRA);
        spin.handleRandomness(nonce2, rng2);
        
        // Now we have streak of 2, wait for next day and try jackpot
        vm.warp(startTs + 3 days);
        
        // Verify the streak is 3 now
        assertEq(spin.currentStreak(USER), 3, "User streak should be 3 at this point");
        
        // Now try for jackpot with a jackpot-winning RNG
        vm.recordLogs();
        vm.prank(USER);
        spin.startSpin();
        uint256 nonce3 = uint256(vm.getRecordedLogs()[0].topics[1]);
        uint256[] memory rngJackpot = new uint256[](1);
        rngJackpot[0] = 0; // Force jackpot win
        
        // Should revert with insufficient balance
        vm.prank(SUPRA);
        vm.expectRevert(bytes("insufficient Plume in the Spin contract"));
        spin.handleRandomness(nonce3, rngJackpot);
    }

    /// @notice Test getUserData after sequence of spins
    function testGetUserDataAfterSpins() public {
        // Initial check
        (uint256 streak0, uint256 lastSpin0, uint256 jackpotWins0, 
         uint256 raffleGained0, uint256 raffleBalance0, 
         uint256 ppGained0, uint256 plumeTokens0) = spin.getUserData(USER);
        
        assertEq(streak0, 1, "Initial streak should be 1");
        assertEq(lastSpin0, 0, "Initial lastSpin should be 0");
        assertEq(jackpotWins0, 0, "Initial jackpotWins should be 0");
        assertEq(raffleGained0, 0, "Initial raffleGained should be 0");
        assertEq(raffleBalance0, 0, "Initial raffleBalance should be 0");
        assertEq(ppGained0, 0, "Initial ppGained should be 0");
        assertEq(plumeTokens0, 0, "Initial plumeTokens should be 0");
        
        // Day 1: PP reward
        vm.recordLogs();
        vm.prank(USER);
        spin.startSpin();
        uint256 nonce1 = uint256(vm.getRecordedLogs()[0].topics[1]);
        uint256[] memory rng1 = new uint256[](1);
        rng1[0] = 700_000; // PP reward
        
        // Timestamp for this spin
        uint256 ts1 = block.timestamp;
        
        vm.prank(SUPRA);
        spin.handleRandomness(nonce1, rng1);
        
        (uint256 streak1, uint256 lastSpin1, , , , uint256 ppGained1, ) = spin.getUserData(USER);
        assertEq(streak1, 1, "Streak should be 1 after first spin");
        assertEq(lastSpin1, ts1, "LastSpin should match spin timestamp");
        assertEq(ppGained1, 100, "PP gained should be 100");
        
        // Day 2: Raffle reward
        vm.warp(ts1 + 1 days);
        vm.recordLogs();
        vm.prank(USER);
        spin.startSpin();
        uint256 nonce2 = uint256(vm.getRecordedLogs()[0].topics[1]);
        uint256[] memory rng2 = new uint256[](1);
        rng2[0] = 300_000; // Raffle ticket reward
        
        // Timestamp for this spin
        uint256 ts2 = block.timestamp;
        
        vm.prank(SUPRA);
        spin.handleRandomness(nonce2, rng2);
        
        (uint256 streak2, uint256 lastSpin2, , uint256 raffleGained2, 
         uint256 raffleBalance2, uint256 ppGained2, ) = spin.getUserData(USER);
        
        assertEq(streak2, 2, "Streak should be 2 after consecutive spin");
        assertEq(lastSpin2, ts2, "LastSpin should update to latest spin");
        assertEq(raffleGained2, 8 * 2, "RaffleGained should be baseMultiplier * (streak + 1)");
        assertEq(raffleBalance2, raffleGained2, "RaffleBalance should equal raffleGained");
        assertEq(ppGained2, 100, "PP gained should remain 100");
    }

    /// @notice Test all setter/getter combinations
    function testSettersAndGetters() public {
        // Test jackpot probabilities
        vm.prank(ADMIN);
        uint8[7] memory newProbs = [10, 20, 30, 40, 50, 60, 70];
        spin.setJackpotProbabilities(newProbs);
        
        // Test jackpot prize
        vm.prank(ADMIN);
        spin.setJackpotPrizes(5, 100_000);
        
        // Test raffle multiplier
        vm.prank(ADMIN);
        spin.setBaseRaffleMultiplier(10);
        
        // Test PP per spin
        vm.prank(ADMIN);
        spin.setPP_PerSpin(200);
        
        // Test plume amounts
        vm.prank(ADMIN);
        uint256[3] memory newPlume = [uint256(2), uint256(3), uint256(4)];
        spin.setPlumeAmounts(newPlume);
        
        // Verify these changes affected rewards
        vm.prank(ADMIN);
        spin.whitelist(USER);
        
        // Test PP reward affected by setPP_PerSpin
        vm.recordLogs();
        vm.prank(USER);
        spin.startSpin();
        uint256 nonce1 = uint256(vm.getRecordedLogs()[0].topics[1]);
        uint256[] memory rng1 = new uint256[](1);
        rng1[0] = 700_000; // PP reward
        
        vm.prank(SUPRA);
        spin.handleRandomness(nonce1, rng1);
        
        (, , , , , uint256 ppGained, ) = spin.getUserData(USER);
        assertEq(ppGained, 200, "PP gained should match new setPP_PerSpin value");
        
        // Test raffle multiplier
        vm.warp(block.timestamp + 1 days);
        vm.recordLogs();
        vm.prank(USER);
        spin.startSpin();
        uint256 nonce2 = uint256(vm.getRecordedLogs()[0].topics[1]);
        uint256[] memory rng2 = new uint256[](1);
        rng2[0] = 300_000; // Raffle ticket
        
        vm.prank(SUPRA);
        spin.handleRandomness(nonce2, rng2);
        
        (, , , uint256 raffleGained, uint256 raffleBalance, , ) = spin.getUserData(USER);
        // Check the actual values first before asserting
        // baseMultiplier * (streak + 1) = 10 * (2) = 20, plus 0 previous tickets
        assertEq(raffleGained, 20, "Raffle tickets gained should be 20");
        assertEq(raffleBalance, 20, "Raffle balance should be 20");
    }

    /// @notice Test view functions for contract state
    function testViewFunctions() public {
        // getCampaignStartDate
        uint256 startDate = spin.getCampaignStartDate();
        assertEq(startDate, block.timestamp, "Campaign start date should match initialization");
        
        // getContractBalance
        uint256 balance = spin.getContractBalance();
        assertEq(balance, 100 ether, "Contract balance should match funded amount");
        
        // getWeeklyJackpot
        (uint256 week, uint256 prize, uint256 requiredStreak) = spin.getWeeklyJackpot();
        assertEq(week, 0, "Should be week 0 initially");
        assertEq(prize, 5000, "Default prize for week 0 should be 5000");
        assertEq(requiredStreak, 2, "Required streak for week 0 should be 2");
    }
}
