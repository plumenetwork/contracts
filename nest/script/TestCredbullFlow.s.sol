// scripts/TestCredbullFlow.s.sol

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "../test/AggregateToken.t.sol"; // We can reuse our interfaces

contract TestCredbullFlow is Script {
    // Contract addresses - testnet addresses (same as test)
    address constant USDT_ADDRESS = 0x2413b8C79Ce60045882559f63d308aE3DFE0903d;
    address constant USDC_ADDRESS = 0x401eCb1D350407f13ba348573E5630B83638E30D;
    address constant CREDBULL_ADDRESS = 0x4B1fC984F324D2A0fDD5cD83925124b61175f5C6;

    ICredbullVault public constant CREDBULL_VAULT = ICredbullVault(CREDBULL_ADDRESS);
    IUSDC public constant USDC = IUSDC(USDC_ADDRESS);
    
    // Test parameters
    uint256 constant TEST_AMOUNT = 100000; // 0.1 USDC
    uint256 constant BASE = 1e18;

    function run() external {
        // Get private key from env
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(privateKey);

        console.log("Running Credbull flow with account:", owner);
        console.log("Initial USDC balance:", USDC.balanceOf(owner));

        vm.startBroadcast(privateKey);

        // Deploy implementation
        AggregateToken implementation = new AggregateToken();
        console.log("Implementation deployed at:", address(implementation));
        
        // Initialize with USDC as asset token
        bytes memory initData = abi.encodeCall(
            AggregateToken.initialize,
            (
                owner,
                "Test Aggregate USD",
                "tAUSD",
                IComponentToken(USDC_ADDRESS),
                BASE,
                BASE
            )
        );

        // Deploy proxy
        AggregateTokenProxy proxy = new AggregateTokenProxy(
            address(implementation),
            initData
        );
        console.log("Proxy deployed at:", address(proxy));
        
        AggregateToken token = AggregateToken(address(proxy));

        // Add Credbull vault as component
        token.addComponentToken(IComponentToken(address(CREDBULL_VAULT)));
        console.log("Credbull vault added as component");
        
        // Set up approvals
        USDC.approve(address(token), type(uint256).max);
        USDC.approve(address(CREDBULL_VAULT), type(uint256).max);
        token.approveComponentToken(CREDBULL_VAULT, type(uint256).max);
        CREDBULL_VAULT.setApprovalForAll(address(token), true);
        console.log("Approvals set");

        // Step 1: Deposit USDC to get aggregate tokens
        uint256 shares = token.deposit(TEST_AMOUNT, owner, owner);
        console.log("Deposited", TEST_AMOUNT);
        console.log( "USDC for shares", shares);

        // Step 2: Buy Credbull tokens
        token.buyComponentToken(CREDBULL_VAULT, TEST_AMOUNT);
        console.log("Bought Credbull tokens");

        uint256 currentPeriod = CREDBULL_VAULT.currentPeriod();
        console.log("Current Period:", currentPeriod);

        // Step 3: Request redeem through token
        vm.stopBroadcast();
        vm.startPrank(address(token));

        CREDBULL_VAULT.requestRedeem(
            TEST_AMOUNT,
            address(token),
            address(token)
        );
        console.log("Redeem requested");

        // Note: In real testnet we can't warp time, need to wait naturally
        console.log("Please wait for notice period:", CREDBULL_VAULT.noticePeriod(), "days");
        console.log("Then run the redeem script");

        vm.stopPrank();
        vm.startBroadcast(privateKey);

        vm.stopBroadcast();
    }
}

// Separate script for redeeming after notice period
contract RedeemCredbull is Script {
    address constant CREDBULL_ADDRESS = 0x4B1fC984F324D2A0fDD5cD83925124b61175f5C6;
    uint256 constant TEST_AMOUNT = 100000; // 0.1 USDC

    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(privateKey);
        
        // Get the proxy address from the previous deployment
        address proxyAddress = vm.envAddress("AGGREGATE_TOKEN_PROXY");
        AggregateToken token = AggregateToken(proxyAddress);
        ICredbullVault vault = ICredbullVault(CREDBULL_ADDRESS);

        console.log("Running redeem with account:", owner);
        
        vm.startBroadcast(privateKey);

        // Try to sell component token
        token.sellComponentToken(IComponentToken(CREDBULL_ADDRESS), TEST_AMOUNT);
        console.log("Successfully sold Credbull tokens");

        vm.stopBroadcast();
    }
}