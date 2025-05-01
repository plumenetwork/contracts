// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./TestUtils.sol";

import {Spin}     from "../src/spin/Spin.sol";
import {DateTime} from "../src/spin/DateTime.sol";
import "../src/helpers/ArbSys.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

/* ──────────────────────────────────────────────────────────── */
/*                          Attacker                          */
/* ──────────────────────────────────────────────────────────── */
contract Attacker {
    Spin public immutable spin;
    constructor(Spin _spin) { spin = _spin; }

    /// Fallback during ETH transfer → tries to re-enter startSpin()
    fallback() external payable {
        try spin.startSpin() {
            revert("re-enter succeeded");
        } catch { }
    }

    /// Entry for the first spin
    function launch() external {
        spin.startSpin();
    }

    receive() external payable {}
}

/* ──────────────────────────────────────────────────────────── */
/*                             Test                             */
/* ──────────────────────────────────────────────────────────── */
contract ReentrancyTest is SpinTestBase {
    function setUp() public {
        // Use SpinTestBase's setupSpin with current timestamp
        uint16 year = 2025;
        uint8 month = 3;
        uint8 day = 8;
        uint8 hour = 10;
        uint8 minute = 0;
        uint8 second = 0;
        
        setupSpin(year, month, day, hour, minute, second);
    }

    function testCannotReenter() public {
        // 1) Deploy attacker
        Attacker atk = new Attacker(spin);

        // 2) Advance one day so canSpin() passes
        vm.warp(block.timestamp + 1 days);

        // 3) Attacker launches the first spin and record logs to get the nonce
        vm.recordLogs();
        vm.prank(address(atk));
        atk.launch();
        
        // Extract nonce using utility function from SpinTestBase
        uint256 nonce = extractNonceFromLogs(vm.getRecordedLogs());
        
        // Make sure we got a valid nonce
        require(nonce != 0, "Failed to get nonce from logs");
        console.log("Extracted nonce:", nonce);

        // 4) Prepare RNG to force "Nothing" (no cooldown)
        uint256[] memory rng = new uint256[](1);
        rng[0] = 999_999;

        // 5) Simulate VRF callback with the correct nonce
        vm.prank(SUPRA_ORACLE);
        spin.handleRandomness(nonce, rng);

        // 6) If fallback re-entered successfully, streak > 1; assert it stayed 1
        (uint256 streak,,,,,,) = spin.getUserData(address(atk));
        assertEq(streak, 1, "Re-entrancy guard failed (streak > 1)");
    }
}
