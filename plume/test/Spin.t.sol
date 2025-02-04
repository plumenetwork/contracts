// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../src/interfaces/ISupraRouterContract.sol";
import "../src/spin/DateTime.sol";
import "../src/spin/Spin.sol";
import "forge-std/Test.sol"; 

contract SpinTest is Test {

    Spin spin;
    ISupraRouterContract supraRouter;
    DateTime dateTime; 

    address constant ADMIN = address(0x1);
    address constant USER = address(0x2);
    address constant SUPRA_ORACLE = address(0x3280Ffd457A354E21A34F7Adf131136bD55E6596);

    uint256 constant COOLDOWN_PERIOD = 86_400;   // 1 day
    uint8 constant RNG_COUNT = 1;
    uint256 constant NUM_CONFIRMATIONS = 1;

    function setUp() public {
        // Fork from mainnet for testing with the deployed Supra Oracle
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));

        // Deploy the DateTime contract from src/DateTime.sol
        dateTime = new DateTime();

        // Deploy the Spin contract
        spin = new Spin();
        spin.initialize(SUPRA_ORACLE, address(dateTime), COOLDOWN_PERIOD);

        vm.prank(ADMIN);
        spin.grantRole(spin.ADMIN_ROLE(), ADMIN);
    }

    function testStartSpin() public {
        vm.prank(USER);
        spin.startSpin();

        // Ensure last spin date is set correctly
        (uint256 streak, uint256 feathers) = spin.getStreakAndFeathers(USER);
        assertEq(streak, 0, "Initial streak should be 0");
        assertEq(feathers, 0, "Initial feathers should be 0");

        // Ensure event emitted
        //vm.expectEmit(true, true, false, false);
        //emit Spin.SpinRequested(1, USER);
    }

    function testHandleRandomness() public {
        // Simulate a spin request
        vm.prank(USER);
        spin.startSpin();

        // Assume VRF callback is received with randomness 42
        uint256[] memory rngList = new uint256[](1);
        //bytes memory b = new bytes(len);
        rngList[0] = 42;

        vm.prank(SUPRA_ORACLE);
        spin.handleRandomness(1, rngList);

        // Ensure feathers & streak updated
        (uint256 streak, uint256 feathers) = spin.getStreakAndFeathers(USER);
        assertGt(feathers, 0, "Feathers should be greater than 0");
        assertEq(streak, 1, "Streak should increment");
    }

    // function testCooldownEnforcement() public {
    //     // Start spin
    //     vm.prank(USER);
    //     spin.startSpin();

    //     // Attempt to spin again within cooldown period
    //     vm.warp(block.timestamp + COOLDOWN_PERIOD - 10);
    //     vm.expectRevert("Can only spin once per day");
    //     vm.prank(USER);
    //     spin.startSpin();
    // }

}
