// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IAtomicQueue } from "../src/interfaces/IAtomicQueue.sol";
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

contract pUSDTest is Test {

    pUSD public token;
    TestUSDC public asset;
    MockVault public vault;

    address public owner;
    address public user1;
    address public user2;

    event VaultChanged(MockVault indexed oldVault, MockVault indexed newVault);

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);

        // Deploy contracts
        asset = new TestUSDC();
        vault = new MockVault();
        IAtomicQueue atomicQueue = IAtomicQueue(0x9fEcc2dFA8B64c27B42757B0B9F725fe881Ddb2a);
        // Deploy through proxy
        pUSD impl = new pUSD();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(pUSD.initialize, (owner, IERC20(address(asset)), address(vault), address(atomicQueue)))
        );
        token = pUSD(address(proxy));

        // Setup balances
        asset.mint(user1, 1000e6);
        vm.prank(user1);
        asset.approve(address(token), type(uint256).max);
    }

    function testInitialize() public {
        assertEq(token.name(), "Plume USD");
        assertEq(token.symbol(), "pUSD");
        assertEq(token.decimals(), 6);
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), owner));
        assertTrue(token.hasRole(token.VAULT_ADMIN_ROLE(), owner));
        assertTrue(token.hasRole(token.UPGRADER_ROLE(), owner));
    }

    function testDeposit() public {
        uint256 depositAmount = 100e6;

        vm.startPrank(user1);
        uint256 shares = token.deposit(depositAmount, user1, user1);
        vm.stopPrank();

        assertEq(shares, depositAmount); // Assuming 1:1 ratio
        assertEq(token.balanceOf(user1), depositAmount);
        // Assets should be in the vault, not the token contract
        assertEq(asset.balanceOf(address(vault)), depositAmount);
    }

    function testRedeem() public {
        uint256 depositAmount = 100e6;

        // Check initial balance
        uint256 initialBalance = asset.balanceOf(user1);

        vm.startPrank(user1);
        token.deposit(depositAmount, user1, user1);
        token.redeem(depositAmount, user1, user1);
        vm.stopPrank();

        assertEq(token.balanceOf(user1), 0);
        // Check final balance matches initial balance
        assertEq(asset.balanceOf(user1), initialBalance);
    }

    function testRedeemFrom() public {
        uint256 amount = 100e6;

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
        uint256 amount = 100e6;

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
        uint256 amount = 100e6;

        vm.startPrank(user1);
        token.deposit(amount, user1, user1);
        token.transfer(user2, amount);
        vm.stopPrank();

        assertEq(token.balanceOf(user1), 0);
        assertEq(token.balanceOf(user2), amount);
    }

    function testVaultIntegration() public {
        uint256 amount = 100e6;

        vm.startPrank(user1);
        token.deposit(amount, user1, user1);
        token.transfer(user2, amount);
        vm.stopPrank();

        assertEq(vault.balanceOf(user1), 0);
        assertEq(vault.balanceOf(user2), amount);
        assertEq(asset.balanceOf(address(vault)), amount);
    }

    function testSetVault() public {
        // Create a new mock vault
        MockVault newVault = new MockVault();

        // Try to set vault without proper role - should revert
        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user1, token.VAULT_ADMIN_ROLE()
            )
        );
        token.setVault(address(newVault));
        vm.stopPrank();

        // Grant VAULT_ADMIN_ROLE to the test contract
        bytes32 vaultAdminRole = token.VAULT_ADMIN_ROLE();
        token.grantRole(vaultAdminRole, address(this));

        // Set vault with proper role
        address oldVault = address(token.vault());

        // Expect the VaultChanged event with the correct address format
        //vm.expectEmit(true, true, true, true, address(token));
        emit VaultChanged(MockVault(oldVault), newVault);

        token.setVault(address(newVault));

        // Verify the vault was updated
        assertEq(address(token.vault()), address(newVault));
    }

    function testVault() public {
        // Verify the vault address matches what we set in setUp
        assertEq(address(token.vault()), address(vault));
    }

    function testTransferFrom() public {
        uint256 amount = 100e6;

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
        uint256 amount = 100e6;

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
