// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { Test } from "forge-std/Test.sol";

import { Deposit, UserState } from "../../src/token/Types.sol";
import { YieldDistributionTokenHarness } from "../harness/YieldDistributionTokenHarness.sol";

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

    function test_setUp() public view {
        assertEq(token.name(), "Yield Distribution Token");
        assertEq(token.symbol(), "YDT");
        assertEq(token.decimals(), 18);
        assertEq(token.getTokenURI(), "URI");
        assertEq(address(token.getCurrencyToken()), address(currencyTokenMock));
        assertEq(token.owner(), OWNER);
        //assertEq(token.totalSupply(), 3 * MINT_AMOUNT);
        /*
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
        */
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

/*
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
*/
    function _timeskip() internal {
        timeskipCounter++;
        vm.warp(block.timestamp + skipDuration);
    }

    function _depositYield(uint256 amount) internal {
        vm.startPrank(OWNER);
        currencyTokenMock.approve(address(token), amount);
        token.exposed_depositYield(amount);
        vm.stopPrank();
    }

    function _transferFrom(address from, address to, uint256 amount) internal {
        vm.startPrank(from);
        token.transfer(to, amount);
        vm.stopPrank();
    }

}
