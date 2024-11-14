// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/ComponentToken.sol";
import "../src/token/pUSD.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { MockVault } from "../src/mocks/MockVault.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("USDC", "USDC") {
        _mint(msg.sender, 1_000_000_000000); // 1M USDC
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract ComponentTokenTest is Test {
   pUSD public implementation;
    pUSD public token;
    MockUSDC public usdc;
    MockVault public vault;
    address public owner;
    address public alice;
    address public bob;

    event PrecisionLossDetected(
        string scenario,
        uint256 expectedShares,
        uint256 actualShares,
        uint256 precisionLoss
    );

     function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        
        // Deploy contracts
        usdc = new MockUSDC();
        vault = new MockVault();
        
   // Deploy implementation
        implementation = new pUSD();
        
        // Deploy proxy with initialization
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(pUSD.initialize, (owner, IERC20(address(usdc)), address(vault)))
        );
        
        // Set token to proxy address
        token = pUSD(address(proxy));

        // Distribute USDC
        usdc.transfer(alice, 100_000_000000); // 100k USDC
        usdc.transfer(bob, 100_000_000000);   // 100k USDC

        // Verify setup
        require(address(token.asset()) == address(usdc), "Wrong asset");
        require(token.vault() == address(vault), "Wrong vault");
    }

    function testInitialDeposit() public {
        console.log("=== Testing Initial Deposit Scenarios ===");
        
        // Test tiny initial deposit
        vm.startPrank(alice);
        usdc.approve(address(token), 1); // 0.000001 USDC
        
        // This should revert due to tiny amount
        vm.expectRevert();
        token.deposit(1, alice, alice);
        vm.stopPrank();

        // Test proper initial deposit
        vm.startPrank(alice);
        uint256 depositAmount = 1000_000000; // 1000 USDC
        usdc.approve(address(token), depositAmount);
        
        uint256 sharesBefore = token.totalSupply();
        token.deposit(depositAmount, alice, alice);
        uint256 sharesAfter = token.totalSupply();
        
        console.log("Initial deposit:");
        console.log("- Amount: %s USDC", depositAmount / 1e6);
        console.log("- Shares minted: %s", sharesAfter - sharesBefore);
        vm.stopPrank();
    }

    function testMultipleDeposits() public {
        console.log("\n=== Testing Multiple Deposits ===");
        
        // Initial state
        _initialDeposit(alice, 1000_000000); // 1000 USDC

        // Series of deposits
        uint256[] memory deposits = new uint256[](4);
        deposits[0] = 10_000000;     // 10 USDC
        deposits[1] = 100_000000;    // 100 USDC
        deposits[2] = 1000_000000;   // 1000 USDC
        deposits[3] = 50_000000;     // 50 USDC

        for (uint i = 0; i < deposits.length; i++) {
            vm.startPrank(bob);
            usdc.approve(address(token), deposits[i]);
            
            uint256 sharesBefore = token.totalSupply();
            uint256 startGas = gasleft();
            
            token.deposit(deposits[i], bob, bob);
            
            uint256 gasUsed = startGas - gasleft();
            uint256 sharesAfter = token.totalSupply();
            
            console.log("\nDeposit %s:", i + 1);
            console.log("- Amount: %s USDC", deposits[i] / 1e6);
            console.log("- Shares minted: %s", sharesAfter - sharesBefore);
            console.log("- Gas used: %s", gasUsed);
            
            vm.stopPrank();
        }
    }

    function testRedeemScenarios() public {
        console.log("\n=== Testing Redeem Scenarios ===");
        
        // Setup initial state
        _initialDeposit(alice, 1000_000000); // 1000 USDC
        
        // Test partial redeem
        vm.startPrank(alice);
        uint256 redeemAmount = 500_000000; // 500 USDC worth of shares
        
        uint256 balanceBefore = usdc.balanceOf(alice);
        uint256 sharesBefore = token.balanceOf(alice);
        
        token.redeem(redeemAmount, alice, alice);
        
        uint256 balanceAfter = usdc.balanceOf(alice);
        uint256 sharesAfter = token.balanceOf(alice);
        
        console.log("Partial redeem:");
        console.log("- Shares burned: %s", sharesBefore - sharesAfter);
        console.log("- USDC received: %s", (balanceAfter - balanceBefore) / 1e6);
        vm.stopPrank();
    }

    function testPrecisionLossScenarios() public {
        console.log("\n=== Testing Precision Loss Scenarios ===");
        
        // Setup with small initial liquidity
        _initialDeposit(alice, 10_000000); // 10 USDC
        
        // Test deposits of varying sizes
        uint256[] memory testAmounts = new uint256[](3);
        testAmounts[0] = 1_000000;     // 1 USDC
        testAmounts[1] = 100_000000;   // 100 USDC
        testAmounts[2] = 1000_000000;  // 1000 USDC

        for (uint i = 0; i < testAmounts.length; i++) {
            vm.startPrank(bob);
            usdc.approve(address(token), testAmounts[i]);
            
            uint256 expectedShares = token.previewDeposit(testAmounts[i]);
            token.deposit(testAmounts[i], bob, bob);
            uint256 actualShares = token.balanceOf(bob);
            
            if (expectedShares != actualShares) {
                emit PrecisionLossDetected(
                    string(abi.encodePacked("Test ", uint8(i + 48))),
                    expectedShares,
                    actualShares,
                    expectedShares - actualShares
                );
            }
            
            console.log("\nPrecision test %s:", i + 1);
            console.log("- Deposit amount: %s USDC", testAmounts[i] / 1e6);
            console.log("- Expected shares: %s", expectedShares);
            console.log("- Actual shares: %s", actualShares);
            
            vm.stopPrank();
        }
    }

    function testStressTest() public {
        console.log("\n=== Stress Testing ===");
        
        // Initial setup
        _initialDeposit(alice, 1000_000000); // 1000 USDC
        
        // Multiple rapid deposits and redeems
        for (uint i = 0; i < 5; i++) {
            vm.startPrank(bob);
            uint256 depositAmount = 100_000000 * (i + 1); // Increasing deposits
            usdc.approve(address(token), depositAmount);
            token.deposit(depositAmount, bob, bob);
            
            uint256 redeemAmount = token.balanceOf(bob) / 2;
            token.redeem(redeemAmount, bob, bob);
            
            console.log("\nStress test iteration %s:", i + 1);
            console.log("- Deposit amount: %s USDC", depositAmount / 1e6);
            console.log("- Redeem amount: %s shares", redeemAmount);
            console.log("- Total supply: %s", token.totalSupply());
            vm.stopPrank();
        }
    }

    // Helper function for initial deposit
    function _initialDeposit(address user, uint256 amount) internal {
        vm.startPrank(user);
        usdc.approve(address(token), amount);
        token.deposit(amount, user, user);
        vm.stopPrank();
    }

    // Helper to calculate expected shares
    function _calculateExpectedShares(
        uint256 depositAmount
    ) internal view returns (uint256) {
        uint256 totalSupply = token.totalSupply();
        if (totalSupply == 0) return depositAmount;
        
        uint256 totalAssets = token.totalAssets();
        return (depositAmount * totalSupply) / totalAssets;
    }
}