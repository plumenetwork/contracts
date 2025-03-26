// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Spin} from "../src/spin/Spin.sol";

contract MonitorCallbackScript is Script {
    Spin spin;
    address constant SPIN_CONTRACT = 0x5cFADCC362b7696CEBAeD6aC7b9dC5Bdc6f8789c;
    
    function setUp() public {}

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);
        
        // Connect to the existing Spin contract
        spin = Spin(SPIN_CONTRACT);
        
        console.log("Connected to Spin contract at:", address(spin));
        console.log("Caller address:", deployer);
        
        // Log user data before spin
        logUserData("BEFORE SPIN", deployer);
        
        // Get current block and timestamp for reference
        console.log("Current block:", block.number);
        console.log("Current timestamp:", block.timestamp);
        
        // Call startSpin and get the nonce - WILL BROADCAST TO TESTNET
        console.log("Broadcasting startSpin transaction to testnet...");
        vm.startBroadcast(privateKey);
        uint256 nonce;
        try spin.startSpin() returns (uint256 _nonce) {
            nonce = _nonce;
            console.log("Spin started successfully with nonce:", nonce);
        } catch Error(string memory reason) {
            console.log("Transaction reverted with reason:", reason);
            vm.stopBroadcast();
            return;
        } catch (bytes memory) {
            console.log("Transaction reverted with no reason");
            vm.stopBroadcast();
            return;
        }
        vm.stopBroadcast();
        
        console.log("Transaction broadcast complete.");
        console.log("IMPORTANT: The callback occurs in a separate transaction initiated by Supra Router.");
        console.log("Watch the testnet explorer for new blocks and check contract state after some time.");
        console.log("NOTE: On a quiet Arbitrum testnet, you may need to wait for blocks to be produced.");
        
        // Cannot reliably monitor in Forge script after broadcast, so provide instructions
        console.log("\nTo check if spin completed, wait a few minutes then run the following command:");
        console.log("cast call --rpc-url $PLUME_TESTNET_RPC_URL 0x5cFADCC362b7696CEBAeD6aC7b9dC5Bdc6f8789c \"getUserData(address)(uint256,uint256,uint256,uint256,uint256,uint256,uint256)\" <your-address>");
        console.log("\nCompare the lastSpinTimestamp with the current time to see if the callback executed.");
    }
    
    function logUserData(string memory label, address user) internal view {
        (
            uint256 dailyStreak,
            uint256 lastSpinTimestamp,
            uint256 jackpotWins,
            uint256 raffleTicketsGained,
            uint256 raffleTicketsBalance,
            uint256 xpGained,
            uint256 smallPlumeTokens
        ) = spin.getUserData(user);
        
        console.log("--- User Data %s ---", label);
        console.log("Daily Streak:", dailyStreak);
        console.log("Last Spin Timestamp:", lastSpinTimestamp);
        console.log("Jackpot Wins:", jackpotWins);
        console.log("Raffle Tickets Gained:", raffleTicketsGained);
        console.log("Raffle Tickets Balance:", raffleTicketsBalance);
        console.log("XP Gained:", xpGained);
        console.log("Plume Tokens:", smallPlumeTokens);
        console.log("-----------------");
    }
} 