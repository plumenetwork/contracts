// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IAtomicQueue } from "../src/interfaces/IAtomicQueue.sol";
import { ITeller } from "../src/interfaces/ITeller.sol";

import { MockAtomicQueue } from "../src/mocks/MockAtomicQueue.sol";
import { MockTeller } from "../src/mocks/MockTeller.sol";

import { MockAccountantWithRateProviders } from "../src/mocks/MockAccountantWithRateProviders.sol";
import { MockLens } from "../src/mocks/MockLens.sol";
import { MockUSDC } from "../src/mocks/MockUSDC.sol";
import { MockVault } from "../src/mocks/MockVault.sol";

import { pUSDProxy } from "../src/proxy/pUSDProxy.sol";
import { pUSD } from "../src/token/pUSD.sol";

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

// Mock contract for testing invalid asset
contract MockInvalidToken {
// Deliberately missing functions to make it invalid
}

contract MockInvalidVault {

    // Empty contract that will fail when trying to call decimals()
    function decimals() external pure returns (uint8) {
        revert();
    }

}

contract pUSDTest is Test {

    pUSD public token;
    MockUSDC public usdc;
    MockVault public vault;
    MockTeller public mockTeller;
    MockAtomicQueue public mockAtomicQueue;
    MockLens public mockLens;
    MockAccountantWithRateProviders public mockAccountant;

    address public payout_address = vm.addr(7_777_777);
    address public owner;
    address public user1;
    address public user2;

    event VaultChanged(MockVault indexed oldVault, MockVault indexed newVault);

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);

        // Deploy contracts
        //asset = new MockUSDC();
        usdc = new MockUSDC();

        vault = new MockVault(owner, "Mock Vault", "mVault", address(usdc));
        mockTeller = new MockTeller();
        mockAtomicQueue = new MockAtomicQueue();
        mockLens = new MockLens();

        mockAccountant = new MockAccountantWithRateProviders(address(vault), address(usdc), 1e6);
        mockTeller.setAssetSupport(IERC20(address(usdc)), true);

        // Set the MockTeller as the beforeTransferHook in the vault
        vault.setBeforeTransferHook(address(mockTeller));

        // Deploy through proxy
        pUSD impl = new pUSD();
        ERC1967Proxy proxy = new pUSDProxy(
            address(impl),
            abi.encodeCall(
                pUSD.initialize,
                (
                    owner,
                    IERC20(address(usdc)),
                    address(vault),
                    address(mockTeller),
                    address(mockAtomicQueue),
                    address(mockLens),
                    address(mockAccountant)
                )
            )
        );
        token = pUSD(address(proxy));

        // Setup balances
        usdc.mint(user1, 1000e6);

        vm.prank(user1);
        usdc.approve(address(token), type(uint256).max);
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
        uint256 shares = token.deposit(depositAmount, user1, user1, 0);
        vm.stopPrank();

        assertEq(shares, depositAmount); // Assuming 1:1 ratio
    }

    function testRedeem() public {
        uint256 depositAmount = 1e6;
        uint256 price = 1e6; // 1:1 price
        uint256 minimumMint = depositAmount;

        // Setup
        deal(address(usdc), user1, depositAmount);

        vm.startPrank(user1);

        // Approve all necessary contracts
        usdc.approve(address(token), type(uint256).max);
        usdc.approve(address(vault), type(uint256).max);
        usdc.approve(address(mockTeller), type(uint256).max);

        // Additional approval needed for the vault to transfer from pUSD
        vm.stopPrank();
        vm.startPrank(address(token));
        usdc.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user1);

        // Perform deposit and redeem
        token.deposit(depositAmount, user1, user1, minimumMint);

        uint64 deadline = uint64(block.timestamp + 1 hours);
        token.redeem(depositAmount, user1, user1, price, deadline);

        vm.stopPrank();

        // TODO: warp time and verify final state
    }

    function testInitializeInvalidAsset() public {
        // Deploy an invalid token that doesn't implement IERC20Metadata
        MockInvalidToken invalidAsset = new MockInvalidToken();
        pUSD impl = new pUSD();

        bytes memory initData = abi.encodeCall(
            pUSD.initialize,
            (
                owner,
                IERC20(address(invalidAsset)),
                address(vault),
                address(mockTeller),
                address(mockAtomicQueue),
                address(mockLens),
                address(mockAccountant)
            )
        );

        vm.expectRevert(pUSD.InvalidAsset.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function testReinitialize() public {
        // First reinitialize with valid parameters
        token.reinitialize(
            owner,
            IERC20(address(usdc)),
            address(vault),
            address(mockTeller),
            address(mockAtomicQueue),
            address(mockLens),
            address(mockAccountant)
        );

        assertNotEq(token.version(), 1);

        // Test zero address requirements
        vm.expectRevert(pUSD.ZeroAddress.selector);
        token.reinitialize(
            address(0),
            IERC20(address(usdc)),
            address(vault),
            address(mockTeller),
            address(mockAtomicQueue),
            address(mockLens),
            address(mockAccountant)
        );

        vm.expectRevert(pUSD.ZeroAddress.selector);

        token.reinitialize(
            owner,
            IERC20(address(0)),
            address(vault),
            address(mockTeller),
            address(mockAtomicQueue),
            address(mockLens),
            address(mockAccountant)
        );

        vm.expectRevert(pUSD.ZeroAddress.selector);
        token.reinitialize(
            owner,
            IERC20(address(usdc)),
            address(0),
            address(mockTeller),
            address(mockAtomicQueue),
            address(mockLens),
            address(mockAccountant)
        );

        vm.expectRevert(pUSD.ZeroAddress.selector);
        token.reinitialize(
            owner,
            IERC20(address(usdc)),
            address(vault),
            address(0),
            address(mockAtomicQueue),
            address(mockLens),
            address(mockAccountant)
        );

        vm.expectRevert(pUSD.ZeroAddress.selector);
        token.reinitialize(
            owner,
            IERC20(address(usdc)),
            address(vault),
            address(mockTeller),
            address(0),
            address(mockLens),
            address(mockAccountant)
        );
    }

    function testAuthorizeUpgrade() public {
        address newImplementation = address(new pUSD());

        // Test with non-upgrader role
        vm.startPrank(user1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user1, token.UPGRADER_ROLE()
            )
        );

        token.upgradeToAndCall(newImplementation, "");
        vm.stopPrank();

        // Test successful upgrade
        vm.startPrank(owner);
        token.upgradeToAndCall(newImplementation, "");
        vm.stopPrank();
    }

    function testGetters() public {
        assertEq(token.getTeller(), address(mockTeller));
        assertEq(token.getAtomicQueue(), address(mockAtomicQueue));
        assertEq(token.version(), 1);
    }

    function testDepositReverts() public {
        uint256 depositAmount = 100e6;

        // Test invalid receiver
        vm.startPrank(user1);
        vm.expectRevert(pUSD.InvalidReceiver.selector);
        token.deposit(depositAmount, address(0), user1, 0);
        vm.stopPrank();

        // Test teller paused
        mockTeller.setPaused(true);
        vm.startPrank(user1);
        vm.expectRevert(pUSD.TellerPaused.selector);
        token.deposit(depositAmount, user1, user1, 0);
        vm.stopPrank();

        // Test asset not supported
        mockTeller.setPaused(false);
        mockTeller.setAssetSupport(IERC20(address(usdc)), false);
        vm.startPrank(user1);
        vm.expectRevert(pUSD.AssetNotSupported.selector);
        token.deposit(depositAmount, user1, user1, 0);
        vm.stopPrank();
    }

    function testRedeemReverts() public {
        uint256 amount = 100e6;
        uint256 price = 1e6;
        uint64 deadline = uint64(block.timestamp + 1 hours);

        // Setup
        vm.startPrank(user1);
        token.deposit(amount, user1, user1, 0);

        // Test invalid receiver
        vm.expectRevert(pUSD.InvalidReceiver.selector);
        token.redeem(amount, address(0), user1, price, deadline);

        // Test invalid controller
        vm.expectRevert(pUSD.InvalidController.selector);
        token.redeem(amount, user1, address(0), price, deadline);

        vm.stopPrank();
    }

    function testRedeemDeadlineExpired() public {
        uint256 amount = 100e6;
        uint256 price = 1e6;

        // Setup
        vm.startPrank(user1);
        token.deposit(amount, user1, user1, 0);

        // Mock the lens to return correct balance
        mockLens.setBalance(user1, amount);

        // Set block.timestamp to a known value
        vm.warp(1000);

        // Set deadline in the past
        uint64 expiredDeadline = uint64(block.timestamp - 1);

        // Test expired deadline
        vm.expectRevert(pUSD.DeadlineExpired.selector);
        token.redeem(amount, user1, user1, price, expiredDeadline);

        vm.stopPrank();
    }

    function testPreviewDepositInvalidVault() public {
        // Deploy an invalid vault (empty contract)
        MockInvalidVault invalidVault = new MockInvalidVault();

        vm.startPrank(owner);

        // Grant UPGRADER_ROLE to owner for reinitialize
        token.grantRole(token.UPGRADER_ROLE(), owner);

        //vm.expectRevert(pUSD.ZeroAddress.selector);
        // Reinitialize with the new vault
        token.reinitialize(
            owner,
            IERC20(address(usdc)),
            address(invalidVault),
            address(mockTeller),
            address(mockAtomicQueue),
            address(mockLens),
            address(mockAccountant)
        );

        // Now we can test the preview functions with the new vault
        vm.expectRevert(pUSD.InvalidVault.selector);
        token.previewDeposit(100e6);

        vm.stopPrank();
    }

    function testPreviewRedeemInvalidVault() public {
        MockInvalidVault invalidVault = new MockInvalidVault();

        vm.startPrank(owner);
        // Grant UPGRADER_ROLE to owner for reinitialize
        token.grantRole(token.UPGRADER_ROLE(), owner);

        // Reinitialize with the new vault
        token.reinitialize(
            owner,
            IERC20(address(usdc)),
            address(invalidVault),
            address(mockTeller),
            address(mockAtomicQueue),
            address(mockLens),
            address(mockAccountant)
        );

        // Now we can test the preview functions with the new vault
        vm.expectRevert(pUSD.InvalidVault.selector);
        token.previewRedeem(100e6);

        vm.stopPrank();
    }

    function testConvertFunctionsAndReverts() public {
        uint256 amount = 100e6;

        // Test normal operation first
        mockAccountant.updateExchangeRate(2e6); // 2:1 rate

        // With 2:1 rate:
        // 100 assets should convert to 50 shares (assets/rate)
        uint256 shares = token.convertToShares(amount);
        assertEq(shares, amount / 2, "Incorrect shares calculation");

        // 50 shares should convert to 100 assets (shares*rate)
        uint256 assets = token.convertToAssets(shares);
        assertEq(assets, amount, "Incorrect assets calculation");

        // Now test reverts with invalid vault
        MockInvalidVault invalidVault = new MockInvalidVault();

        vm.startPrank(owner);
        token.grantRole(token.UPGRADER_ROLE(), owner);

        // Reinitialize with invalid vault
        token.reinitialize(
            owner,
            IERC20(address(usdc)),
            address(invalidVault),
            address(mockTeller),
            address(mockAtomicQueue),
            address(mockLens),
            address(mockAccountant)
        );

        // Test convertToShares revert
        vm.expectRevert(pUSD.InvalidVault.selector);
        token.convertToShares(amount);

        // Test convertToAssets revert
        vm.expectRevert(pUSD.InvalidVault.selector);
        token.convertToAssets(amount);

        vm.stopPrank();
    }

    function testTransferFrom() public {
        uint256 amount = 100e6;

        // Setup initial balance for user1
        vm.startPrank(user1);
        token.deposit(amount, user1, user1, 0);

        // Mock the lens to return correct balances
        mockLens.setBalance(user1, amount);

        // Approve user2 to spend tokens
        token.approve(user2, amount);
        vm.stopPrank();

        // Initial balances
        assertEq(token.balanceOf(user1), amount, "Initial balance user1 incorrect");
        assertEq(token.balanceOf(user2), 0, "Initial balance user2 incorrect");

        // Test transferFrom with user2
        vm.startPrank(user2);
        token.transferFrom(user1, user2, amount);

        // Update mock balances after transfer
        mockLens.setBalance(user1, 0);
        mockLens.setBalance(user2, amount);

        // Check final balances
        assertEq(token.balanceOf(user1), 0, "Final balance user1 incorrect");
        assertEq(token.balanceOf(user2), amount, "Final balance user2 incorrect");

        // Check allowance was spent
        assertEq(token.allowance(user1, user2), 0, "Allowance should be spent");
        vm.stopPrank();
    }

    function testConvertToAssets() public {
        uint256 shares = 100e6;
        uint256 assets = token.convertToAssets(shares);
        assertEq(assets, shares); // Assuming 1:1 ratio
    }

    function testTransferFunctions() public {
        uint256 amount = 100e6;

        // Setup
        vm.startPrank(user1);
        token.deposit(amount, user1, user1, 0);

        // Set initial balance in MockLens
        mockLens.setBalance(user1, amount);

        // Test transfer
        token.transfer(user2, amount / 2);

        // Update mock balances after transfer
        mockLens.setBalance(user1, amount / 2);
        mockLens.setBalance(user2, amount / 2);

        // Verify balances after transfer
        assertEq(token.balanceOf(user1), amount / 2, "User1 balance incorrect after transfer");
        assertEq(token.balanceOf(user2), amount / 2, "User2 balance incorrect after transfer");

        // Test transferFrom
        token.approve(user2, amount / 2);
        vm.stopPrank();

        vm.prank(user2);
        token.transferFrom(user1, user2, amount / 2);

        // Update mock balances after transferFrom
        mockLens.setBalance(user1, 0);
        mockLens.setBalance(user2, amount);

        // Verify final balances
        assertEq(token.balanceOf(user1), 0, "User1 final balance incorrect");
        assertEq(token.balanceOf(user2), amount, "User2 final balance incorrect");
    }

    // Helper function for access control error message
    function accessControlErrorMessage(address account, bytes32 role) internal pure returns (bytes memory) {
        return abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(account),
            " is missing role ",
            Strings.toHexString(uint256(role), 32)
        );
    }

    function testVaultIntegration() public {
        uint256 amount = 1e6;

        vm.startPrank(user1);
        token.deposit(amount, user1, user1);
        vm.stopPrank();
    }

    function testVault() public {
        // Verify the vault address matches what we set in setUp
        assertEq(address(token.getVault()), address(vault));
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

    function testPreviewDeposit() public {
        uint256 depositAmount = 100e6; // 100 USDC

        // Set the exchange rate to 1:1 (1e6)
        mockAccountant.updateExchangeRate(1e6);

        // Preview deposit should return same amount as shares (1:1 ratio)
        uint256 expectedShares = token.previewDeposit(depositAmount);
        assertEq(expectedShares, depositAmount, "Preview deposit amount mismatch");

        // Verify actual deposit matches preview
        vm.startPrank(user1);
        uint256 actualShares = token.deposit(depositAmount, user1, user1, 0);
        vm.stopPrank();

        assertEq(actualShares, expectedShares, "Actual shares don't match preview");
    }

    function testPreviewRedeem() public {
        uint256 depositAmount = 100e6;
        uint256 redeemAmount = 50e6;
        uint64 deadline = uint64(block.timestamp + 1 hours);

        // Setup: First deposit some tokens
        vm.startPrank(user1);
        token.deposit(depositAmount, user1, user1, 0);

        // Preview redeem should return same amount as assets (1:1 ratio)
        uint256 expectedAssets = token.previewRedeem(redeemAmount);
        assertEq(expectedAssets, redeemAmount);

        // Verify actual redeem matches preview
        uint256 actualAssets = token.redeem(redeemAmount, user1, user1, 1e6, deadline);
        vm.stopPrank();

        assertEq(actualAssets, expectedAssets, "Redeem amount doesn't match preview");
    }

    function testBalanceOf() public {
        uint256 depositAmount = 100e6;

        // Initial balances should be 0
        assertEq(token.balanceOf(user1), 0, "Initial share balance should be 0");
        assertEq(token.assetsOf(user1), 0, "Initial asset balance should be 0");

        // Setup initial rate in accountant
        mockAccountant.updateExchangeRate(1e6); // 1:1 rate

        vm.startPrank(user1);

        // Approve vault to spend USDC
        usdc.approve(address(vault), type(uint256).max);

        // Deposit through vault
        vault.enter(user1, address(usdc), depositAmount, user1, depositAmount);

        // Check both balances
        assertEq(token.balanceOf(user1), depositAmount, "Share balance after deposit incorrect");
        assertEq(token.assetsOf(user1), depositAmount, "Asset balance after deposit incorrect with 1:1 rate");

        // Test with different exchange rate
        mockAccountant.updateExchangeRate(2e6); // 2:1 rate

        // Share balance should remain the same
        assertEq(token.balanceOf(user1), depositAmount, "Share balance should not change with rate");
        // Asset balance should double
        assertEq(token.assetsOf(user1), depositAmount * 2, "Asset balance incorrect with 2:1 rate");

        vm.stopPrank();
    }

    // small hack to be excluded from coverage report
    function test() public { }

}
