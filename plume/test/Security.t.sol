// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/* ──────────────────────────────────────────────────────────── */
/*                        VRF Stub (no interface)             */
/* ──────────────────────────────────────────────────────────── */
/// @notice Minimal stub that only provides generateRequest()
contract StubSupra {
    uint256 private next = 1;
    /// @dev Mimics VRF: each call returns a new nonce
    function generateRequest(
        string calldata,  // callbackSignature
        uint8,            // rngCount
        uint256,          // numConfirmations
        uint256,          // clientSeed
        address           // clientAddress
    ) external returns (uint256) {
        return next++;
    }
}

/* ──────────────────────────────────────────────────────────── */
/*                     Contracts under test                    */
/* ──────────────────────────────────────────────────────────── */
import {Spin}     from "../src/spin/Spin.sol";
import {DateTime} from "../src/spin/DateTime.sol";
import "forge-std/Test.sol";

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
contract ReentrancyTest is Test {
    Spin      spin;
    DateTime  dt;
    StubSupra supra;

    function setUp() public {
        // Deploy the DateTime helper and stub VRF
        dt    = new DateTime();
        supra = new StubSupra();

        // Deploy & initialize Spin
        spin  = new Spin();
        spin.initialize(address(supra), address(dt));

        // Enable spins and set campaign start
        spin.setCampaignStartDate(block.timestamp);
        // spin.setEnableSpin(true);

        // Give the Spin contract some ETH to pay out
        vm.deal(address(spin), 10 ether);
    }

    function testCannotReenter() public {
        // 1) Deploy attacker
        Attacker atk = new Attacker(spin);

        // 2) Advance one day so canSpin() passes
        vm.warp(block.timestamp + 1 days);

        // 3) Attacker launches the first spin (queues nonce = 1)
        vm.prank(address(atk));
        atk.launch();

        // 4) Prepare RNG to force “Nothing” (no cooldown)
        uint256[] memory rng = new uint256[](1);
        rng[0] = 999_999;

        // 5) Simulate VRF callback
        vm.prank(address(supra));
        spin.handleRandomness(1, rng);

        // 6) If fallback re-entered successfully, streak > 1; assert it stayed 1
        (uint256 streak,,,,,,) = spin.getUserData(address(atk));
        assertEq(streak, 1, "Re-entrancy guard failed (streak > 1)");
    }
}
