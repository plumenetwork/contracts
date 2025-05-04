// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../src/mock/MockUSDC.sol";
import { Script } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

/**
 * @title MockUSDC Deployment Script
 * @notice Deploys a mock USDC token for testing purposes
 */
contract DeployMockUSDC is Script, Test {

    // Address of the admin - Update this to your address
    address private constant ADMIN_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;

    // Initial USDC amount to mint (1 million USDC with 6 decimals)
    uint256 public constant INITIAL_USDC_AMOUNT = 1_000_000 * 1e6;

    function test() public { }

    /**
     * @notice Deploys a MockUSDC token and mints an initial supply to the admin
     */
    function run() external {
        vm.startBroadcast(ADMIN_ADDRESS);

        // Deploy the MockUSDC
        MockUSDC mockUSDC = new MockUSDC();
        console2.log("MockUSDC deployed to:", address(mockUSDC));

        // Mint some initial USDC to the admin
        mockUSDC.mint(ADMIN_ADDRESS, INITIAL_USDC_AMOUNT);
        console2.log("Minted", INITIAL_USDC_AMOUNT / 1e6, "USDC to", ADMIN_ADDRESS);

        vm.stopBroadcast();
    }

}
