// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../src/interfaces/ISupraRouterContract.sol";
import "../src/spin/DateTime.sol";
import "../src/spin/Spin.sol";
import "../src/spin/Raffle.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract RaffleTest is Test {
    Spin spin;
    ISupraRouterContract supraRouter;
    DateTime dateTime;

    address constant ADMIN = address(0x1);
    address constant USER = address(0x2);
    address constant SUPRA_ORACLE = address(0x6D46C098996AD584c9C40D6b4771680f54cE3726);
    address constant DEPOSIT_CONTRACT = address(0x3B5F96986389f6BaCF58d5b69425fab000D3551e);
    address constant SUPRA_OWNER = address(0x578DD059Ec425F83cCCC3149ed594d4e067A5307);

    function setup() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));

        // Deploy the Spin contract
        vm.prank(ADMIN);
        spin = new Spin();

        vm.prank(ADMIN);
        Raffle raffle = new Raffle();

        vm.prank(ADMIN);
        raffle.initialize(address(spin), SUPRA_ORACLE);

        assertTrue(raffle.hasRole(raffle.DEFAULT_ADMIN_ROLE(), ADMIN), "ADMIN is not the contract admin");
    }

    // function testAddPrize() public {
        
    // }
}