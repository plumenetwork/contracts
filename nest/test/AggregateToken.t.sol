// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/AggregateToken.sol";
import "../src/interfaces/IComponentToken.sol";

interface IUSDT is IERC20 {
    function decimals() external view returns (uint8);
    function mint(address to, uint256 amount) external;
}

interface IUSDC is IERC20 {
    function decimals() external view returns (uint8);
    function mint(address to, uint256 amount) external;
}

interface ICredbullVault is IComponentToken {
    function noticePeriod() external view returns (uint256);
    function currentPeriod() external view returns (uint256);
    function balanceOf(address account, uint256 id) external view returns (uint256);
    function requestDeposit(uint256 assets, address controller, address owner) external returns (uint256);
    function requestRedeem(uint256 shares, address controller, address owner) external returns (uint256);
    function deposit(uint256 assets, address receiver, address controller) external returns (uint256);
    function redeem(uint256 shares, address receiver, address controller) external returns (uint256);
}

contract AggregateTokenTest is Test {
    // Deployed contracts
    AggregateToken public aggregateToken;
    ICredbullVault public constant credbullVault = ICredbullVault(0x4B1fC984F324D2A0fDD5cD83925124b61175f5C6);
    
    // Plume Testnet token addresses
    IUSDT public constant USDT = IUSDT(0x2413b8C79Ce60045882559f63d308aE3DFE0903d);
    IUSDC public constant USDC = IUSDC(0x401eCb1D350407f13ba348573E5630B83638E30D);
    
    // Test accounts
    address public owner = address(0x1);
    address public user = address(0x2);
    
    // Constants
    uint256 constant INITIAL_BALANCE = 1_000_000e6; // 1M USDT/USDC
    uint256 constant TEST_AMOUNT = 10_000e6; // 10k USDT
    uint256 constant BASE = 1e18;
    uint256 constant CHAIN_ID = 161221135; // Plume testnet

    function setUp() public {
        // Fork Plume testnet
        vm.createSelectFork(vm.envString("PLUME_RPC_URL"), CHAIN_ID);
        
        // Setup accounts
        vm.startPrank(owner);
        
        // Deploy AggregateToken
        aggregateToken = new AggregateToken();
        aggregateToken.initialize(
            owner,
            "Aggregate USD",
            "aUSD",
            IComponentToken(address(credbullVault)),
            BASE, // 1:1 ask price
            BASE  // 1:1 bid price
        );
        
        // Setup initial token balances
        vm.deal(user, 100 ether); // Give some ETH for gas
        vm.startPrank(address(USDT));
        USDT.mint(user, INITIAL_BALANCE);
        vm.stopPrank();
        
        vm.startPrank(address(USDC));
        USDC.mint(address(aggregateToken), INITIAL_BALANCE);
        vm.stopPrank();
        
        // Approve tokens
        vm.startPrank(user);
        USDT.approve(address(aggregateToken), type(uint256).max);
        vm.stopPrank();
        
        // Approve AggregateToken to interact with Credbull vault
        aggregateToken.approveComponentToken(IComponentToken(address(credbullVault)), type(uint256).max);
        
        vm.stopPrank();

        // Log initial state
        console.log("Test Setup Complete");
        console.log("USDT balance of user:", USDT.balanceOf(user));
        console.log("USDC balance of AggregateToken:", USDC.balanceOf(address(aggregateToken)));
    }

    function testBuyCredbullFlow() public {
        vm.startPrank(user);
        
        // Record initial states
        uint256 initialUsdtBalance = USDT.balanceOf(user);
        uint256 currentPeriod = credbullVault.currentPeriod();
        
        console.log("Starting Buy Flow");
        console.log("Initial USDT Balance:", initialUsdtBalance);
        console.log("Current Period:", currentPeriod);
        
        // Step 1: User deposits USDT to get aUSD (AggregateToken shares)
        uint256 aggregateShares = aggregateToken.deposit(TEST_AMOUNT, user, user);
        
        console.log("Aggregate Shares Received:", aggregateShares);
        
        assertEq(USDT.balanceOf(user), initialUsdtBalance - TEST_AMOUNT, "USDT not transferred");
        assertEq(aggregateToken.balanceOf(user), aggregateShares, "Aggregate shares not received");
        
        // Step 2: AggregateToken buys Credbull vault shares
        uint256 initialAggregateBalance = aggregateToken.balanceOf(user);
        
        // First need to request deposit due to async nature
        uint256 requestId = credbullVault.requestDeposit(
            TEST_AMOUNT,
            address(aggregateToken),
            address(aggregateToken)
        );
        
        console.log("Deposit Request ID:", requestId);
        
        // Wait for deposit to be ready
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1 hours);
        
        // Complete deposit
        aggregateToken.buyComponentToken(IComponentToken(address(credbullVault)), TEST_AMOUNT);
        
        // Verify Credbull vault shares received
        uint256 credbullShares = credbullVault.balanceOf(address(aggregateToken), currentPeriod);
        console.log("Credbull Shares Received:", credbullShares);
        
        assertGt(credbullShares, 0, "No Credbull shares received");
        assertEq(aggregateToken.balanceOf(user), initialAggregateBalance, "Aggregate token balance changed unexpectedly");
        
        vm.stopPrank();
    }

    function testSellCredbullFlow() public {
        // First buy some Credbull shares
        testBuyCredbullFlow();
        
        vm.startPrank(user);
        
        console.log("Starting Sell Flow");
        uint256 currentPeriod = credbullVault.currentPeriod();
        
        // Step 1: Calculate initial balances
        uint256 initialAggregateBalance = aggregateToken.balanceOf(user);
        uint256 initialCredbullShares = credbullVault.balanceOf(address(aggregateToken), currentPeriod);
        
        console.log("Initial Credbull Shares:", initialCredbullShares);
        
        // Step 2: Request redemption from Credbull vault
        uint256 requestId = credbullVault.requestRedeem(
            initialCredbullShares,
            address(aggregateToken),
            address(aggregateToken)
        );
        
        console.log("Redeem Request ID:", requestId);
        
        // Wait for notice period
        uint256 noticePeriod = credbullVault.noticePeriod();
        console.log("Notice Period:", noticePeriod);
        
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + noticePeriod + 1);
        
        // Step 3: Complete redemption through AggregateToken
        aggregateToken.sellComponentToken(
            IComponentToken(address(credbullVault)),
            initialCredbullShares
        );
        
        // Verify final state
        assertEq(credbullVault.balanceOf(address(aggregateToken), currentPeriod), 0, "Credbull shares not sold");
        assertEq(aggregateToken.balanceOf(user), initialAggregateBalance, "Aggregate token balance changed unexpectedly");
        
        // Step 4: Redeem aggregate tokens back to USDT
        uint256 initialUsdtBalance = USDT.balanceOf(user);
        uint256 redeemAmount = aggregateToken.balanceOf(user);
        
        aggregateToken.redeem(redeemAmount, user, user);
        
        uint256 finalUsdtBalance = USDT.balanceOf(user);
        console.log("Initial USDT Balance:", initialUsdtBalance);
        console.log("Final USDT Balance:", finalUsdtBalance);
        
        assertEq(aggregateToken.balanceOf(user), 0, "Aggregate tokens not burned");
        assertGt(finalUsdtBalance, initialUsdtBalance, "USDT not received back");
        
        vm.stopPrank();
    }

    function testQueryVaultInfo() public {
        // Get vault info
        address vaultAsset = credbullVault.asset();
        uint256 noticePeriod = credbullVault.noticePeriod();
        uint256 currentPeriod = credbullVault.currentPeriod();
        uint256 totalAssets = credbullVault.totalAssets();
        
        console.log("Vault Info:");
        console.log("Vault Asset:", vaultAsset);
        console.log("Notice Period:", noticePeriod);
        console.log("Current Period:", currentPeriod);
        console.log("Total Assets:", totalAssets);
    }
}