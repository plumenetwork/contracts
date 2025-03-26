// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Spin} from "../src/spin/Spin.sol";

contract TestSpinScript is Script {
    Spin spin;
    address constant SPIN_CONTRACT = 0x5cFADCC362b7696CEBAeD6aC7b9dC5Bdc6f8789c;

    function setUp() public {}

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);
        
        // Start broadcasting transactions
        vm.startBroadcast(privateKey);
        
        // Connect to the existing Spin contract
        spin = Spin(SPIN_CONTRACT);
        
        console.log("Connected to Spin contract at:", address(spin));
        console.log("Caller address:", deployer);
        
        // Log some contract state for debugging
        (
            uint256 dailyStreak,
            uint256 lastSpinTimestamp,
            uint256 jackpotWins,
            uint256 raffleTicketsGained,
            uint256 raffleTicketsBalance,
            uint256 xpGained,
            uint256 smallPlumeTokens
        ) = spin.getUserData(deployer);
        
        console.log("Daily Streak:", dailyStreak);
        console.log("Last Spin Timestamp:", lastSpinTimestamp);
        console.log("Current Timestamp:", block.timestamp);
        
        // Call the startSpin function
        console.log("Calling startSpin...");
        try spin.startSpin() returns (uint256 nonce) {
            console.log("Spin started successfully with nonce:", nonce);
        } catch Error(string memory reason) {
            console.log("Transaction reverted with reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("Transaction reverted with no reason");
            console.logBytes(lowLevelData);
        }
        
        vm.stopBroadcast();
    }
} 