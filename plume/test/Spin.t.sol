// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./TestUtils.sol";

import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { console2 } from "forge-std/console2.sol";

contract SpinTest is SpinTestBase {

    uint256 constant COOLDOWN_PERIOD = 86_400; // 1 day
    uint8 constant RNG_COUNT = 1;
    uint256 constant NUM_CONFIRMATIONS = 1;
    mapping(bytes32 => uint256) public prizeCounts;
    uint256 public constant INITIAL_SPIN_PRICE = 2 ether;

    function setUp() public {
        // Set up spin with date March 8, 2025 10:00:00

        setupSpin(2025, 3, 8, 10, 0, 0);
    }

    /// @notice startSpin happy case test for a spin
    function testStartSpin() public {
        vm.recordLogs();

        // Move to March 10
        vm.warp(dateTime.toTimestamp(2025, 3, 10, 10, 0, 0));
        vm.prank(USER);
        vm.deal(USER, INITIAL_SPIN_PRICE); // Deal funds
        spin.startSpin{ value: INITIAL_SPIN_PRICE }(); // Send value

        // Expect emit Spin requested
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 2, "No logs emitted");

        assertEq(entries[1].topics[0], keccak256("SpinRequested(uint256,address)"), "SpinRequested event not emitted");
        assertEq(entries[1].topics[2], bytes32(uint256(uint160(address(USER)))), "User address incorrect");

        uint256 nonce = uint256(entries[0].topics[1]);
        emit log_named_uint("Extracted Nonce", nonce);

        assertGt(nonce, 0, "Nonce should be greater than 0");
    }

    /// @notice startSpin should revert if incorrect amount is sent
    function testStartSpinIncorrectPaymentReverts() public {
        vm.prank(USER);
        vm.expectRevert(bytes("Incorrect spin price sent"));
        spin.startSpin{ value: 1 ether }();

        vm.prank(USER);
        vm.expectRevert(bytes("Incorrect spin price sent"));
        spin.startSpin{ value: 3 ether }();
    }

    /// @notice startSpin should succeed with correct payment
    function testStartSpinCorrectPayment() public {
        vm.recordLogs();
        vm.prank(USER);
        vm.deal(USER, INITIAL_SPIN_PRICE); // Fund the user
        spin.startSpin{ value: INITIAL_SPIN_PRICE }();

        // Expect emit Spin requested
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 2, "Incorrect log count");
        assertEq(entries[1].topics[0], keccak256("SpinRequested(uint256,address)"), "SpinRequested event not emitted");
        assertEq(entries[1].topics[2], bytes32(uint256(uint160(address(USER)))), "User address incorrect");
    }

    /// @notice startSpinDisabledReverts should check payment even when disabled
    function testStartSpinDisabledRevertsWithPayment() public {
        vm.prank(ADMIN);
        spin.setEnableSpin(false);

        // Even though disabled, it should ideally check payment first if applicable,
        // but current logic checks enableSpin first. Let's test that revert.
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(Spin.CampaignNotStarted.selector));
        spin.startSpin{ value: INITIAL_SPIN_PRICE }();
    }

    /// @notice Non-whitelisted daily spin limit enforcement
    function testDailySpinLimitEnforced() public {
        // First spin
        vm.deal(USER, INITIAL_SPIN_PRICE);
        uint256 nonce = performPaidSpin(USER); // Use paid spin
        completeSpin(nonce, 999_999);

        // Attempt second spin same day
        vm.prank(USER);
        vm.deal(USER, INITIAL_SPIN_PRICE); // Deal funds even for expected revert
        vm.expectRevert(abi.encodeWithSelector(Spin.AlreadySpunToday.selector));
        spin.startSpin{ value: INITIAL_SPIN_PRICE }(); // Call with value
    }

    /// @notice Whitelisted users can spin multiple times a day
    function testWhitelistBypassesCooldown() public {
        // Whitelist USER
        vm.prank(ADMIN);
        spin.whitelist(USER);

        // First spin (whitelisted)
        vm.deal(USER, INITIAL_SPIN_PRICE);
        uint256 nonce1 = performPaidSpin(USER); // Use paid spin
        completeSpin(nonce1, 999_999);

        // Second spin same day (whitelisted)
        vm.recordLogs();
        vm.prank(USER);
        vm.deal(USER, INITIAL_SPIN_PRICE);
        spin.startSpin{ value: INITIAL_SPIN_PRICE }(); // Whitelisted user pays
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Verify second spin request was successful
        bool foundSpinRequested = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("SpinRequested(uint256,address)")) {
                foundSpinRequested = true;
                assertEq(
                    logs[i].topics[2], bytes32(uint256(uint160(address(USER)))), "User address in event doesn't match"
                );
                break;
            }
        }

        assertTrue(foundSpinRequested, "SpinRequested event not emitted for second spin");
    }

    /// @notice Removing a user from the whitelist restores the daily spin limit
    function testRemoveWhitelistRestoresCooldown() public {
        // 1. Whitelist USER
        vm.prank(ADMIN);
        spin.whitelist(USER);

        // 2. Perform first spin (should succeed)
        vm.deal(USER, INITIAL_SPIN_PRICE);
        uint256 nonce1 = performPaidSpin(USER);
        completeSpin(nonce1, 999_999);

        // 3. Perform second spin while whitelisted (should succeed)
        vm.deal(USER, INITIAL_SPIN_PRICE);
        uint256 nonce2 = performPaidSpin(USER);
        assertTrue(nonce2 > 0, "Second spin should succeed while whitelisted");

        // 4. Remove user from whitelist
        vm.prank(ADMIN);
        spin.removeWhitelist(USER);

        // 5. Attempt third spin on the same day (should fail)
        vm.prank(USER);
        vm.deal(USER, INITIAL_SPIN_PRICE);
        vm.expectRevert(abi.encodeWithSelector(Spin.AlreadySpunToday.selector));
        spin.startSpin{ value: INITIAL_SPIN_PRICE }();
    }

    /// @notice Pause and unpause behavior
    function testPauseUnpause() public {
        // Pause
        vm.prank(ADMIN);
        spin.pause();
        vm.prank(USER);
        vm.deal(USER, INITIAL_SPIN_PRICE);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector)); // Correct way to get error
            // selector
        spin.startSpin{ value: INITIAL_SPIN_PRICE }();

        // Unpause
        vm.prank(ADMIN);
        spin.unpause();
        vm.prank(USER);
        vm.deal(USER, INITIAL_SPIN_PRICE);
        vm.recordLogs();
        spin.startSpin{ value: INITIAL_SPIN_PRICE }();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // With the real Supra Oracle integration, we only need to check for SpinRequested event
        bool foundSpinRequested = false;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("SpinRequested(uint256,address)")) {
                foundSpinRequested = true;
                assertEq(
                    logs[i].topics[2], bytes32(uint256(uint160(address(USER)))), "User address in event doesn't match"
                );
            }
        }

        assertTrue(foundSpinRequested, "SpinRequested event not emitted after unpause");

        // Make ADMIN the default sender for setup calls
        vm.startPrank(ADMIN);
        vm.stopPrank(); // Stop the persistent prank after setup
    }

    /// @notice getWeeklyJackpot: before start and various weeks
    function testGetWeeklyJackpotRevertsWithoutStart() public {
        // Deploy fresh contract without setting start
        Spin fresh;
        vm.prank(ADMIN);
        fresh = new Spin();
        vm.prank(ADMIN);
        fresh.initialize(SUPRA_ORACLE, address(dateTime));

        vm.expectRevert(bytes("Campaign not started"));
        fresh.getWeeklyJackpot();
    }

    /// @notice getWeeklyJackpot: test weekly jackpot values across weeks works. NOTE: hardcoded values, brittle test
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

    /// @notice currentStreak computations
    function testStreakComputationAcrossDays() public {
        // No previous spin => streak = 0
        assertEq(spin.currentStreak(USER), 0);

        // Spin day 1
        uint256 ts1 = block.timestamp;
        vm.deal(USER, INITIAL_SPIN_PRICE);
        uint256 nonce1 = performPaidSpin(USER); // Use paid spin
        completeSpin(nonce1, 999_999); // Complete spin for day 1
        // after first spin, streak = 1
        assertEq(spin.currentStreak(USER), 1);

        // Next day (Day 2)
        vm.warp(ts1 + 1 days);
        // next day, no spin yet, streak = 1 (correctly reflects last spin's effect)
        assertEq(spin.currentStreak(USER), 1);
        // Spin again on Day 2
        vm.deal(USER, INITIAL_SPIN_PRICE);
        uint256 nonce2 = performPaidSpin(USER); // Use paid spin
        completeSpin(nonce2, 999_999); // Complete spin for day 2
        // next day, spin again, streak = 2
        assertEq(spin.currentStreak(USER), 2);

        // Skip a day (Go to Day 4)
        vm.warp(ts1 + 3 days);
        // skip a day, no spin yet, streak = 0 (broken streak)
        assertEq(spin.currentStreak(USER), 0);
        // Spin again on Day 4
        vm.deal(USER, INITIAL_SPIN_PRICE);
        uint256 nonce3 = performPaidSpin(USER); // Use paid spin
        completeSpin(nonce3, 999_999); // Complete spin for day 4
        // skip a day, spin again, streak = 1
        assertEq(spin.currentStreak(USER), 1);
    }

    /// @notice spendRaffleTickets onlyRaffleContract
    function testspendRaffleTicketsAccessAndEffect() public {
        // Whitelist and give a ticket via RNG
        vm.prank(ADMIN);
        spin.whitelist(USER);

        vm.deal(USER, INITIAL_SPIN_PRICE);
        uint256 nonce = performPaidSpin(USER);
        completeSpin(nonce, 300_000); // Raffle ticket reward

        // raffleTicketsBalance should be 8
        (,,,, uint256 bal,,) = spin.getUserData(USER);
        assertEq(bal, 8);

        // Set this contract as raffleContract
        vm.prank(ADMIN);
        spin.setRaffleContract(address(this));

        // Expect event and new balance
        vm.recordLogs();
        spin.spendRaffleTickets(USER, 3);
        Vm.Log[] memory L = vm.getRecordedLogs();
        assertEq(L[0].topics[0], keccak256("RaffleTicketsSpent(address,uint256,uint256)"));
        (,,,, uint256 newBal,,) = spin.getUserData(USER);
        assertEq(newBal, 5);

        // Non-raffleContract caller should revert
        vm.prank(USER);
        vm.expectRevert();
        spin.spendRaffleTickets(USER, 1);
    }

    /// @notice Plume adminWithdraw flows and reverts (testing renamed function)
    function testAdminWithdrawSuccessAndFailures() public {
        // Ensure contract has 100 plume initially + 2 from spin price test
        uint256 initialBalance = address(spin).balance;
        // Perform a paid spin to add funds
        vm.prank(USER);
        spin.startSpin{ value: INITIAL_SPIN_PRICE }();
        // Balance should increase by spin price
        assertEq(address(spin).balance, initialBalance + INITIAL_SPIN_PRICE, "Balance did not increase after paid spin");
        uint256 currentBalance = address(spin).balance;

        // Non-admin cannot withdraw
        vm.prank(USER);
        vm.expectRevert();
        spin.adminWithdraw(USER, 1 ether);

        // Zero address fails
        vm.prank(ADMIN);
        vm.expectRevert(bytes("Invalid recipient address"));
        spin.adminWithdraw(payable(address(0)), 1 ether);

        // Too much fails on balance check
        vm.prank(ADMIN);
        vm.expectRevert(bytes("insufficient Plume in the Spin contract"));
        spin.adminWithdraw(payable(ADMIN), currentBalance + 1 ether);

        // Successful
        uint256 withdrawAmount = 50 ether;
        uint256 userInitialBalance = USER.balance;
        vm.prank(ADMIN);
        spin.adminWithdraw(payable(USER), withdrawAmount);
        assertEq(address(spin).balance, currentBalance - withdrawAmount, "Contract balance incorrect after withdraw");
        assertEq(USER.balance, userInitialBalance + withdrawAmount, "User balance incorrect after withdraw");
    }

    /// NOTE: SUCCESSFUL handleRandomness for complex case at end of test file

    /// @notice handleRandomness should revert when called by non-SUPRA_ORACLE address
    function testHandleRandomnessAccessControl() public {
        uint256 nonce = performPaidSpin(USER); // Use paid spin

        // Create a dummy nonce that will be considered valid
        vm.mockCall(SUPRA_ORACLE, abi.encodeWithSelector(ArbSysMock.arbBlockNumber.selector), abi.encode(nonce));

        uint256[] memory rng = new uint256[](1);
        rng[0] = 999_999;

        // Call from non-SUPRA_ORACLE address should revert with access control
        vm.prank(USER);
        vm.expectRevert(); // Generic revert check is okay for access control
        spin.handleRandomness(nonce, rng);
    }

    /// @notice handleRandomness should revert with InvalidNonce for bogus nonce
    function testHandleRandomnessInvalidNonce() public {
        uint256[] memory rng = new uint256[](1);
        rng[0] = 999_999;

        // Bogus nonce should revert
        vm.prank(SUPRA_ORACLE);
        vm.expectRevert(abi.encodeWithSelector(Spin.InvalidNonce.selector));
        spin.handleRandomness(999, rng);
    }

    /// @notice Test Insufficient balance for jackpot payout
    function testInsufficientBalanceForPayout() public {
        // Empty the contract first
        vm.prank(ADMIN);
        spin.adminWithdraw(payable(ADMIN), address(spin).balance);
        assertEq(address(spin).balance, 0, "Contract should be empty");

        // Add spin price back for user to pay
        vm.deal(USER, INITIAL_SPIN_PRICE);

        // Now set up user to get jackpot
        vm.prank(ADMIN);

        // We need to set the streak high enough to win jackpot
        // Jump to a point where we're still in week 0
        uint256 startTs = spin.getCampaignStartDate();
        vm.warp(startTs + 1 days);

        // We need streak of 2 for week 0 jackpot
        // First spin to build history
        vm.deal(USER, INITIAL_SPIN_PRICE);
        uint256 nonce1 = performPaidSpin(USER); // Use paid spin
        completeSpin(nonce1, 900_000); // Something other than jackpot

        // Move to next day and spin again to build streak
        vm.warp(startTs + 2 days);
        vm.deal(USER, INITIAL_SPIN_PRICE);
        uint256 nonce2 = performPaidSpin(USER); // Use paid spin
        completeSpin(nonce2, 900_000); // Something other than jackpot

        assertEq(spin.currentStreak(USER), 2, "User streak should be 2 at this point");

        // Now we have streak of 2, wait for next day and try jackpot
        vm.warp(startTs + 3 days);

        // Now try for jackpot with a jackpot-winning RNG
        vm.deal(USER, INITIAL_SPIN_PRICE);
        uint256 nonce3 = performPaidSpin(USER); // Use paid spin
        uint256[] memory rngJackpot = new uint256[](1);
        rngJackpot[0] = 0; // Force jackpot win

        // Should revert with insufficient balance
        vm.prank(SUPRA_ORACLE);
        vm.expectRevert(bytes("insufficient Plume in the Spin contract"));
        spin.handleRandomness(nonce3, rngJackpot);
    }

    /// @notice Test getUserData after sequence of spins
    function testGetUserDataAfterSpins() public {
        // Initial check
        (
            uint256 streak0,
            uint256 lastSpin0,
            uint256 jackpotWins0,
            uint256 raffleGained0,
            uint256 raffleBalance0,
            uint256 ppGained0,
            uint256 plumeTokens0
        ) = spin.getUserData(USER);

        assertEq(streak0, 0, "Initial streak should be 0");
        assertEq(lastSpin0, 0, "Initial lastSpin should be 0");
        assertEq(jackpotWins0, 0, "Initial jackpotWins should be 0");
        assertEq(raffleGained0, 0, "Initial raffleGained should be 0");
        assertEq(raffleBalance0, 0, "Initial raffleBalance should be 0");
        assertEq(ppGained0, 0, "Initial ppGained should be 0");
        assertEq(plumeTokens0, 0, "Initial plumeTokens should be 0");

        // Day 1: PP reward (with payment)
        vm.deal(USER, INITIAL_SPIN_PRICE); // Give user funds to spin
        uint256 nonce1 = performPaidSpin(USER);
        uint256[] memory rng1 = new uint256[](1);
        rng1[0] = 700_000; // PP reward

        // Timestamp for this spin
        uint256 ts1 = block.timestamp;

        vm.prank(SUPRA_ORACLE);
        spin.handleRandomness(nonce1, rng1);
        console2.log("USER", USER);
        vm.prank(USER);
        (uint256 streak1, uint256 lastSpin1,,,, uint256 ppGained1,) = spin.getUserData(USER);
        assertEq(streak1, 1, "Streak should be 1 after first spin");
        assertEq(lastSpin1, ts1, "LastSpin should match spin timestamp");
        assertEq(ppGained1, 100, "PP gained should be 100");

        // Day 2: Raffle reward
        vm.warp(ts1 + 1 days);
        vm.deal(USER, INITIAL_SPIN_PRICE);
        uint256 nonce2 = performPaidSpin(USER);
        uint256[] memory rng2 = new uint256[](1);
        rng2[0] = 300_000; // Raffle ticket reward

        // Timestamp for this spin
        uint256 ts2 = block.timestamp;

        vm.prank(SUPRA_ORACLE);
        spin.handleRandomness(nonce2, rng2);

        (uint256 streak2, uint256 lastSpin2,, uint256 raffleGained2, uint256 raffleBalance2, uint256 ppGained2,) =
            spin.getUserData(USER);

        assertEq(streak2, 2, "Streak should be 2 after consecutive spin");
        assertEq(lastSpin2, ts2, "LastSpin should update to latest spin");
        assertEq(raffleGained2, 8 * 2, "RaffleGained should be baseMultiplier * (streak + 1)");
        assertEq(raffleBalance2, raffleGained2, "RaffleBalance should equal raffleGained");
        assertEq(ppGained2, 100, "PP gained should remain 100");
    }

    /// @notice Test that jackpot probabilities can be updated and affect rewards
    function testSetJackpotProbabilitiesImpact() public {
        // 1. Set all jackpot probabilities to 0 - effectively disabling jackpot wins
        vm.prank(ADMIN);
        uint8[7] memory zeroProbabilities = [0, 0, 0, 0, 0, 0, 0];
        spin.setJackpotProbabilities(zeroProbabilities);

        // Fund contract
        vm.deal(address(spin), 10_000 ether);
        uint256 currentPrice = spin.getSpinPrice();

        // Day 0, streak=0 => Not enough streak for jackpot
        vm.deal(USER, currentPrice);
        uint256 n0 = performPaidSpin(USER);
        uint256[] memory r0 = new uint256[](1);
        r0[0] = 600_000;

        vm.prank(SUPRA_ORACLE);
        spin.handleRandomness(n0, r0);

        // Day 1, streak=1 => Still Not enough streak
        vm.warp(block.timestamp + 1 days);
        vm.deal(USER, currentPrice);
        uint256 n1 = performPaidSpin(USER);
        uint256[] memory r00 = new uint256[](1);
        r00[0] = 600_000;

        vm.prank(SUPRA_ORACLE);
        spin.handleRandomness(n1, r00);

        // Day 2, streak=2 => Now enough streak for jackpot

        vm.warp(block.timestamp + 1 days);
        vm.deal(USER, currentPrice);
        uint256 n2 = performPaidSpin(USER);
        uint256[] memory r000 = new uint256[](1);
        r000[0] = 600_000;

        vm.prank(SUPRA_ORACLE);
        spin.handleRandomness(n2, r000);

        // Now we have enough streak for jackpot

        vm.warp(block.timestamp + 1 days);

        // Try to get jackpot with randomness=0 (which would normally trigger jackpot)
        vm.deal(USER, currentPrice);
        uint256 nonce1 = performPaidSpin(USER);
        uint256[] memory r1 = new uint256[](1);
        r1[0] = 0; // normally would be jackpot

        vm.prank(SUPRA_ORACLE);
        vm.recordLogs();
        spin.handleRandomness(nonce1, r1);

        // Get the SpinCompleted event
        Vm.Log[] memory logs1 = vm.getRecordedLogs();
        (string memory category1, uint256 amount1) = abi.decode(logs1[0].data, (string, uint256));

        // Since jackpot probability is 0, we should get Plume Token instead
        assertEq(category1, "Plume Token", "Should not get Jackpot when probability is 0");

        // 2. Now set a very high jackpot probability for all days
        vm.prank(ADMIN);
        uint8[7] memory highProbabilities = [250, 250, 250, 250, 250, 250, 250];
        spin.setJackpotProbabilities(highProbabilities);

        // We should now get jackpot even with higher randomness
        vm.warp(block.timestamp + 1 days);
        vm.deal(USER, currentPrice);
        uint256 nonce2 = performPaidSpin(USER);
        uint256[] memory r2 = new uint256[](1);
        r2[0] = 200; // value that would normally be Plume Token

        vm.prank(SUPRA_ORACLE);
        vm.recordLogs();
        spin.handleRandomness(nonce2, r2);

        // Get the SpinCompleted event
        Vm.Log[] memory logs2 = vm.getRecordedLogs();
        (string memory category2, uint256 amount2) = abi.decode(logs2[0].data, (string, uint256));

        // Since jackpot probability is now high, we should get Jackpot
        assertEq(category2, "Jackpot", "Should get Jackpot when probability is high");
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

    /// @notice Test that "Nothing" reward counts for streak
    function testNothingKeepsStreakAlive() public {
        vm.deal(USER, INITIAL_SPIN_PRICE);
        uint256 nonce = performPaidSpin(USER); // Use paid spin

        uint256[] memory rng = new uint256[](1);
        rng[0] = 950_000; // >900k = Nothing

        vm.prank(SUPRA_ORACLE);
        vm.recordLogs();
        spin.handleRandomness(nonce, rng);
        Vm.Log[] memory L = vm.getRecordedLogs();

        (string memory cat, uint256 amt) = abi.decode(L[0].data, (string, uint256));
        assertEq(cat, "Nothing");
        assertEq(amt, 0);

        (uint256 streak,,,,,,) = spin.getUserData(USER);
        assertEq(streak, 1);
    }

    /// @notice Test that a broken streak results in a recalculated (lower) raffle ticket reward
    function testBrokenStreakRaffleReward() public {
        // Day 1: Spin to get streak to 1
        vm.deal(USER, INITIAL_SPIN_PRICE);
        uint256 nonce1 = performPaidSpin(USER);
        completeSpin(nonce1, 999_999); // "Nothing" reward
        assertEq(spin.currentStreak(USER), 1, "Streak should be 1 after day 1");

        // Day 2: Spin to get streak to 2
        vm.warp(block.timestamp + 1 days);
        vm.deal(USER, INITIAL_SPIN_PRICE);
        uint256 nonce2 = performPaidSpin(USER);
        completeSpin(nonce2, 999_999);
        assertEq(spin.currentStreak(USER), 2, "Streak should be 2 after day 2");

        // Day 4: Skip a day, breaking the streak
        vm.warp(block.timestamp + 2 days);
        
        // Sanity check: streak is now 0 before the spin
        assertEq(spin.currentStreak(USER), 0, "Streak should be 0 after breaking");

        // Spin and get a raffle ticket reward
        vm.deal(USER, INITIAL_SPIN_PRICE);
        uint256 nonce3 = performPaidSpin(USER);
        
        uint256[] memory rng = new uint256[](1);
        rng[0] = 300_000; // Raffle Ticket reward

        vm.prank(SUPRA_ORACLE);
        vm.recordLogs();
        spin.handleRandomness(nonce3, rng);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // The reward amount should be based on the new streak of 1 (baseRaffleMultiplier * 1)
        (string memory category, uint256 amount) = abi.decode(logs[0].data, (string, uint256));
        assertEq(category, "Raffle Ticket", "Reward should be Raffle Ticket");
        assertEq(amount, spin.baseRaffleMultiplier() * 1, "Reward amount should be based on a streak of 1");
        
        // Check final user state
        (uint256 finalStreak, , , uint256 raffleGained, uint256 raffleBalance, , ) = spin.getUserData(USER);
        assertEq(finalStreak, 1, "Final streak should be 1");
        assertEq(raffleGained, spin.baseRaffleMultiplier(), "Total raffle tickets gained should be based on streak of 1");
    }

    /// @notice Test jackpot payout with insufficient then sufficient streak
    function testJackpotInsufficientThenSufficientStreak() public {
        // Make sure contract has enough balance for jackpot payouts
        vm.deal(address(spin), 10_000 ether);
        uint256 currentPrice = spin.getSpinPrice();

        // Day 0, streak=1 => Not enough streak for jackpot
        vm.deal(USER, currentPrice);
        uint256 n0 = performPaidSpin(USER); // Use paid spin
        uint256[] memory r0 = new uint256[](1);
        r0[0] = 0; // force jackpot

        vm.prank(SUPRA_ORACLE);
        vm.recordLogs();
        spin.handleRandomness(n0, r0);
        Vm.Log[] memory L0 = vm.getRecordedLogs();

        // Log[0] = NotEnoughStreak, Log[1] = SpinCompleted
        assertEq(L0[0].topics[0], keccak256("NotEnoughStreak(string)"), "NotEnoughStreak event not emitted");
        // Check the SpinCompleted event
        (string memory cat0, uint256 amt0) = abi.decode(L0[1].data, (string, uint256));
        assertEq(cat0, "Nothing");
        assertEq(amt0, 0);

        // Day 1, streak=1 => Still Not enough streak
        vm.warp(block.timestamp + 1 days);
        vm.deal(USER, currentPrice);
        uint256 n1 = performPaidSpin(USER); // Use paid spin
        uint256[] memory r1 = new uint256[](1);
        r1[0] = 0;

        vm.prank(SUPRA_ORACLE);
        vm.recordLogs();
        spin.handleRandomness(n1, r1);
        Vm.Log[] memory L1 = vm.getRecordedLogs();
        assertEq(L1[0].topics[0], keccak256("NotEnoughStreak(string)"), "NotEnoughStreak event not emitted");
        (string memory cat1, uint256 amt1) = abi.decode(L1[1].data, (string, uint256));
        assertEq(cat1, "Nothing");
        assertEq(amt1, 0);

        // Day 2, streak=2 => Now should get Jackpot
        vm.warp(block.timestamp + 1 days);
        vm.deal(USER, currentPrice);
        uint256 n2 = performPaidSpin(USER); // Use paid spin
        uint256[] memory r2 = new uint256[](1);
        r2[0] = 0;

        vm.prank(SUPRA_ORACLE);
        vm.recordLogs();
        spin.handleRandomness(n2, r2);
        Vm.Log[] memory L2 = vm.getRecordedLogs();
        (string memory cat2, uint256 amt2) = abi.decode(L2[0].data, (string, uint256));
        assertEq(cat2, "Jackpot");
        assertEq(amt2, 5000);
        assertEq(USER.balance, 5000 ether);
    }

    /// @notice Test Plume Token reward and transfer
    function testPlumeTokenRewardAndTransfer() public {
        vm.prank(ADMIN);
        spin.whitelist(USER);

        vm.deal(USER, INITIAL_SPIN_PRICE);
        uint256 n = performPaidSpin(USER);
        uint256[] memory r = new uint256[](1);
        r[0] = 100_123; // 1–200k = Plume Token

        vm.prank(SUPRA_ORACLE);
        vm.recordLogs();
        spin.handleRandomness(n, r);
        Vm.Log[] memory L = vm.getRecordedLogs();
        (string memory c, uint256 a) = abi.decode(L[0].data, (string, uint256));
        assertEq(c, "Plume Token");
        assertEq(a, 1);
        assertEq(USER.balance, 1 ether);
    }

    /// @notice Test Raffle Ticket reward
    function testRaffleTicketReward() public {
        vm.prank(ADMIN);
        spin.whitelist(USER);

        vm.deal(USER, INITIAL_SPIN_PRICE);
        uint256 n = performPaidSpin(USER);
        uint256[] memory r = new uint256[](1);
        r[0] = 300_000; // 200–600k = Raffle Ticket

        vm.prank(SUPRA_ORACLE);
        vm.recordLogs();
        spin.handleRandomness(n, r);
        Vm.Log[] memory L = vm.getRecordedLogs();
        (string memory c, uint256 a) = abi.decode(L[0].data, (string, uint256));
        assertEq(c, "Raffle Ticket");
        assertEq(a, 8); // base 8 * (0+1)

        (,,,, uint256 bal,,) = spin.getUserData(USER);
        assertEq(bal, 8);
    }

    /// @notice Test PP reward
    function testPPReward() public {
        vm.prank(ADMIN);
        spin.whitelist(USER);

        vm.deal(USER, INITIAL_SPIN_PRICE);
        uint256 n = performPaidSpin(USER);
        uint256[] memory r = new uint256[](1);
        r[0] = 700_000; // 600–900k = PP

        vm.prank(SUPRA_ORACLE);
        vm.recordLogs();
        spin.handleRandomness(n, r);
        Vm.Log[] memory L = vm.getRecordedLogs();
        (string memory c, uint256 a) = abi.decode(L[0].data, (string, uint256));
        assertEq(c, "PP");
        assertEq(a, 100);

        (,,,,, uint256 pp,) = spin.getUserData(USER);
        assertEq(pp, 100);
    }

    /// @notice Test the probability, week tracking, and jackpot claiming logic over multiple days with two users
    function testJackpotProbabilityAndWeekTrackingWithTwoUsers() public {
        // Fund the contract sufficiently for jackpot payouts
        vm.deal(address(spin), 200_000 ether);

        // Define the default jackpot probabilities used in the contract
        uint256[7] memory defaultProbabilities = [uint256(1), 2, 3, 5, 7, 10, 20];

        uint256 startTimestamp = block.timestamp;
        uint256 campaignStartDate = spin.getCampaignStartDate();

        emit log_string(
            string(
                abi.encodePacked("START! ", vm.toString(campaignStartDate), " chain: ", vm.toString(block.timestamp))
            )
        );

        // Track streak-building days (days 1-7, first week) for both users
        for (uint8 day = 1; day < 8; day++) {
            // Check we're still in week 0
            assertEq(
                spin.getCurrentWeek(),
                0,
                string(
                    abi.encodePacked(
                        "Day ",
                        vm.toString(day),
                        " should be in week 0, timestamp: ",
                        vm.toString(block.timestamp),
                        ", startTimestamp: ",
                        vm.toString(campaignStartDate)
                    )
                )
            );

            // USER 4: Spin to build streak
            vm.deal(USER4, INITIAL_SPIN_PRICE);
            uint256 nonce1 = performPaidSpin(USER4);
            completeSpin(nonce1, 999_999);

            // USER 5: Spin to build streak
            vm.deal(USER5, INITIAL_SPIN_PRICE);
            uint256 nonce2 = performPaidSpin(USER5);
            completeSpin(nonce2, 999_999);

            // Check streak is building properly for both users
            assertEq(
                spin.currentStreak(USER4),
                day,
                string(
                    abi.encodePacked(
                        "USER4 streak should be ", vm.toString(day), " after spin on day ", vm.toString(day)
                    )
                )
            );
            assertEq(
                spin.currentStreak(USER5),
                day,
                string(
                    abi.encodePacked(
                        "USER5 streak should be ", vm.toString(day), " after spin on day ", vm.toString(day)
                    )
                )
            );

            // move to next day
            vm.warp(block.timestamp + 1 days);
        }

        //**  Now its day 8 **/

        // Check we're now in week 2 (1 based on zero indexing)
        assertEq(
            spin.getCurrentWeek(),
            1,
            string(abi.encodePacked("Should be in week 2 on day 8, block.timestamp: ", vm.toString(block.timestamp)))
        );
        assertEq(spin.currentStreak(USER4), 7, "USER4 streak should be 7 on day 7 before spin");
        assertEq(spin.currentStreak(USER5), 7, "USER5 streak should be 7 on day 7 before spin");

        // USER4: Test with probability > threshold (should fail)
        vm.deal(USER4, INITIAL_SPIN_PRICE);
        uint256 nonce8a = performPaidSpin(USER4);

        vm.recordLogs();
        completeSpin(nonce8a, 1); // Use 1 which is > day 0's probability of < 1

        assertEq(spin.currentStreak(USER4), 8, "USER4 streak should be 8 on day 7 after spin");

        // Check the result was "Nothing" not a jackpot
        Vm.Log[] memory logs8a = vm.getRecordedLogs();
        (string memory cat8a, uint256 amt8a) = abi.decode(logs8a[0].data, (string, uint256));
        assertEq(cat8a, "Plume Token", "USER4 should get Plume Token for probability > threshold");
        assertEq(amt8a, 1, "Amount should be 1 for Plume Token");

        // USER5: Test with probability < threshold (should win jackpot)
        vm.deal(USER5, INITIAL_SPIN_PRICE);
        uint256 nonce8b = performPaidSpin(USER5);

        vm.recordLogs();
        completeSpin(nonce8b, 0); // Use 0 which is < day 0's probability of < 1

        assertEq(spin.currentStreak(USER5), 8, "USER5 streak should be 8 on day 7 after spin");

        // Check the result was a jackpot
        Vm.Log[] memory logs8b = vm.getRecordedLogs();
        (string memory cat8b, uint256 amt8b) = abi.decode(logs8b[0].data, (string, uint256));
        assertEq(cat8b, "Jackpot", "USER5 should get Jackpot for probability < threshold");
        (, uint256 week1Prize,) = spin.getWeeklyJackpot();
        assertEq(amt8b, 5000, "Amount should be week 1's jackpot prize");
        assertEq(week1Prize, 5000, "Week1 jackpot amount is wrong"); // note this is brittle and might change

        // Day 9 - second day of week 1
        vm.warp(block.timestamp + 1 days);

        //**  Now its day 9 **/

        // USER4: Try with probability > threshold (should fail naturally)
        vm.deal(USER4, INITIAL_SPIN_PRICE);
        uint256 nonce9a = performPaidSpin(USER4);

        vm.recordLogs();
        completeSpin(nonce9a, 2); // Use 2 which is > day 1's probability of <2

        // Check the result was "Nothing" without NotEnoughStreak
        Vm.Log[] memory logs9a = vm.getRecordedLogs();
        bool emittedNotEnoughStreak9a = false;

        for (uint256 i = 0; i < logs9a.length; i++) {
            if (logs9a[i].topics[0] == keccak256("NotEnoughStreak(string)")) {
                emittedNotEnoughStreak9a = true;
                break;
            }
        }

        assertFalse(emittedNotEnoughStreak9a, "Should not emit NotEnoughStreak for probability > threshold");

        // Parse the SpinCompleted event
        (string memory cat9a, uint256 amt9a) = abi.decode(logs9a[0].data, (string, uint256));
        assertEq(cat9a, "Plume Token", "Should get Plume Token for probability > threshold");

        // USER5: Try with probability < threshold (should hit jackpot threshold but fail due to one per week)
        vm.deal(USER5, INITIAL_SPIN_PRICE);
        uint256 nonce9b = performPaidSpin(USER5);

        vm.recordLogs();
        completeSpin(nonce9b, 1); // Use 1 which is < day 1's probability of < 2

        // Check we got JackpotAlreadyClaimed
        Vm.Log[] memory logs9b = vm.getRecordedLogs();
        bool foundJackpotAlreadyClaimed9b = false;

        for (uint256 i = 0; i < logs9b.length; i++) {
            if (logs9b[i].topics[0] == keccak256("JackpotAlreadyClaimed(string)")) {
                foundJackpotAlreadyClaimed9b = true;
                break;
            }
        }

        assertTrue(
            foundJackpotAlreadyClaimed9b, "Should emit JackpotAlreadyClaimed when second jackpot hit in same week"
        );

        // Check the result was "Nothing"
        (string memory cat9b, uint256 amt9b) = abi.decode(logs9b[logs9b.length - 1].data, (string, uint256));
        assertEq(cat9b, "Nothing", "Should get Nothing for second jackpot in same week");

        // Test remaining days of week 1 with progressively higher probabilities
        for (uint8 day = 3; day < 8; day++) {
            vm.warp(block.timestamp + 1 days);

            //**  Now its day 10-14 (day+7) **/

            // Check we're still in week 2 (match 1 based on zero indexing)
            assertEq(
                spin.getCurrentWeek(),
                1,
                string(abi.encodePacked("Day ", vm.toString(day + 7), " should be in week 2s"))
            );

            // USER4: Try with above threshold (should fail naturally)
            vm.deal(USER4, INITIAL_SPIN_PRICE);
            uint256 nonceUserAbove = performPaidSpin(USER4);

            vm.recordLogs();
            completeSpin(nonceUserAbove, defaultProbabilities[day - 1]); // use the probability for the day which should
                // not win

            // Check USER4 got Plume Token without NotEnoughStreak
            Vm.Log[] memory logsUser = vm.getRecordedLogs();
            bool userEmittedNotEnoughStreak = false;

            for (uint256 i = 0; i < logsUser.length; i++) {
                if (logsUser[i].topics[0] == keccak256("NotEnoughStreak(string)")) {
                    userEmittedNotEnoughStreak = true;
                    break;
                }
            }
            assertFalse(userEmittedNotEnoughStreak, "USER4 should not emit NotEnoughStreak for probability > threshold");
            (string memory catUser, uint256 amtUser) = abi.decode(logsUser[logsUser.length - 1].data, (string, uint256));
            assertEq(catUser, "Plume Token", "Should get Plume Token for probability > threshold");

            // USER5: Try with below threshold (should get JackpotAlreadyClaimed)
            vm.deal(USER5, INITIAL_SPIN_PRICE);
            uint256 nonceUser2Below = performPaidSpin(USER5);

            vm.recordLogs();
            completeSpin(nonceUser2Below, defaultProbabilities[day - 1] - 1);

            // Check USER5 got JackpotAlreadyClaimed
            Vm.Log[] memory logsUser2 = vm.getRecordedLogs();
            bool user2FoundClaimed = false;

            for (uint256 i = 0; i < logsUser2.length; i++) {
                if (logsUser2[i].topics[0] == keccak256("JackpotAlreadyClaimed(string)")) {
                    user2FoundClaimed = true;
                    break;
                }
            }

            assertTrue(
                user2FoundClaimed,
                string(abi.encodePacked("USER5 should emit JackpotAlreadyClaimed on day ", vm.toString(day + 7)))
            );
            // Check the result was "Nothing"
            (string memory catUser2, uint256 amtUser2) =
                abi.decode(logsUser2[logsUser2.length - 1].data, (string, uint256));
            assertEq(catUser2, "Nothing", "Should get Nothing for second jackpot in same week");
        }

        // Now test week 2, day 0 (which is day 14 overall)
        vm.warp(block.timestamp + 1 days);

        //**  Now its day 15 **/

        // Check we're now in week 3 (2 based on zero indexing)
        assertEq(spin.getCurrentWeek(), 2, "Should be in week 3 on day 15");

        // USER4: Try with probability > threshold (should fail)
        vm.deal(USER4, INITIAL_SPIN_PRICE);
        uint256 nonce14a = performPaidSpin(USER4);

        vm.recordLogs();
        completeSpin(nonce14a, 1); // Use 1 which is > day 0's probability of < 1

        // Check the result was "Nothing"
        Vm.Log[] memory logs14a = vm.getRecordedLogs();
        (string memory cat14a, uint256 amt14a) = abi.decode(logs14a[0].data, (string, uint256));
        assertEq(cat14a, "Plume Token", "USER4 should get Plume Token for probability > threshold in week 2");

        // USER5: Try with probability < threshold (should win as we're on day 0 of week 2)
        vm.deal(USER5, INITIAL_SPIN_PRICE);
        uint256 nonce14b = performPaidSpin(USER5);

        vm.recordLogs();
        completeSpin(nonce14b, 0); // Use 0 which is < day 0's probability of 1

        // Check the result was a jackpot
        Vm.Log[] memory logs14b = vm.getRecordedLogs();
        (string memory cat14b, uint256 amt14b) = abi.decode(logs14b[0].data, (string, uint256));
        assertEq(cat14b, "Jackpot", "USER5 should get Jackpot for probability < threshold in week 2");
        assertEq(amt14b, 10_000, "Amount should be week 2's jackpot prize");
    }

    /// @notice Test that streak calculation is based on calendar days, not 24-hour periods
    function testStreakByCalendarDay() public {
        // Initial check
        assertEq(spin.currentStreak(USER), 0, "Initial streak should be 0");

        uint256 currentSpinPrice = spin.getSpinPrice();

        // Get the start date from the contract to make sure we're using compatible dates
        uint256 campaignStartDate = spin.getCampaignStartDate();

        // Day 0 @ 7am - Use the campaign start date but set time to 11:00 AM
        uint16 year = dateTime.getYear(campaignStartDate);
        uint8 month = dateTime.getMonth(campaignStartDate);
        uint8 day = dateTime.getDay(campaignStartDate);
        vm.warp(dateTime.toTimestamp(year, month, day, 11, 0, 0));

        vm.deal(USER, currentSpinPrice);
        uint256 nonce1 = performPaidSpin(USER);
        completeSpin(nonce1, 999_999); // Complete spin with "Nothing" reward
        assertEq(spin.currentStreak(USER), 1, "Streak should be 1 after first spin");

        // Day 1 @ 1am - Next day early morning
        vm.warp(dateTime.toTimestamp(year, month, day + 1, 1, 0, 0));
        vm.deal(USER, currentSpinPrice);
        uint256 nonce2 = performPaidSpin(USER);
        completeSpin(nonce2, 999_999);
        assertEq(spin.currentStreak(USER), 2, "Streak should be 2 after consecutive day spin (early morning)");

        // Day 2 @ 11pm - Next day late evening
        vm.warp(dateTime.toTimestamp(year, month, day + 2, 23, 0, 0));
        vm.deal(USER, currentSpinPrice);
        uint256 nonce3 = performPaidSpin(USER);
        completeSpin(nonce3, 999_999);
        assertEq(spin.currentStreak(USER), 3, "Streak should be 3 after consecutive day spin (late night)");

        // Day 4 @ 1am - Skip day 3, go to day 4 early morning
        vm.warp(dateTime.toTimestamp(year, month, day + 4, 1, 0, 0));

        // Check streak BEFORE spin - should be reset to 0 due to missed day
        assertEq(spin.currentStreak(USER), 0, "Streak should reset to 0 after skipping a day");

        // Now spin on day 4
        vm.deal(USER, currentSpinPrice);
        uint256 nonce4 = performPaidSpin(USER);
        completeSpin(nonce4, 999_999);

        // Streak should be 1 after spinning on day 4 (not consecutive with day 2)
        assertEq(spin.currentStreak(USER), 1, "Streak should be 1 after spinning on non-consecutive day");
    }

}
