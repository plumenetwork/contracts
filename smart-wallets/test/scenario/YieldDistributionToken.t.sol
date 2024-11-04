// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { Test } from "forge-std/Test.sol";

import { Deposit, UserState } from "../../src/token/Types.sol";
import { YieldDistributionTokenHarness } from "../harness/YieldDistributionTokenHarness.sol";
import { stdError } from "forge-std/StdError.sol";

import { console2 } from "forge-std/console2.sol";

contract YieldDistributionTokenScenarioTest is Test {

    /**
     * @notice Emitted when yield is deposited into the YieldDistributionToken
     * @param user Address of the user who deposited the yield
     * @param currencyTokenAmount Amount of CurrencyToken deposited as yield
     */
    event Deposited(address indexed user, uint256 currencyTokenAmount);

    /**
     * @notice Emitted when yield is claimed by a user
     * @param user Address of the user who claimed the yield
     * @param currencyTokenAmount Amount of CurrencyToken claimed as yield
     */
    event YieldClaimed(address indexed user, uint256 currencyTokenAmount);

    /**
     * @notice Emitted when yield is accrued to a user
     * @param user Address of the user who accrued the yield
     * @param currencyTokenAmount Amount of CurrencyToken accrued as yield
     */
    event YieldAccrued(address indexed user, uint256 currencyTokenAmount);

    // Errors

    /**
     * @notice Indicates a failure because the transfer of CurrencyToken failed
     * @param user Address of the user who tried to transfer CurrencyToken
     * @param currencyTokenAmount Amount of CurrencyToken that failed to transfer
     */
    error TransferFailed(address user, uint256 currencyTokenAmount);

    /// @notice Indicates a failure because a yield deposit is made in the same block as the last one
    error DepositSameBlock();

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
        // vm.expectRevert(abi.encodeWithSignature("DepositSameBlock()"));
        vm.expectRevert(DepositSameBlock.selector);
        token.exposed_depositYield(YIELD_AMOUNT);
    }

    function test_scenario_precisionLossHandling() public {
        // Test handling of very small amounts and precision loss
        uint256 tinyAmount = 1;
        token.exposed_mint(alice, tinyAmount);
        token.exposed_mint(bob, MINT_AMOUNT);

        _timeskip();
        _depositYield(YIELD_AMOUNT);

        uint256 aliceYieldBefore = token.getUserState(alice).yieldAccrued;
        uint256 bobYieldBefore = token.getUserState(bob).yieldAccrued;

        token.claimYield(alice);
        token.claimYield(bob);

        // Ensure small holders still get something if entitled
        if (aliceYieldBefore > 0) {
            assertGt(token.getUserState(alice).yieldWithdrawn, 0);
        }
        assertGt(token.getUserState(bob).yieldWithdrawn, 0);
    }

    function test_scenario_multipleDepositsAndClaims() public {
        uint256 aliceBalance = currencyTokenMock.balanceOf(alice);
        console2.log("aliceBalance", aliceBalance);

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
        console2.log("aliceBalance after claimYield", aliceBalance);

        _depositYield(YIELD_AMOUNT);
        _timeskip();

        uint256 newAccrued = token.getUserState(alice).yieldAccrued;
        assertGt(newAccrued, 0);
        assertLt(initialAccrued, newAccrued);
    }

    // TODO: test failing rn.
    function test_scenario_transferDuringYieldAccrual() public {
        token.exposed_mint(alice, MINT_AMOUNT);
        _timeskip();

        _depositYield(YIELD_AMOUNT);
        // Record initial states
        uint256 aliceInitialYield = token.getUserState(alice).yieldAccrued;
        // console2.log("aliceInitialYield", aliceInitialYield);

        // token.accrueYield(alice);
        console2.log("aliceYieldAfterAccrue", token.getUserState(alice).yieldAccrued);
        uint256 expectedAliceAmountSeconds = MINT_AMOUNT * skipDuration * timeskipCounter;
        uint256 expectedAliceYieldAccrued = expectedAliceAmountSeconds * YIELD_AMOUNT / expectedAliceAmountSeconds;

        // Transfer tokens
        vm.expectEmit(true, true, true, true, address(token));
        emit YieldAccrued(alice, expectedAliceYieldAccrued);
        _transferFrom(alice, bob, MINT_AMOUNT / 2);

        uint256 aliceYieldAfterTransfer = token.getUserState(alice).yieldAccrued;
        console2.log("aliceYieldAfterTransfer", aliceYieldAfterTransfer);
        token.logUserState(bob, "bob after _transferFrom");
        token.accrueYield(bob);
        token.logUserState(bob, "bob after accrueYield(bob)");
        _timeskip();
        _depositYield(YIELD_AMOUNT);
        token.logUserState(bob, "bob after depositYield");
        // Verify yield distribution after transfer
        // the transfer is bob's first deposit
        // the transfer will update bob's amountSeconds and lastUpdate.
        // accrueYield must be called after some _timeskip() after the first _transferFrom()
        // in order for bob to actually accrue any yield
        token.accrueYield(bob);
        token.logUserState(bob, "after second accrueYield(bob)");

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
        // already called and nothing
        // has changed
        vm.expectEmit(true, true, true, true, address(token));
        emit YieldClaimed(alice, aliceYieldAfterAccrue);
        token.claimYield(alice);

        uint256 aliceYieldAfterClaim = token.getUserState(alice).yieldAccrued;
        assertEq(aliceYieldAfterAccrue, aliceYieldAfterClaim);
        uint256 aliceBalance = currencyTokenMock.balanceOf(alice);
        assertEq(currencyTokenMock.balanceOf(alice), aliceYieldAfterClaim);
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
        console2.log("aliceYieldBeforeBurn", aliceYieldBeforeBurn);
        console2.log("aliceYieldAfterBurn", aliceYieldAfterBurn);
        assertEq(aliceYieldBeforeBurn, aliceYieldAfterBurn);

        console2.log("timeskip before depositYield 2");
        _timeskip();
        console2.log("depositing yield 2");
        // Reverts here b/c of division by 0. This is expected b/c
        // _updateGlobalAmountSeconds() is setting
        // $.totalAmountSeconds += 0 since totalSupply() is now 0.
        // then in _depositYield, the deposit denominator is
        // `$.totalAmountSeconds - $.deposits[previousDepositIndex].totalAmountSeconds`
        // which is 0.
        _approveForDepositYield(YIELD_AMOUNT);
        vm.expectRevert(stdError.divisionError);
        token.exposed_depositYield(YIELD_AMOUNT);
        // _depositYield(YIELD_AMOUNT);
        // _timeskip();
        // console2.log("accrueYield 2");
        // token.accrueYield(alice);
        // uint256 aliceYieldAfterDeposit = token.getUserState(alice).yieldAccrued;
        // console2.log("aliceYieldAfterDeposit", aliceYieldAfterDeposit);
        // assertGt(aliceYieldAfterDeposit, aliceYieldAfterBurn);
    }

    // function test_scenario_mintAndTransferInSameBlock() public {
    //     // setup - bob & alice have equal amount
    //     token.exposed_mint(alice, MINT_AMOUNT);
    //     token.exposed_mint(bob, MINT_AMOUNT);
    //     _timeskip();
    //     _depositYield(YIELD_AMOUNT);
    //     token.accrueYield(alice);
    //     token.accrueYield(bob);
    //     assertEq(token.getUserState(alice).yieldAccrued, token.getUserState(bob).yieldAccrued);
    //     _timeskip();
    //     _depositYield(YIELD_AMOUNT);
    //     token.accrueYield(alice);
    //     token.accrueYield(bob);
    //     // this timeskip results in bob still accruing yield after
    //     // minting & transferring all his tokens in the same block
    //     _timeskip();

    //     // alice mints & accrues yield in same block
    //     token.logUserState(alice, "alice before mint2");
    //     console2.log("before mint2");
    //     uint256 aliceBeforeMintAndAccrue = token.getUserState(alice).yieldAccrued;
    //     token.exposed_mint(alice, MINT_AMOUNT);
    //     token.accrueYield(alice);
    //     uint256 aliceAfterMintAndAccrue = token.getUserState(alice).yieldAccrued;
    //     console2.log("aliceBeforeMintAndAccrue:\t%d", aliceBeforeMintAndAccrue);
    //     console2.log("aliceAfterMintAndAccrue:\t%d", aliceAfterMintAndAccrue);

    //     token.accrueYield(bob);
    //     uint256 bobBeforeMintAndAccrue = token.getUserState(bob).yieldAccrued;
    //     console2.log("bobBeforeMintAndAccrue:\t%d", bobBeforeMintAndAccrue);
    //     // bob mints, accures yield then transfers all yieldTokens to charlie
    //     token.exposed_mint(bob, MINT_AMOUNT);
    //     token.accrueYield(bob);
    //     uint256 bobBeforeTransfer = token.getUserState(bob).yieldAccrued;
    //     _transferFrom(bob, charlie, token.balanceOf(bob));
    //     // token.exposed_burn(bob, 2 * MINT_AMOUNT);

    //     console2.log("alice yield: %d", token.getUserState(alice).yieldAccrued);
    //     console2.log("bobBeforeTransfer:\t%d", bobBeforeTransfer);
    //     token.accrueYield(bob);
    //     token.accrueYield(charlie);
    //     uint256 charlieAfterTransfer = token.getUserState(charlie).yieldAccrued;
    //     uint256 bobAfterTransfer = token.getUserState(bob).yieldAccrued;
    //     console2.log("bobAfterTransfer:\t%d", bobAfterTransfer);
    //     console2.log("charlieAfterTransfer:\t%d", charlieAfterTransfer);

    //     _timeskip();
    //     _depositYield(YIELD_AMOUNT);
    //     token.accrueYield(alice);
    //     token.accrueYield(bob);
    //     token.accrueYield(charlie);
    //     uint256 aliceYieldAfterTimeskip = token.getUserState(alice).yieldAccrued;
    //     uint256 bobYieldAfterTransferAndTimeskip = token.getUserState(bob).yieldAccrued;
    //     uint256 charlieYieldAfterTransferAndTimeskip = token.getUserState(charlie).yieldAccrued;

    //     console2.log("aliceYieldAfterTimeskip:\t%d", aliceYieldAfterTimeskip);
    //     console2.log("bobYieldAfterTransferAndTimeskip:\t%d", bobYieldAfterTransferAndTimeskip);
    //     console2.log("charlieYieldAfterTransferAndTimeskip:\t%d", charlieYieldAfterTransferAndTimeskip);
    //     assertGt(aliceYieldAfterTimeskip, bobYieldAfterTransferAndTimeskip);
    //     // token.logUserState(alice, "alice after mint2 and accrueYield");
    //     // console2.log("before burn2");
    //     // token.exposed_burn(alice, MINT_AMOUNT);
    //     // token.accrueYield(alice);
    //     // token.logUserState(alice, "alice after burn2 and accrueYield");

    // }

    // function test_scenario_mintAndTransferInSameBlock_2() public {
    //     // setup - bob & alice have equal amount
    //     token.exposed_mint(alice, MINT_AMOUNT);
    //     token.exposed_mint(bob, MINT_AMOUNT);
    //     _timeskip();
    //     _depositYield(YIELD_AMOUNT);
    //     token.accrueYield(alice);
    //     uint256 bob1 = token.getUserState(bob).yieldAccrued;
    //     token.accrueYield(bob);
    //     uint256 bob2 = token.getUserState(bob).yieldAccrued;
    //     _transferFrom(bob, charlie, token.balanceOf(bob));
    //     _timeskip();
    //     token.accrueYield(bob);
    //     uint256 bobBefore3 = token.getUserState(bob).yieldAccrued;
    //     _depositYield(YIELD_AMOUNT);
    //     token.accrueYield(bob);
    //     uint256 bob3 = token.getUserState(bob).yieldAccrued;
    //     console2.log("bob1:\t%d", bob1);
    //     console2.log("bob2:\t%d", bob2);
    //     console2.log("bobBefore3:\t%d", bobBefore3);
    //     console2.log("bob3:\t%d", bob3);
    // }

    function test_scenario_mintAndTransferInSameBlock_3() public {
        // setup - bob & alice have equal amount
        token.exposed_mint(alice, MINT_AMOUNT);
        _timeskip();
        console2.log("depositing yield 1");
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

}
