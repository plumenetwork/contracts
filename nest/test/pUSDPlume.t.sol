// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { MockVault } from "../src/mocks/MockVault.sol";
import { pUSD } from "../src/token/pUSD.sol";

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

contract TestUSDC is ERC20 {

    constructor() ERC20("USD Coin", "USDC") {
        _mint(msg.sender, 1_000_000 * 10 ** 6);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

}

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
        atomicQueue = IAtomicQueue(ATOMIC_QUEUE_ADDRESS);

        // No need to deal USDC if the account already has balance
        // But we still need the approval
        asset.approve(address(token), type(uint256).max);

        vm.stopPrank();
    }

    function testDeposit() public {
        uint256 depositAmount = 1e6;
        uint256 minimumMint = depositAmount; // 1:1 ratio expected

        vm.startPrank(user1);
        uint256 shares = token.deposit(depositAmount, user1, user1, minimumMint);
        vm.stopPrank();

        assertEq(shares, depositAmount); // Assuming 1:1 ratio
        assertEq(token.balanceOf(user1), depositAmount);
        // Assets should be in the vault, not the token contract
        assertEq(asset.balanceOf(address(vault)), depositAmount);
    }

    function testRedeem() public {
        uint256 depositAmount = 1e6;
        uint256 price = 1e6; // 1:1 price
        uint256 minimumMint = depositAmount;

        // Check initial balance
        uint256 initialBalance = asset.balanceOf(user1);

        vm.startPrank(user1);
        token.deposit(depositAmount, user1, user1, minimumMint);
        token.redeem(depositAmount, user1, user1, price);
        vm.stopPrank();

        assertEq(token.balanceOf(user1), 0);
        // Check final balance matches initial balance
        assertEq(asset.balanceOf(user1), initialBalance);
    }

    function testRedeemFrom() public {
        uint256 amount = 1e6;

        // Setup: user1 deposits tokens
        vm.startPrank(user1);
        token.deposit(amount, user1, user1);

        // user1 approves user2 to spend their tokens
        token.approve(user2, amount);
        vm.stopPrank();

        // Initial balance
        uint256 initialBalance = asset.balanceOf(user2);

        // Check vault balances before redeem
        assertEq(vault.balanceOf(user1), amount);
        assertEq(vault.balanceOf(user2), 0);

        // user2 redeems user1's tokens to user2's address
        vm.prank(user2);
        token.redeem(amount, user2, user1); // user1 is controller (owner of shares), user2 is receiver

        // Verify balances
        assertEq(token.balanceOf(user1), 0);
        assertEq(asset.balanceOf(user2), initialBalance + amount);

        // Verify allowance was decreased
        assertEq(token.allowance(user1, user2), 0);
    }

    function testRedeemFromWithMaxApproval() public {
        uint256 amount = 1e6;

        // Setup: user1 deposits tokens
        vm.startPrank(user1);
        token.deposit(amount, user1, user1);

        // user1 approves user2 to spend max tokens
        token.approve(user2, type(uint256).max);
        vm.stopPrank();

        // Initial balance
        uint256 initialBalance = asset.balanceOf(user2);

        // user2 redeems user1's tokens to user2's address
        vm.prank(user2);
        token.redeem(amount, user2, user1); // user1 is controller, user2 is receiver

        // Verify balances
        assertEq(token.balanceOf(user1), 0);
        assertEq(asset.balanceOf(user2), initialBalance + amount);

        // Verify max allowance remains unchanged
        assertEq(token.allowance(user1, user2), type(uint256).max);
    }

    function testTransfer() public {
        uint256 amount = 1e6;

        vm.startPrank(user1);
        token.deposit(amount, user1, user1);
        token.transfer(user2, amount);
        vm.stopPrank();

        assertEq(token.balanceOf(user1), 0);
        assertEq(token.balanceOf(user2), amount);
    }

    function testVaultIntegration() public {
        uint256 amount = 1e6;

        vm.startPrank(user1);
        token.deposit(amount, user1, user1);
        token.transfer(user2, amount);
        vm.stopPrank();

        assertEq(vault.balanceOf(user1), 0);
        assertEq(vault.balanceOf(user2), amount);
        assertEq(asset.balanceOf(address(vault)), amount);
    }
    /*
    function testSetVault() public {
        // Create a new vault (you might want to deploy a new vault or use another existing one)
        address newVaultAddr = address(0x123); // Replace with actual vault address if testing vault changes

        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user1, token.VAULT_ADMIN_ROLE()
            )
        );
        token.setVault(newVaultAddr);
        vm.stopPrank();

        bytes32 vaultAdminRole = token.VAULT_ADMIN_ROLE();
        token.grantRole(vaultAdminRole, address(this));

        address oldVault = address(token.vault());
        
        emit VaultChanged(IERC4626(oldVault), IERC4626(newVaultAddr));
        
        token.setVault(newVaultAddr);
        assertEq(address(token.vault()), newVaultAddr);
    }
    */

    function testVault() public {
        // Verify the vault address matches what we set in setUp
        assertEq(address(token.vault()), address(vault));
    }

    function testTransferFrom() public {
        uint256 amount = 1e6;

        // Setup: user1 deposits tokens
        vm.startPrank(user1);
        token.deposit(amount, user1, user1);

        // Approve user2 to spend tokens
        token.approve(user2, amount);
        vm.stopPrank();

        // user2 transfers tokens from user1 to themselves
        vm.prank(user2);
        token.transferFrom(user1, user2, amount);

        // Verify balances
        assertEq(token.balanceOf(user1), 0);
        assertEq(token.balanceOf(user2), amount);

        // Verify allowance was decreased
        assertEq(token.allowance(user1, user2), 0);
    }

    function testTransferFromWithMaxApproval() public {
        uint256 amount = 1e6;

        // Setup: user1 deposits tokens
        vm.startPrank(user1);
        token.deposit(amount, user1, user1);

        // Approve user2 to spend max tokens
        token.approve(user2, type(uint256).max);
        vm.stopPrank();

        // user2 transfers tokens from user1 to themselves
        vm.prank(user2);
        token.transferFrom(user1, user2, amount);

        // Verify balances
        assertEq(token.balanceOf(user1), 0);
        assertEq(token.balanceOf(user2), amount);

        // Verify max allowance remains unchanged
        assertEq(token.allowance(user1, user2), type(uint256).max);
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

}
