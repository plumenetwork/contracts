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

    bool private skipTests;

    modifier skipIfNoRPC() {
        if (skipTests) {
            vm.skip(true);
        } else {
            _;
        }
    }

    function setUp() public {
        string memory PLUME_RPC = vm.envOr("PLUME_RPC_URL", string(""));
        if (bytes(PLUME_RPC).length == 0) {
            console.log("PLUME_RPC_URL is not defined");
            skipTests = true;

            // Skip all tests if RPC URL is not defined
            vm.skip(false);
            return;
        }

        vm.createSelectFork(PLUME_RPC);

        // Get private key from environment variable
        uint256 privateKey = uint256(vm.envOr("PRIVATE_KEY", bytes32(0)));
        if (privateKey == 0) {
            console.log("PRIVATE_KEY is not defined");
            skipTests = true;
            vm.skip(false);
            return;
        }
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

        vm.stopPrank();
    }

    function testDeposit() public skipIfNoRPC {
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

        vm.stopPrank();
    }

    function testRedeem() public skipIfNoRPC {
        uint256 depositAmount = 1e6;
        uint256 price = 1e6; // 1:1 price
        uint256 minimumMint = depositAmount;
        uint64 deadline = uint64(block.timestamp + 1 hours);

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

        // Step 1: Deposit first
        token.deposit(depositAmount, user1, user1, minimumMint);

        // Step 2: Request redemption
        token.requestRedeem(depositAmount, user1, user1, price, deadline);

        // Step 3: Mock atomic queue notification (in real scenario this would come from the queue)
        vm.stopPrank();
        vm.prank(address(token.getAtomicQueue()));
        token.notifyRedeem(depositAmount, depositAmount, user1);

        // Step 4: Complete redemption
        vm.prank(user1);
        uint256 redeemedAssets = token.redeem(depositAmount, user1, user1);

        // Verify redemption amount
        assertEq(redeemedAssets, depositAmount, "Redeemed assets should match deposit amount");

        vm.stopPrank();
    }

    function testTransfer() public skipIfNoRPC {
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

    function testVaultIntegration() public skipIfNoRPC {
        uint256 amount = 1e6;

        vm.startPrank(user1);
        token.deposit(amount, user1, user1);
        //token.transfer(user2, amount);
        vm.stopPrank();
    }

    function testVault() public skipIfNoRPC {
        // Verify the vault address matches what we set in setUp
        assertEq(address(token.getVault()), address(VAULT_ADDRESS));
        assertEq(address(token.getTeller()), address(TELLER_ADDRESS));
        assertEq(address(token.getAtomicQueue()), address(ATOMIC_QUEUE_ADDRESS));
    }

    function testSupportsInterface() public skipIfNoRPC {
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

}
