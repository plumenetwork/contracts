// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IAtomicQueue } from "../src/interfaces/IAtomicQueue.sol";
import { ITeller } from "../src/interfaces/ITeller.sol";

import { MockAtomicQueue } from "../src/mocks/MockAtomicQueue.sol";
import { MockTeller } from "../src/mocks/MockTeller.sol";

import { MockUSDC } from "../src/mocks/MockUSDC.sol";
import { MockVault } from "../src/mocks/MockVault.sol";

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

contract pUSDTest is Test {

    pUSD public token;
    MockUSDC public asset;
    MockVault public vault;
    MockTeller public mockTeller;
    MockAtomicQueue public mockAtomicQueue;

    address public owner;
    address public user1;
    address public user2;

    event VaultChanged(MockVault indexed oldVault, MockVault indexed newVault);

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);

        // Deploy contracts
        asset = new MockUSDC();
        vault = new MockVault();
        mockTeller = new MockTeller();
        mockAtomicQueue = new MockAtomicQueue();

        mockTeller.setAssetSupport(IERC20(address(asset)), true);

        // Set the MockTeller as the beforeTransferHook in the vault
        vault.setBeforeTransferHook(address(mockTeller));

        // Deploy through proxy
        pUSD impl = new pUSD();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(
                pUSD.initialize,
                (owner, IERC20(address(asset)), address(vault), address(mockTeller), address(mockAtomicQueue))
            )
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
        uint256 shares = token.deposit(depositAmount, user1, user1, 0);
        vm.stopPrank();

        assertEq(shares, depositAmount); // Assuming 1:1 ratio
            //assertEq(token.balanceOf(user1), depositAmount);
            //Assets should be in the vault, not the token contract
            //assertEq(asset.balanceOf(address(vault)), depositAmount);
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
        asset.approve(address(mockTeller), type(uint256).max);

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

    function testInitializeInvalidAsset() public {
        // Deploy an invalid token that doesn't implement IERC20Metadata
        MockInvalidToken invalidAsset = new MockInvalidToken();
        pUSD impl = new pUSD();

        bytes memory initData = abi.encodeCall(
            pUSD.initialize,
            (owner, IERC20(address(invalidAsset)), address(vault), address(mockTeller), address(mockAtomicQueue))
        );

        vm.expectRevert(pUSD.InvalidAsset.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function testReinitialize() public {
        // First reinitialize with valid parameters
        token.reinitialize(owner, IERC20(address(asset)), address(vault), address(mockTeller), address(mockAtomicQueue));

        assertEq(token.version(), 2);

        // Test zero address requirements
        vm.expectRevert("Zero address owner");
        token.reinitialize(
            address(0), IERC20(address(asset)), address(vault), address(mockTeller), address(mockAtomicQueue)
        );

        vm.expectRevert("Zero address asset");
        token.reinitialize(owner, IERC20(address(0)), address(vault), address(mockTeller), address(mockAtomicQueue));

        vm.expectRevert("Zero address vault");
        token.reinitialize(owner, IERC20(address(asset)), address(0), address(mockTeller), address(mockAtomicQueue));

        vm.expectRevert("Zero address teller");
        token.reinitialize(owner, IERC20(address(asset)), address(vault), address(0), address(mockAtomicQueue));

        vm.expectRevert("Zero address AtomicQueue");
        token.reinitialize(owner, IERC20(address(asset)), address(vault), address(mockTeller), address(0));
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
        assertEq(token.getAtomicqueue(), address(mockAtomicQueue));
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
        mockTeller.setAssetSupport(IERC20(address(asset)), false);
        vm.startPrank(user1);
        vm.expectRevert(pUSD.AssetNotSupported.selector);
        token.deposit(depositAmount, user1, user1, 0);
        vm.stopPrank();
    }

    function testRedeemReverts() public {
        uint256 amount = 100e6;
        uint256 price = 1e6;

        // Setup
        vm.startPrank(user1);
        token.deposit(amount, user1, user1, 0);

        // Test invalid receiver
        vm.expectRevert(pUSD.InvalidReceiver.selector);
        token.redeem(amount, address(0), user1, price);

        // Test invalid controller
        vm.expectRevert(pUSD.InvalidController.selector);
        token.redeem(amount, user1, address(0), price);

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
        // TODO: Mock Teller deposit does not transfer assets to the vault
        token.deposit(amount, user1, user1, 0);

        // Test transfer
        token.transfer(user2, amount / 2);
        /*

        console.log(token.balanceOf(user1));
        console.log(token.balanceOf(user2));

        assertEq(token.balanceOf(user1), amount / 2);
        assertEq(token.balanceOf(user2), amount / 2);
        // Test transferFrom
        token.approve(user2, amount / 2);
        vm.stopPrank();

        vm.prank(user2);
        token.transferFrom(user1, user2, amount / 2);
        assertEq(token.balanceOf(user1), 0);
        assertEq(token.balanceOf(user2), amount);
        */
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
        //token.transfer(user2, amount);
        vm.stopPrank();

        //assertEq(vault.balanceOf(user1), 0);
        //assertEq(vault.balanceOf(user2), amount);
        //assertEq(asset.balanceOf(address(vault)), amount);
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

    // small hack to be excluded from coverage report
    function test() public { }

}
