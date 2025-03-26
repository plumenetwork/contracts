// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Spin} from "../src/spin/Spin.sol";

contract GasMonitorScript is Script {
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
        
        // Try different gas limits to find the sweet spot
        uint256[] memory gasLimits = new uint256[](5);
        gasLimits[0] = 200_000;   // 200K gas
        gasLimits[1] = 500_000;   // 500K gas
        gasLimits[2] = 1_000_000; // 1M gas
        gasLimits[3] = 2_000_000; // 2M gas
        gasLimits[4] = 5_000_000; // 5M gas
        
        for (uint i = 0; i < gasLimits.length; i++) {
            uint256 gasLimit = gasLimits[i];
            console.log("\n--- Testing with gas limit:", gasLimit, "---");
            
            // Start a transaction with a gas meter
            uint256 gasStart = gasleft();
            vm.startBroadcast(privateKey);
            
            try spin.startSpin{gas: gasLimit}() returns (uint256 nonce) {
                uint256 gasUsed = gasStart - gasleft();
                console.log("Spin started successfully with nonce:", nonce);
                console.log("Gas used:", gasUsed);
            } catch Error(string memory reason) {
                console.log("Transaction reverted with reason:", reason);
            } catch (bytes memory lowLevelData) {
                if (lowLevelData.length > 0) {
                    console.log("Transaction reverted with no reason or out of gas");
                    console.logBytes(lowLevelData);
                } else {
                    console.log("Out of gas");
                }
            }
            
            vm.stopBroadcast();
            
            // Add a small delay between attempts
            vm.warp(block.timestamp + 1);
        }
        
        // Alternative gas monitoring approach using a simulated call
        console.log("\n--- Simulating startSpin without broadcasting ---");
        vm.startPrank(deployer);
        
        // Estimate gas using a dry run
        try this.estimateStartSpinGas(address(spin)) returns (uint256 gasEstimate) {
            console.log("Estimated gas for startSpin:", gasEstimate);
            console.log("Recommended gas limit (1.5x estimate):", gasEstimate * 3 / 2);
        } catch Error(string memory reason) {
            console.log("Gas estimation failed with reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("Gas estimation failed with no reason");
            console.logBytes(lowLevelData);
        }
        
        vm.stopPrank();
    }
    
    // Function to estimate gas usage of startSpin
    function estimateStartSpinGas(address spinContract) external returns (uint256) {
        Spin spinInstance = Spin(spinContract);
        
        uint256 gasStart = gasleft();
        spinInstance.startSpin();
        uint256 gasEnd = gasleft();
        
        return gasStart - gasEnd;
    }
} 