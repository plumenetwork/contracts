// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { MockVault } from "../src/mocks/MockVault.sol";
import { pUSD } from "../src/token/pUSD.sol";

import { IAtomicQueue } from "../src/interfaces/IAtomicQueue.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

contract pUSDPlumeTest is Test {

    pUSD public token;
    IERC20 public asset;
    IERC4626 public vault;

    address public owner;
    address public user1;
    address public user2;

    // Constants for deployed contracts
    address constant USDC_ADDRESS = 0x401eCb1D350407f13ba348573E5630B83638E30D;
    address constant VAULT_ADDRESS = 0xe644F07B1316f28a7F134998e021eA9f7135F351;
    address constant TELLER_ADDRESS = 0xE010B6fdcB0C1A8Bf00699d2002aD31B4bf20B86;
    address constant ATOMIC_QUEUE_ADDRESS = 0x9fEcc2dFA8B64c27B42757B0B9F725fe881Ddb2a;

    address constant PUSD_PROXY = 0x2DEc3B6AdFCCC094C31a2DCc83a43b5042220Ea2;

    event VaultChanged(IERC4626 indexed oldVault, IERC4626 indexed newVault);

    function setUp() public {
        // Fork Plume testnet
        string memory PLUME_RPC = vm.envString("PLUME_RPC_URL");
        vm.createSelectFork(PLUME_RPC);

        // Setup accounts using the private key
        uint256 privateKey = 0xf1906c3250e18e8036273019f2d6d4d5107404b84753068fe8fb170674461f1b;
        owner = vm.addr(privateKey);
        user1 = vm.addr(privateKey);
        user2 = address(0x2);

        // Set the default signer for all transactions
        vm.startPrank(owner, owner);

        // Connect to deployed contracts
        token = pUSD(PUSD_PROXY);
        asset = IERC20(USDC_ADDRESS);
        vault = IERC4626(VAULT_ADDRESS);
        IAtomicQueue atomicQueue = IAtomicQueue(ATOMIC_QUEUE_ADDRESS);

        deal(address(asset), owner, 1000e6);

        // Approve all necessary contracts
        asset.approve(address(token), type(uint256).max);
        asset.approve(address(vault), type(uint256).max);
        asset.approve(TELLER_ADDRESS, type(uint256).max);

        /*
        // Additional setup for the vault if needed
        if (IAccessControl(address(vault)).hasRole(keccak256("APPROVER_ROLE"), owner)) {
            vault.approve(address(token), type(uint256).max);
            vault.approve(TELLER_ADDRESS, type(uint256).max);
        }
        */

        vm.stopPrank();
    }

    function testDeposit() public {
        uint256 depositAmount = 1e6;
        uint256 minimumMint = depositAmount;

        // Setup
        deal(address(asset), user1, depositAmount * 2);

        vm.startPrank(user1);

        // Approve both token and vault
        asset.approve(address(token), type(uint256).max);
        asset.approve(address(vault), type(uint256).max);
        asset.approve(TELLER_ADDRESS, type(uint256).max);

        // Additional approval needed for the vault to transfer from pUSD
        vm.stopPrank();

        // Add approval from pUSD to vault
        vm.startPrank(address(token));
        asset.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user1);

        console.log("Asset balance before deposit:", asset.balanceOf(user1));
        console.log("Asset allowance for token:", asset.allowance(user1, address(token)));
        console.log("Asset allowance for vault:", asset.allowance(user1, address(vault)));
        console.log("Asset allowance for teller:", asset.allowance(user1, TELLER_ADDRESS));

        // Deposit
        uint256 shares = token.deposit(depositAmount, user1, user1, minimumMint);

        console.log("Shares received:", shares);
        // TODO: Add assertions

        //console.log("pUSD balance after deposit:", token.balanceOf(user1));
        //console.log("Asset balance in vault:", asset.balanceOf(address(vault)));
        //assertEq(shares, depositAmount);
        //assertEq(token.balanceOf(user1), depositAmount);
        //assertEq(asset.balanceOf(address(vault)), depositAmount);

        vm.stopPrank();
    }

    function testRedeem() public {
        uint256 depositAmount = 1e6;
        uint256 price = 1e6; // 1:1 price
        uint256 minimumMint = depositAmount;

        // Setup
        deal(address(asset), user1, depositAmount);

        vm.startPrank(user1);

        // Approve all necessary contracts
        asset.approve(address(token), type(uint256).max);
        asset.approve(address(vault), type(uint256).max);
        asset.approve(TELLER_ADDRESS, type(uint256).max);

        // Additional approval needed for the vault to transfer from pUSD
        vm.stopPrank();
        vm.startPrank(address(token));
        asset.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user1);

        // Perform deposit and redeem
        token.deposit(depositAmount, user1, user1, minimumMint);
        token.redeem(depositAmount, user1, user1, price);

        vm.stopPrank();

        // TODO: warp time and verify final state
    }

    function testTransfer() public {
        uint256 amount = 1e6;

        // Setup initial balance
        deal(address(asset), user1, amount * 2);

        vm.startPrank(address(token));
        asset.approve(address(vault), type(uint256).max);
        asset.approve(TELLER_ADDRESS, type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user1);

        // First approve and deposit
        asset.approve(address(token), type(uint256).max);
        asset.approve(address(vault), type(uint256).max);
        asset.approve(TELLER_ADDRESS, type(uint256).max);

        token.deposit(amount, user1, user1, amount);

        // Now test transfer
        uint256 preBalance = token.balanceOf(user1);
        token.transfer(user2, amount);

        assertEq(token.balanceOf(user1), preBalance - amount);
        assertEq(token.balanceOf(user2), amount);

        vm.stopPrank();
    }

    function testVaultIntegration() public {
        uint256 amount = 1e6;

        vm.startPrank(user1);
        token.deposit(amount, user1, user1);
        //token.transfer(user2, amount);
        vm.stopPrank();

        //assertEq(vault.balanceOf(user1), 0);
        //assertEq(vault.balanceOf(user2), amount);
        //assertEq(asset.balanceOf(address(vault)), amount);
    }

    function testVault() public {
        // Verify the vault address matches what we set in setUp
        assertEq(address(token.getVault()), address(VAULT_ADDRESS));
        assertEq(address(token.getTeller()), address(TELLER_ADDRESS));
        assertEq(address(token.getAtomicqueue()), address(ATOMIC_QUEUE_ADDRESS));
    }

    function testSupportsInterface() public {
        // Test for ERC20 interface
        bytes4 erc20InterfaceId = type(IERC20).interfaceId;
        assertTrue(token.supportsInterface(erc20InterfaceId));

        // Test for AccessControl interface
        bytes4 accessControlInterfaceId = type(IAccessControl).interfaceId;
        assertTrue(token.supportsInterface(accessControlInterfaceId));

        // Test for non-supported interface
        bytes4 randomInterfaceId = bytes4(keccak256("random()"));
        assertFalse(token.supportsInterface(randomInterfaceId));
    }
    // small hack to be excluded from coverage report

    function test() public { }

}
