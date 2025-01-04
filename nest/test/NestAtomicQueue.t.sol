// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { NestAtomicQueue } from "../src/vault/NestAtomicQueue.sol";
import { NestBoringVaultModule } from "../src/vault/NestBoringVaultModule.sol";
import { NestBoringVaultModuleTest } from "./NestBoringVaultModuleTest.t.sol";
import { AtomicQueue } from "@boringvault/src/atomic-queue/AtomicQueue.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";

// Add event definitions at the top of the contract
event AtomicRequestUpdated(
    address user,
    address offerToken,
    address wantToken,
    uint256 amount,
    uint256 deadline,
    uint256 minPrice,
    uint256 timestamp
);

contract NestAtomicQueueTest is NestBoringVaultModuleTest {

    NestAtomicQueue public queue;

    uint256 public constant DEADLINE_PERIOD = 1 days;
    uint256 public constant PRICE_PERCENTAGE = 9900; // 99.00%

    using SafeCast for uint256;
    using FixedPointMathLib for uint256;

    function setUp() public override {
        super.setUp();
        /*
        // Deploy NestAtomicQueue
        queue = new NestAtomicQueue(
            address(this), address(vault), address(accountant), asset, DEADLINE_PERIOD, PRICE_PERCENTAGE
        );

        */
    }

    function testInitialization() public override {
        //assertEq(queue.owner(), address(this));
        assertEq(address(queue.vault()), address(vault));
        assertEq(address(queue.accountant()), address(accountant));
        assertEq(address(queue.assetToken()), address(asset));
        assertEq(queue.deadlinePeriod(), DEADLINE_PERIOD);
        assertEq(queue.pricePercentage(), PRICE_PERCENTAGE);
    }
    /*
    function testRequestRedeem(
        uint256 shares
    ) public {
        // Bound shares to reasonable values
        shares = bound(shares, 1e6, 1_000_000e6);

        // Give user some shares in the vault
        deal(address(vault), user, shares);

        // Start as user
        vm.startPrank(user);

        // Approve queue to spend shares
        vault.approve(address(queue), shares);

        // Calculate expected deadline and atomic price
        uint256 expectedDeadline = block.timestamp + DEADLINE_PERIOD;
        uint256 expectedAtomicPrice =
            accountant.getRateInQuote(ERC20(address(asset))).mulDivDown(PRICE_PERCENTAGE, 10_000);

        // Expect AtomicRequestUpdated event
        vm.expectEmit(true, true, true, true);
        emit AtomicRequestUpdated(
            user, // user
            address(vault), // offerToken
            address(asset), // wantToken
            shares, // amount
            expectedDeadline, // deadline
            expectedAtomicPrice, // minPrice
            block.timestamp // timestamp
        );

        // Make redeem request
        uint256 requestId = queue.requestRedeem(shares, user, user);

        // Get request details using getUserAtomicRequest
        AtomicQueue.AtomicRequest memory request =
            queue.getUserAtomicRequest(user, ERC20(address(vault)), ERC20(address(asset)));

        // Verify request details
        assertEq(request.offerAmount, shares);
        assertEq(request.deadline, expectedDeadline);
        assertEq(request.atomicPrice, expectedAtomicPrice);
        assertEq(request.inSolve, false);

        vm.stopPrank();
    }

    function testRequestRedeemZeroShares() public {
        vm.expectRevert(NestBoringVaultModule.InvalidAmount.selector);
        queue.requestRedeem(0, user, user);
    }

    function testRequestRedeemInsufficientBalance(
        uint256 shares
    ) public {
        shares = bound(shares, 1e6, 1_000_000e6);

        vm.startPrank(user);
        vm.expectRevert("TRANSFER_FROM_FAILED");
        queue.requestRedeem(shares, user, user);
        vm.stopPrank();
    }

    function testRequestRedeemInsufficientAllowance(
        uint256 shares
    ) public {
        shares = bound(shares, 1e6, 1_000_000e6);

        // Give user shares but don't approve queue
        deal(address(vault), user, shares);

        vm.startPrank(user);
        vm.expectRevert("TRANSFER_FROM_FAILED");
        queue.requestRedeem(shares, user, user);
        vm.stopPrank();
    }

    function testDepositReverts() public {
        vm.expectRevert(NestBoringVaultModule.Unimplemented.selector);
        queue.deposit(1e6, address(this), address(this));
    }
    */

}
