// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";
import {Spin} from "../src/spin/Spin.sol";
import {ISupraRouterContract} from "../src/interfaces/ISupraRouterContract.sol";

contract TraceSupraCallScript is Script {
    Spin spin;
    address constant SPIN_CONTRACT = 0x5cFADCC362b7696CEBAeD6aC7b9dC5Bdc6f8789c;

    // Flag to control if we mock the Supra Router
    bool useMockSupraRouter = false;

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
        
        if (useMockSupraRouter) {
            // This section would require admin access to modify the contract
            console.log("Mock Supra Router option is disabled. This requires admin access.");
        }
        
        // Set a specific gas limit to prevent running out of gas
        uint256 gasLimit = 1_000_000; // 1M gas
        
        // Get the address of the Supra Router by analyzing storage
        address supraRouterAddress = getSupraRouterAddress();
        console.log("Supra Router address:", supraRouterAddress);
        
        // Trace the Supra Router generate request directly
        if (supraRouterAddress != address(0)) {
            try this.traceSupraCall(supraRouterAddress, deployer) {
                console.log("Supra call tracing completed");
            } catch Error(string memory reason) {
                console.log("Supra call tracing failed with reason:", reason);
            } catch (bytes memory lowLevelData) {
                console.log("Supra call tracing failed with no reason");
                console.logBytes(lowLevelData);
            }
        }
        
        // Try calling startSpin with explicit gas limit
        console.log("Calling startSpin with gas limit:", gasLimit);
        try spin.startSpin{gas: gasLimit}() returns (uint256 nonce) {
            console.log("Spin started successfully with nonce:", nonce);
        } catch Error(string memory reason) {
            console.log("Transaction reverted with reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("Transaction reverted with no reason or out of gas");
            console.logBytes(lowLevelData);
        }
        
        vm.stopBroadcast();
    }
    
    // This function attempts to extract the Supra Router address from storage
    // Note: This is an approximation as it depends on the exact storage layout
    function getSupraRouterAddress() public view returns (address) {
        address routerAddress = address(0);
        
        // Try to use storage inspection to find the Supra Router address
        // This is a bit of a hack and might not work depending on the exact storage layout
        bytes32 slot = 0x35fc247836aa7388208f5bf12c548be42b83fa7b653b6690498b1d90754d0b00; // SPIN_STORAGE_LOCATION
        
        // The Supra Router might be several slots in, we attempt to find it
        // This is simplistic and might need adjustment
        for (uint i = 0; i < 10; i++) {
            bytes32 value = vm.load(address(spin), bytes32(uint256(slot) + i));
            address potentialAddress = address(uint160(uint256(value)));
            
            // Crude check: If it looks like a valid address, log it
            if (potentialAddress != address(0) && potentialAddress != address(spin)) {
                console.log("Potential address found at slot", i, ":", potentialAddress);
                
                // Try to see if this behaves like the Supra Router
                // This is very simplistic and might not work
                if (i == 7) { // Based on contract structure, supraRouter might be at slot 7
                    routerAddress = potentialAddress;
                }
            }
        }
        
        return routerAddress;
    }
    
    // Function to trace a call to the Supra Router directly
    function traceSupraCall(address supraRouterAddress, address clientWallet) external {
        console.log("Tracing Supra Router call directly...");
        
        ISupraRouterContract supraRouter = ISupraRouterContract(supraRouterAddress);
        
        string memory callbackSignature = "handleRandomness(uint256,uint256[])";
        uint8 rngCount = 1;
        uint256 numConfirmations = 1;
        uint256 clientSeed = uint256(keccak256(abi.encodePacked(clientWallet, block.timestamp)));
        
        console.log("Calling generateRequest with:");
        console.log("  callbackSignature:", callbackSignature);
        console.log("  rngCount:", rngCount);
        console.log("  numConfirmations:", numConfirmations);
        console.log("  clientSeed:", clientSeed);
        console.log("  clientWallet:", clientWallet);
        
        try supraRouter.generateRequest(
            callbackSignature,
            rngCount,
            numConfirmations,
            clientSeed,
            clientWallet
        ) returns (uint256 nonce) {
            console.log("Supra Router generateRequest succeeded with nonce:", nonce);
        } catch Error(string memory reason) {
            console.log("Supra Router call failed with reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("Supra Router call failed with no reason");
            console.logBytes(lowLevelData);
        }
    }
} 