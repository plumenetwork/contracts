// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { Test } from "forge-std/Test.sol";

import { Deposit, UserState } from "../../src/token/Types.sol";
import { YieldDistributionTokenHarness } from "../harness/YieldDistributionTokenHarness.sol";
import { stdError } from "forge-std/StdError.sol";

import { YieldDistributionToken } from "../../src/token/YieldDistributionToken.sol";

contract YieldDistributionTokenScenarioTest is Test {

    YieldDistributionTokenHarness token;
    ERC20Mock currencyTokenMock;

    address alice = makeAddr("Alice");
    address bob = makeAddr("Bob");
    address charlie = makeAddr("Charlie");
    address OWNER = makeAddr("Owner");
    uint256 MINT_AMOUNT = 10 ether;
    uint256 YIELD_AMOUNT = 100 ether;
    uint256 OWNER_MINTED_AMOUNT = 100_000 ether;

    uint256 skipDuration = 10;
    uint256 timeskipCounter;

    function setUp() public {
        currencyTokenMock = new ERC20Mock();
        token = new YieldDistributionTokenHarness(
            OWNER, "Yield Distribution Token", "YDT", IERC20(address(currencyTokenMock)), 18, "URI"
        );

        currencyTokenMock.mint(OWNER, OWNER_MINTED_AMOUNT);
    }

    function test_setUp() public {
        token.exposed_mint(alice, MINT_AMOUNT);
        token.exposed_mint(bob, MINT_AMOUNT);
        token.exposed_mint(charlie, MINT_AMOUNT);

        assertEq(token.name(), "Yield Distribution Token");
        assertEq(token.symbol(), "YDT");
        assertEq(token.decimals(), 18);
        assertEq(token.getTokenURI(), "URI");
        assertEq(address(token.getCurrencyToken()), address(currencyTokenMock));
        assertEq(token.owner(), OWNER);
        assertEq(token.totalSupply(), 3 * MINT_AMOUNT);
        assertEq(token.balanceOf(alice), MINT_AMOUNT);
        assertEq(token.balanceOf(bob), MINT_AMOUNT);
        assertEq(token.balanceOf(charlie), MINT_AMOUNT);
        assertEq(currencyTokenMock.balanceOf(OWNER), OWNER_MINTED_AMOUNT);

        Deposit[] memory deposits = token.getDeposits();
        assertEq(deposits.length, 1);
        assertEq(deposits[0].scaledCurrencyTokenPerAmountSecond, 0);
        assertEq(deposits[0].totalAmountSeconds, 0);
        assertEq(deposits[0].timestamp, block.timestamp);

        UserState memory aliceState = token.getUserState(alice);
        assertEq(aliceState.amountSeconds, 0);
        assertEq(aliceState.amountSecondsDeduction, 0);
        assertEq(aliceState.lastUpdate, block.timestamp);
        assertEq(aliceState.lastDepositIndex, 0);
        assertEq(aliceState.yieldAccrued, 0);
        assertEq(aliceState.yieldWithdrawn, 0);

        UserState memory bobState = token.getUserState(bob);
        assertEq(bobState.amountSeconds, 0);
        assertEq(bobState.amountSecondsDeduction, 0);
        assertEq(bobState.lastUpdate, block.timestamp);
        assertEq(bobState.lastDepositIndex, 0);
        assertEq(bobState.yieldAccrued, 0);
        assertEq(bobState.yieldWithdrawn, 0);

        UserState memory charlieState = token.getUserState(charlie);
        assertEq(charlieState.amountSeconds, 0);
        assertEq(charlieState.amountSecondsDeduction, 0);
        assertEq(charlieState.lastUpdate, block.timestamp);
        assertEq(charlieState.lastDepositIndex, 0);
        assertEq(charlieState.yieldAccrued, 0);
        assertEq(charlieState.yieldWithdrawn, 0);
    }

    /// @dev Simulates a simple real world scenario
    function test_scenario() public {
        token.exposed_mint(alice, MINT_AMOUNT);
        _timeskip();

        token.exposed_mint(bob, MINT_AMOUNT);
        _timeskip();

        token.exposed_mint(charlie, MINT_AMOUNT);
        _timeskip();

        uint256 expectedAliceAmountSeconds = MINT_AMOUNT * skipDuration * timeskipCounter;
        uint256 expectedBobAmountSeconds = MINT_AMOUNT * skipDuration * (timeskipCounter - 1);
        uint256 expectedCharlieAmountSeconds = MINT_AMOUNT * skipDuration * (timeskipCounter - 2);
        uint256 totalExpectedAmountSeconds =
            expectedAliceAmountSeconds + expectedBobAmountSeconds + expectedCharlieAmountSeconds;

        _depositYield(YIELD_AMOUNT);

        uint256 expectedAliceYieldAccrued = expectedAliceAmountSeconds * YIELD_AMOUNT / totalExpectedAmountSeconds;
        uint256 expectedBobYieldAccrued = expectedBobAmountSeconds * YIELD_AMOUNT / totalExpectedAmountSeconds;
        uint256 expectedCharlieYieldAccrued = expectedCharlieAmountSeconds * YIELD_AMOUNT / totalExpectedAmountSeconds;

        _transferFrom(alice, bob, MINT_AMOUNT);
        token.claimYield(charlie);

        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 2 * MINT_AMOUNT);
        assertEq(token.balanceOf(charlie), MINT_AMOUNT);

        // WEIRD BEHAVIOUR MARK, COMMENT EVERYTHING OUT AFTER 3 NEXT ASSERTIONS AND RUN
        // rounding error; perhaps can fix by rounding direction?
        assertEq(token.getUserState(alice).yieldAccrued, expectedAliceYieldAccrued - 1);
        assertEq(token.getUserState(bob).yieldAccrued, expectedBobYieldAccrued);
        assertEq(token.getUserState(charlie).yieldAccrued, expectedCharlieYieldAccrued);

        _timeskip();

        token.exposed_mint(alice, MINT_AMOUNT);

        _timeskip();

        token.exposed_burn(charlie, MINT_AMOUNT);
        _timeskip();

        assertEq(token.balanceOf(charlie), 0);

        _transferFrom(bob, alice, MINT_AMOUNT);
        _timeskip();

        expectedAliceAmountSeconds = MINT_AMOUNT * skipDuration * 2 + (2 * MINT_AMOUNT) * skipDuration;
        expectedBobAmountSeconds = (2 * MINT_AMOUNT) * skipDuration * 3 + MINT_AMOUNT * skipDuration;
        expectedCharlieAmountSeconds = MINT_AMOUNT * skipDuration * 2;
        totalExpectedAmountSeconds =
            expectedAliceAmountSeconds + expectedBobAmountSeconds + expectedCharlieAmountSeconds;

        _depositYield(YIELD_AMOUNT);

        expectedAliceYieldAccrued += expectedAliceAmountSeconds * YIELD_AMOUNT / totalExpectedAmountSeconds;
        expectedBobYieldAccrued += expectedBobAmountSeconds * YIELD_AMOUNT / totalExpectedAmountSeconds;
        expectedCharlieYieldAccrued += expectedCharlieAmountSeconds * YIELD_AMOUNT / totalExpectedAmountSeconds;

        token.accrueYield(alice);
        token.accrueYield(bob);
        token.accrueYield(charlie);

        // rounding error; perhaps can fix by rounding direction?
        assertEq(token.getUserState(alice).yieldAccrued, expectedAliceYieldAccrued - 1);
        assertEq(token.getUserState(bob).yieldAccrued, expectedBobYieldAccrued);
        assertEq(token.getUserState(charlie).yieldAccrued, expectedCharlieYieldAccrued);

        uint256 oldAliceBalance = currencyTokenMock.balanceOf(alice);
        uint256 oldBobBalance = currencyTokenMock.balanceOf(bob);
        uint256 oldCharlieBalance = currencyTokenMock.balanceOf(charlie);
        uint256 oldWithdrawnYieldAlice = token.getUserState(alice).yieldWithdrawn;
        uint256 oldWithdrawnYieldBob = token.getUserState(bob).yieldWithdrawn;
        uint256 oldWithdrawnYieldCharlie = token.getUserState(charlie).yieldWithdrawn;

        token.claimYield(alice);
        token.claimYield(bob);
        token.claimYield(charlie);

        // rounding error; perhaps can fix by rounding direction?
        assertEq(
            currencyTokenMock.balanceOf(alice) - oldAliceBalance, expectedAliceYieldAccrued - oldWithdrawnYieldAlice - 1
        );
        assertEq(currencyTokenMock.balanceOf(bob) - oldBobBalance, expectedBobYieldAccrued - oldWithdrawnYieldBob);
        assertEq(
            currencyTokenMock.balanceOf(charlie) - oldCharlieBalance,
            expectedCharlieYieldAccrued - oldWithdrawnYieldCharlie
        );
    }

    /// @dev Simulates a scenario where a user returns, or claims, some deposits after accruing `amountSeconds`,
    /// ensuring that
    /// yield is correctly distributed
    function test_scenario_userBurnsTokensAfterAccruingSomeYield_andWaitsForAtLeastTwoDeposits_priorToClaimingYield()
        public
    {
        token.exposed_mint(alice, MINT_AMOUNT);
        _timeskip();

        token.exposed_mint(bob, MINT_AMOUNT);
        _timeskip();

        token.exposed_mint(charlie, MINT_AMOUNT);
        _timeskip();

        token.exposed_burn(alice, MINT_AMOUNT);
        _timeskip();

        uint256 expectedAliceAmountSeconds = MINT_AMOUNT * skipDuration * 3;
        uint256 expectedBobAmountSeconds = MINT_AMOUNT * skipDuration * 3;
        uint256 expectedCharlieAmountSeconds = MINT_AMOUNT * skipDuration * 2;
        uint256 totalExpectedAmountSeconds =
            expectedAliceAmountSeconds + expectedBobAmountSeconds + expectedCharlieAmountSeconds;

        _depositYield(YIELD_AMOUNT);

        uint256 expectedAliceYieldAccrued = expectedAliceAmountSeconds * YIELD_AMOUNT / totalExpectedAmountSeconds;
        uint256 expectedBobYieldAccrued = expectedBobAmountSeconds * YIELD_AMOUNT / totalExpectedAmountSeconds;
        uint256 expectedCharlieYieldAccrued = expectedCharlieAmountSeconds * YIELD_AMOUNT / totalExpectedAmountSeconds;

        _timeskip();

        expectedAliceAmountSeconds = 0;
        expectedBobAmountSeconds = MINT_AMOUNT * skipDuration;
        expectedCharlieAmountSeconds = MINT_AMOUNT * skipDuration;
        totalExpectedAmountSeconds =
            expectedAliceAmountSeconds + expectedBobAmountSeconds + expectedCharlieAmountSeconds;

        _depositYield(YIELD_AMOUNT);

        expectedAliceYieldAccrued += expectedAliceAmountSeconds * YIELD_AMOUNT / totalExpectedAmountSeconds;
        expectedBobYieldAccrued += expectedBobAmountSeconds * YIELD_AMOUNT / totalExpectedAmountSeconds;
        expectedCharlieYieldAccrued += expectedCharlieAmountSeconds * YIELD_AMOUNT / totalExpectedAmountSeconds;

        uint256 oldAliceBalance = currencyTokenMock.balanceOf(alice);
        uint256 oldBobBalance = currencyTokenMock.balanceOf(bob);
        uint256 oldCharlieBalance = currencyTokenMock.balanceOf(charlie);
        uint256 oldWithdrawnYieldAlice = token.getUserState(alice).yieldWithdrawn;
        uint256 oldWithdrawnYieldBob = token.getUserState(bob).yieldWithdrawn;
        uint256 oldWithdrawnYieldCharlie = token.getUserState(charlie).yieldWithdrawn;

        token.claimYield(alice);
        token.claimYield(bob);
        token.claimYield(charlie);

        // TODO: no rounding error here, why?
        assertEq(
            currencyTokenMock.balanceOf(alice) - oldAliceBalance, expectedAliceYieldAccrued - oldWithdrawnYieldAlice
        );
        assertEq(currencyTokenMock.balanceOf(bob) - oldBobBalance, expectedBobYieldAccrued - oldWithdrawnYieldBob);
        assertEq(
            currencyTokenMock.balanceOf(charlie) - oldCharlieBalance,
            expectedCharlieYieldAccrued - oldWithdrawnYieldCharlie
        );
    }

    function _timeskip() internal {
        timeskipCounter++;
        vm.warp(block.timestamp + skipDuration);
    }

    function _depositYield(
        uint256 amount
    ) internal {
        vm.startPrank(OWNER);
        currencyTokenMock.approve(address(token), amount);
        token.exposed_depositYield(amount);
        vm.stopPrank();
    }

    function _approveForDepositYield(
        uint256 amount
    ) internal {
        vm.startPrank(OWNER);
        currencyTokenMock.approve(address(token), amount);
        vm.stopPrank();
    }

    function _transferFrom(address from, address to, uint256 amount) internal {
        vm.startPrank(from);
        token.transfer(to, amount);
        vm.stopPrank();
    }

    function test_RevertIf_DepositYieldCalledMultipleTimesInSameBlock() public {
        token.exposed_mint(alice, MINT_AMOUNT);
        _timeskip();
        _depositYield(YIELD_AMOUNT);
        // use separated approve & deposit otherwise expectRevert will
        // fail if using the test `_depositYield()` call
        _approveForDepositYield(YIELD_AMOUNT);

        vm.expectRevert(YieldDistributionToken.DepositSameBlock.selector);
        token.exposed_depositYield(YIELD_AMOUNT);
    }

    function test_scenario_precisionLossHandling() public {
        // Test handling of very small amounts and precision loss
        uint256 tinyAmount = 1;
        token.exposed_mint(alice, tinyAmount);
        token.exposed_mint(bob, 100_000_000 * MINT_AMOUNT);

        _timeskip();
        _depositYield(YIELD_AMOUNT);

        token.claimYield(alice);
        token.claimYield(bob);

        assertEq(token.getUserState(alice).yieldWithdrawn, 0);

        assertGt(token.getUserState(bob).yieldWithdrawn, 0);
    }

    function test_scenario_multipleDepositsAndClaims() public {
        uint256 aliceBalance = currencyTokenMock.balanceOf(alice);

        token.exposed_mint(alice, MINT_AMOUNT);
        _timeskip();

        // Multiple deposits
        for (uint256 i = 0; i < 3; i++) {
            _depositYield(YIELD_AMOUNT);
            _timeskip();
        }

        // Partial claims
        uint256 initialAccrued = token.getUserState(alice).yieldAccrued;
        token.claimYield(alice);
        aliceBalance = currencyTokenMock.balanceOf(alice);

        _depositYield(YIELD_AMOUNT);
        _timeskip();

        uint256 newAccrued = token.getUserState(alice).yieldAccrued;
        assertGt(newAccrued, 0);
        assertLt(initialAccrued, newAccrued);
    }

    function test_scenario_transferDuringYieldAccrual() public {
        token.exposed_mint(alice, MINT_AMOUNT);
        _timeskip();

        _depositYield(YIELD_AMOUNT);
        // Record initial states
        uint256 aliceInitialYield = token.getUserState(alice).yieldAccrued;
        uint256 expectedAliceAmountSeconds = MINT_AMOUNT * skipDuration * timeskipCounter;
        uint256 expectedAliceYieldAccrued = expectedAliceAmountSeconds * YIELD_AMOUNT / expectedAliceAmountSeconds;

        // Transfer tokens
        vm.expectEmit(true, true, true, true, address(token));
        emit YieldDistributionToken.YieldAccrued(alice, expectedAliceYieldAccrued);
        _transferFrom(alice, bob, MINT_AMOUNT / 2);

        token.accrueYield(bob);
        uint256 bobYield = token.getUserState(bob).yieldAccrued;
        assertEq(bobYield, 0);
        _timeskip();
        _depositYield(YIELD_AMOUNT);
        // Verify yield distribution after transfer
        // the transfer is bob's first deposit
        // the transfer will update bob's amountSeconds and lastUpdate.
        // in order for bob to accrue yield, token.accrueYield(bob) must be called
        // after bob has held balance for some time
        token.accrueYield(bob);
        assertGt(token.getUserState(bob).yieldAccrued, 0);
        assertGt(token.getUserState(alice).yieldAccrued, aliceInitialYield);
    }

    function test_scenario_massiveAmounts() public {
        uint256 largeAmount = type(uint128).max;
        uint256 largeYield = type(uint128).max;

        // Test with very large numbers to ensure no overflows
        token.exposed_mint(alice, largeAmount);
        _timeskip();

        vm.startPrank(OWNER);
        currencyTokenMock.mint(OWNER, largeYield);
        currencyTokenMock.approve(address(token), largeYield);
        token.exposed_depositYield(largeYield);
        vm.stopPrank();

        // Should not revert
        token.claimYield(alice);
        assertGt(token.getUserState(alice).yieldWithdrawn, 0);
    }

    function test_scenario_accrueYieldThenClaim() public {
        token.exposed_mint(alice, MINT_AMOUNT);
        _timeskip();
        _depositYield(YIELD_AMOUNT);

        token.accrueYield(alice);
        uint256 aliceYieldAfterAccrue = token.getUserState(alice).yieldAccrued;

        // YieldAccrued should not be emitted since it was
        // already called and nothing has changed
        vm.expectEmit(true, true, true, true, address(token));
        emit YieldDistributionToken.YieldClaimed(alice, aliceYieldAfterAccrue);
        token.claimYield(alice);

        uint256 aliceYieldAfterClaim = token.getUserState(alice).yieldAccrued;
        assertEq(aliceYieldAfterAccrue, aliceYieldAfterClaim);
        uint256 aliceBalance = currencyTokenMock.balanceOf(alice);
        assertEq(aliceBalance, aliceYieldAfterClaim);
    }

    function test_RevertIf_BurnAllThenDepositYIeld() public {
        token.exposed_mint(alice, MINT_AMOUNT);
        _timeskip();
        _depositYield(YIELD_AMOUNT);
        token.accrueYield(alice);
        uint256 aliceYieldBeforeBurn = token.getUserState(alice).yieldAccrued;

        token.exposed_burn(alice, MINT_AMOUNT);
        _timeskip();
        token.accrueYield(alice);
        uint256 aliceYieldAfterBurn = token.getUserState(alice).yieldAccrued;
        assertEq(aliceYieldBeforeBurn, aliceYieldAfterBurn);
        _timeskip();
        // Reverts here b/c of division by 0. This is expected b/c
        // _updateGlobalAmountSeconds() is setting
        // $.totalAmountSeconds += 0 since totalSupply() is now 0.
        // then in _depositYield, the deposit denominator is
        // `$.totalAmountSeconds - $.deposits[previousDepositIndex].totalAmountSeconds`
        // which is 0.
        _approveForDepositYield(YIELD_AMOUNT);
        vm.expectRevert(stdError.divisionError);
        token.exposed_depositYield(YIELD_AMOUNT);
    }

    function test_scenario_mintAndTransferInSameBlock() public {
        // setup - bob & alice have equal amount
        token.exposed_mint(alice, MINT_AMOUNT);
        _timeskip();
        _depositYield(YIELD_AMOUNT);
        // alice is owed yield from initial deposit
        token.accrueYield(alice);
        uint256 aliceYield1 = token.getUserState(alice).yieldAccrued;
        // transfer all yield tokens to bob. should not receive anymore yield going forward
        _transferFrom(alice, bob, token.balanceOf(alice));
        _timeskip();
        _depositYield(YIELD_AMOUNT);
        token.accrueYield(alice);
        uint256 aliceYield2 = token.getUserState(alice).yieldAccrued;
        assertEq(aliceYield1, aliceYield2);
    }

    function test_scenario_mintAndBurnInSameBlock() public {
        // setup - bob & alice have equal amount
        token.exposed_mint(alice, MINT_AMOUNT);
        // need to mint to bob to have some supply
        token.exposed_mint(bob, MINT_AMOUNT);

        _timeskip();
        // deposit 1
        _depositYield(YIELD_AMOUNT);
        // alice is owed yield for holding from initial mint until deposit 1
        token.accrueYield(alice);
        uint256 aliceYield1 = token.getUserState(alice).yieldAccrued;
        assertGt(aliceYield1, 0);

        _timeskip();
        // deposit 2
        _depositYield(YIELD_AMOUNT);
        // Alice burns all her tokens.
        token.exposed_burn(alice, token.balanceOf(alice));
        // alice should be owed yield for deposit 2
        token.accrueYield(alice);
        uint256 aliceYield2 = token.getUserState(alice).yieldAccrued;
        assertGt(aliceYield2, aliceYield1);

        // deposit 3
        _timeskip();
        _depositYield(YIELD_AMOUNT);
        token.exposed_mint(alice, MINT_AMOUNT);
        token.exposed_burn(alice, token.balanceOf(alice));
        token.accrueYield(alice);
        uint256 aliceYield3 = token.getUserState(alice).yieldAccrued;
        assertEq(aliceYield3, aliceYield2);

        // deposit 4
        _timeskip();
        token.exposed_mint(alice, MINT_AMOUNT);
        _depositYield(YIELD_AMOUNT);
        token.accrueYield(alice);
        token.exposed_burn(alice, token.balanceOf(alice));
        uint256 aliceYield4 = token.getUserState(alice).yieldAccrued;
        assertEq(aliceYield4, aliceYield3);

        // deposit 5
        // alice held yieldToken for some time but burned
        // before yield was deposited. Should still be owed yield.
        token.exposed_mint(alice, MINT_AMOUNT);
        _timeskip();
        token.exposed_burn(alice, token.balanceOf(alice));
        _depositYield(YIELD_AMOUNT);
        token.accrueYield(alice);
        uint256 aliceYield5 = token.getUserState(alice).yieldAccrued;
        assertGt(aliceYield5, aliceYield4);
    }

    function test_scenario_depositZeroYieldIsNoop() public {
        token.exposed_mint(alice, MINT_AMOUNT);
        uint256 expectedDepositLength = token.getDeposits().length;
        uint256 expectedTotalAmountSeconds = token.exposed_getTotalAmountSeconds();
        _timeskip();
        _depositYield(0);
        assertEq(token.getDeposits().length, expectedDepositLength);
        assertEq(token.exposed_getTotalAmountSeconds(), expectedTotalAmountSeconds);
    }

    function test_setAndGetTokenUri() public {
        assertEq(token.getTokenURI(), "URI");
        vm.startPrank(OWNER);
        token.setTokenURI("newURI");
        vm.stopPrank();
        assertEq(token.getTokenURI(), "newURI");
    }

    function test_depositYield_updatesDeposit() public {
        Deposit memory initialDeposit = token.getDeposit(0);
        assertEq(initialDeposit.scaledCurrencyTokenPerAmountSecond, 0);
        assertEq(initialDeposit.totalAmountSeconds, 0);
        assertEq(token.getDeposits().length, 1);

        token.exposed_mint(alice, MINT_AMOUNT);
        _timeskip();
        _depositYield(YIELD_AMOUNT);

        assertEq(token.getDeposits().length, 2);
    }

    // FIXME: this test is failing due to a bug in accrueYield
    // when there's an early break in the loop.
    // the accrueYield still calls _updateUserAmountSeconds()
    // which updates the userState.lastUpdate to block.timestamp
    // instead of using the timestamp of the last deposit processed
    function test_scenario_accrueYieldEarlyBreakNotEnoughGas() public {
        token.exposed_mint(alice, MINT_AMOUNT);
        for (uint256 i = 0; i < 3; i++) {
            _timeskip();
            _depositYield(YIELD_AMOUNT);
        }
        // Limit gas to test early break in accrueYield loop
        // accrueYield loop will break early if gasLeft() < 100K

        uint256 gasLimit = 100_500;
        (bool success,) = address(token).call{ gas: gasLimit }(abi.encodeWithSignature("accrueYield(address)", alice));
        /*
        alice after minGas accrueYield
            amountSeconds: 300000000000000000000
            amountSecondsDeduction: 100000000000000000000
            lastUpdate: 31
            lastDepositIndex: 1
            yieldAccrued: 100000000000000000000
            yieldWithdrawn: 0
        */
        assertTrue(success);

        /*
        alice after last accrueYield
            amountSeconds: 300000000000000000000
            amountSecondsDeduction: 300000000000000000000
            lastUpdate: 31
            lastDepositIndex: 3
            yieldAccrued: 300000000000000000000
            yieldWithdrawn: 0
        */
        token.accrueYield(alice);
    }

    function test_scenario_zeroBalanceThenDepositYieldThenNonZeroBalanceThenDepositYield() public {
        token.exposed_mint(alice, MINT_AMOUNT);
        _timeskip();
        // deposit1
        _depositYield(YIELD_AMOUNT);
        token.accrueYield(alice);
        uint256 aliceYield1 = token.getUserState(alice).yieldAccrued;
        assertGt(aliceYield1, 0);

        // alice transfers all her tokens to bob
        _transferFrom(alice, bob, token.balanceOf(alice));
        _timeskip();
        // deposit 2
        // alice should have no yield from this
        _depositYield(YIELD_AMOUNT);
        _timeskip();
        // uint256 aliceYield2 = token.getUserState(alice).yieldAccrued;
        // assertEq(aliceYield2, aliceYield1);
        _transferFrom(bob, alice, token.balanceOf(bob));
        _timeskip();
        // deposit 3
        _depositYield(YIELD_AMOUNT);
        _transferFrom(alice, bob, token.balanceOf(alice));
        _timeskip();
        // deposit 4
        _depositYield(YIELD_AMOUNT);
        // alice should have yield for the time from deposit 2 to deposit 3
        token.accrueYield(alice);
        uint256 aliceYield2 = token.getUserState(alice).yieldAccrued;
        assertGt(aliceYield2, aliceYield1);
    }

}
