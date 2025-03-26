// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Spin} from "../src/spin/Spin.sol";
import {ISupraRouterContract} from "../src/interfaces/ISupraRouterContract.sol";

contract MockSupraRouter {
    function generateRequest(
        string memory callbackSignature,
        uint8 rngCount,
        uint256 numConfirmations,
        uint256 clientSeed,
        address admin
    ) external returns (uint256) {
        console.log("Mock Supra Router generateRequest called");
        console.log("  callbackSignature:", callbackSignature);
        console.log("  rngCount:", rngCount);
        console.log("  numConfirmations:", numConfirmations);
        console.log("  clientSeed:", clientSeed);
        console.log("  admin:", admin);
        
        // Return a mock nonce
        return 12345;
    }
}

contract DebugSpinScript is Script {
    Spin spin;
    address constant SPIN_CONTRACT = 0x5cFADCC362b7696CEBAeD6aC7b9dC5Bdc6f8789c;
    bool useMockRouter = false; // Set to true to use mock router

    function setUp() public {}

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);
        
        // Enable tracing for detailed debugging
        vm.recordLogs();
        
        // Start the prank to impersonate the deployer
        vm.startBroadcast(privateKey);
        
        // Connect to the existing Spin contract
        spin = Spin(SPIN_CONTRACT);
        
        console.log("Connected to Spin contract at:", address(spin));
        console.log("Caller address:", deployer);
        
        // Log contract state before the call
        logUserData(deployer);
        
        if (useMockRouter) {
            // Deploy mock Supra Router and replace in the contract (for testing purposes)
            // This would need admin access to the contract, so likely won't work
            // Just kept here as an example approach for debugging
            console.log("Using mock router is disabled. Enable in script if needed.");
        }
        
        // Set a reasonable gas limit to prevent transaction from running too long
        uint256 gasLimit = 10_000_000; // 10M gas
        
        // Call the startSpin function with a gas limit
        console.log("Calling startSpin with gas limit:", gasLimit);
        console.log("Gas price:", tx.gasprice);
        console.log("Current block:", block.number);
        console.log("Current timestamp:", block.timestamp);
        
        // Try to call startSpin with explicit gas limit
        try spin.startSpin{gas: gasLimit}() returns (uint256 nonce) {
            console.log("Spin started successfully with nonce:", nonce);
        } catch Error(string memory reason) {
            console.log("Transaction reverted with reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("Transaction reverted with no reason");
            console.logBytes(lowLevelData);
        }
        
        vm.stopBroadcast();
    }
    
    function logUserData(address user) internal view {
        (
            uint256 dailyStreak,
            uint256 lastSpinTimestamp,
            uint256 jackpotWins,
            uint256 raffleTicketsGained,
            uint256 raffleTicketsBalance,
            uint256 xpGained,
            uint256 smallPlumeTokens
        ) = spin.getUserData(user);
        
        console.log("--- User Data ---");
        console.log("Daily Streak:", dailyStreak);
        console.log("Last Spin Timestamp:", lastSpinTimestamp);
        console.log("Last Spin Date:", formatTimestamp(lastSpinTimestamp));
        console.log("Current Date:", formatTimestamp(block.timestamp));
        console.log("Jackpot Wins:", jackpotWins);
        console.log("Raffle Tickets Gained:", raffleTicketsGained);
        console.log("Raffle Tickets Balance:", raffleTicketsBalance);
        console.log("XP Gained:", xpGained);
        console.log("Plume Tokens:", smallPlumeTokens);
        console.log("-----------------");
    }
    
    function formatTimestamp(uint256 timestamp) internal pure returns (string memory) {
        if (timestamp == 0) return "Never";
        
        // This is pseudo-code as Solidity doesn't have date formatting built-in
        // In a real implementation, you'd need a proper date library
        return vm.toString(timestamp);
    }
} 