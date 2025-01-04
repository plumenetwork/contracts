// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IOAppCore } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppCore.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Auth } from "@solmate/auth/Auth.sol";
import { Authority, RolesAuthority } from "@solmate/auth/authorities/RolesAuthority.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { console } from "forge-std/console.sol";

import { IBoringVault } from "../src/interfaces/IBoringVault.sol";
import { ITeller } from "../src/interfaces/ITeller.sol";
import { InYSV } from "../src/interfaces/InYSV.sol";
import { NestBoringVaultModule } from "../src/vault/NestBoringVaultModule.sol";
import { NestTeller } from "../src/vault/NestTeller.sol";
import { NestBoringVaultModuleTest } from "./NestBoringVaultModuleTest.t.sol";

import { MockAccountantWithRateProviders } from "../src/mocks/MockAccountantWithRateProviders.sol";
import { MockLayerZeroEndpoint } from "../src/mocks/MockLayerZeroEndpoint.sol";
import { MockUSDC } from "../src/mocks/MockUSDC.sol";
import { MockVault } from "../src/mocks/MockVault.sol";

contract NestTellerTest is NestBoringVaultModuleTest {

    NestTeller public teller;
    address public endpoint;
    uint256 public constant MINIMUM_MINT_PERCENTAGE = 9900; // 99%
    MockLayerZeroEndpoint public mockEndpoint;
    RolesAuthority public rolesAuthority;

    uint8 public constant ADMIN_ROLE = 1;
    uint8 public constant MINTER_ROLE = 7;
    uint8 public constant BURNER_ROLE = 8;
    uint8 public constant SOLVER_ROLE = 9;
    uint8 public constant QUEUE_ROLE = 10;
    uint8 public constant CAN_SOLVE_ROLE = 11;

    function setUp() public override {
        super.setUp();

        /*
        mockEndpoint = new MockLayerZeroEndpoint(1, address(this));
        endpoint = address(mockEndpoint);

        // Deploy teller
        teller = new NestTeller(
            owner, address(vault), address(accountant), endpoint, address(asset), MINIMUM_MINT_PERCENTAGE
        );

        // Set up roles and permissions
        vm.startPrank(owner);
        rolesAuthority = new RolesAuthority(owner, Authority(address(0)));

        // Set role capabilities
        rolesAuthority.setRoleCapability(MINTER_ROLE, address(vault), vault.enter.selector, true);
        rolesAuthority.setRoleCapability(BURNER_ROLE, address(vault), vault.exit.selector, true);
        rolesAuthority.setRoleCapability(ADMIN_ROLE, address(teller), 0x298410e5, true); // addAsset
        rolesAuthority.setRoleCapability(ADMIN_ROLE, address(teller), 0x7033e4a6, true); // removeAsset

        // Set public capabilities using explicit selectors
        rolesAuthority.setPublicCapability(address(teller), 0x2e2d2984, true); // deposit(uint256,address,address)
        rolesAuthority.setPublicCapability(address(teller), 0x0efe6a8b, true); // deposit(IERC20,uint256,uint256)
        rolesAuthority.setPublicCapability(address(teller), 0x2e1a7d4d, true); // depositWithPermit

        // Assign roles
        rolesAuthority.setUserRole(address(teller), MINTER_ROLE, true);
        rolesAuthority.setUserRole(address(teller), BURNER_ROLE, true);
        rolesAuthority.setUserRole(address(this), ADMIN_ROLE, true);

        // Set authorities
        vault.setAuthority(rolesAuthority);
        teller.setAuthority(rolesAuthority);

        // Add supported assets
        teller.addAsset(ERC20(address(asset)));
        vm.stopPrank();

        // Give user tokens and set up approvals
        deal(address(asset), user, 1_000_000e6);
        deal(address(asset), address(teller), 1_000_000e6);

        vm.startPrank(user);
        IERC20(address(asset)).approve(address(teller), type(uint256).max); // User approves teller only
        vm.stopPrank();

        vm.startPrank(address(teller));
        IERC20(address(asset)).approve(address(vault), type(uint256).max); // User approves teller only
        vm.stopPrank();
        */
    }

    // Add this function to implement the Authority interface
    function canCall(address user, address target, bytes4 sig) external view returns (bool) {
        // Allow all calls for testing
        return true;
    }

    function testInitialization() public override {
        //assertEq(teller.owner(), owner);
        assertEq(address(teller.vault()), address(vault));
        assertEq(address(teller.accountant()), address(accountant));
        assertEq(teller.asset(), address(asset));
        assertEq(teller.minimumMintPercentage(), MINIMUM_MINT_PERCENTAGE);
    }

    function testDeposit(
        uint256 amount
    ) public {
        // Bound the amount to reasonable values
        amount = bound(amount, 1e6, 1_000_000e6);

        // Give user some tokens
        deal(address(asset), NYSV_PROXY, amount);

        // Record initial vault balance
        uint256 vaultBalanceBefore = IERC20(address(asset)).balanceOf(address(vault));
        // Approval chain:
        // 1. AGGREGATE_TOKEN needs to approve NYSV_PROXY
        vm.startPrank(AGGREGATE_TOKEN);
        IERC20(address(asset)).approve(NYSV_PROXY, amount);
        vm.stopPrank();

        // 2. NYSV_PROXY needs to approve the vault
        vm.startPrank(NYSV_PROXY);
        IERC20(address(asset)).approve(address(vault), amount);
        vm.stopPrank();

        vm.startPrank(AGGREGATE_TOKEN);

        // Deposit
        uint256 shares = InYSV(NYSV_PROXY).deposit(amount, AGGREGATE_TOKEN, AGGREGATE_TOKEN);

        // Verify
        assertGt(shares, 0, "Should have received shares");

        uint256 vaultBalanceAfter = IERC20(address(asset)).balanceOf(address(vault));
        assertEq(vaultBalanceAfter - vaultBalanceBefore, amount, "Vault should have received correct amount of tokens");
        vm.stopPrank();
    }
    /*
    // Test deposit with invalid receiver
    function testDepositWithInvalidReceiver(
        uint256 amount
    ) public {
        amount = bound(amount, 1e6, 1_000_000e6);
        deal(address(asset), user, amount);

        vm.startPrank(user);
        IERC20(address(asset)).approve(address(teller), amount);

        vm.expectRevert(NestBoringVaultModule.InvalidReceiver.selector);
        teller.deposit(amount, address(this), user);
        vm.stopPrank();
    }

    // Test deposit with invalid controller
    function testDepositWithInvalidController(
        uint256 amount
    ) public {
        amount = bound(amount, 1e6, 1_000_000e6);
        deal(address(asset), user, amount);

        vm.startPrank(user);
        IERC20(address(asset)).approve(address(teller), amount);

        vm.expectRevert(NestBoringVaultModule.InvalidController.selector);
        teller.deposit(amount, user, address(this));
        vm.stopPrank();
    }

    // Test requestDeposit reverts as unimplemented
    function testRequestDepositReverts() public {
        vm.expectRevert(NestBoringVaultModule.Unimplemented.selector);
        teller.requestDeposit(1e6, user, user);
    }

    // Test requestRedeem reverts as unimplemented
    function testRequestRedeemReverts() public {
        vm.expectRevert(NestBoringVaultModule.Unimplemented.selector);
        teller.requestRedeem(1e6, user, user);
    }

    // Test constructor reverts with invalid parameters
    function testConstructorInvalidOwner() public {
        vm.expectRevert(IOAppCore.InvalidDelegate.selector);
        new NestTeller(
            address(0), address(vault), address(accountant), endpoint, address(asset), MINIMUM_MINT_PERCENTAGE
        );
    }

    function testConstructorInvalidVault() public {
        vm.expectRevert();
        new NestTeller(owner, address(0), address(accountant), endpoint, address(asset), MINIMUM_MINT_PERCENTAGE);
    }

    function testConstructorInvalidAccountant() public {
        // comes from TellerWithMultiAssetSupport
        vm.expectRevert("TellerWithMultiAssetSupport: accountant cannot be zero");
        new NestTeller(owner, address(vault), address(0), endpoint, address(asset), MINIMUM_MINT_PERCENTAGE);
    }

    function testConstructorInvalidEndpoint() public {
        vm.expectRevert();
    new NestTeller(owner, address(vault), address(accountant), address(0), address(asset), MINIMUM_MINT_PERCENTAGE);
    }

    function testConstructorInvalidAsset() public {
        vm.expectRevert(NestBoringVaultModule.ZeroAsset.selector);
        new NestTeller(owner, address(vault), address(accountant), endpoint, address(0), MINIMUM_MINT_PERCENTAGE);
    }

    function testConstructorInvalidMinimumMintPercentage() public {
        // Test with 0
        vm.expectRevert(NestBoringVaultModule.InvalidMinimumMintPercentage.selector);
        new NestTeller(owner, address(vault), address(accountant), endpoint, address(asset), 0);

        // Test with > 10_000
        vm.expectRevert(NestBoringVaultModule.InvalidMinimumMintPercentage.selector);
        new NestTeller(owner, address(vault), address(accountant), endpoint, address(asset), 10_001);
    }

    // Test deposit with insufficient allowance
    function testDepositInsufficientAllowance(
        uint256 amount
    ) public {
        amount = bound(amount, 1e6, 1_000_000e6);
        console.log("Amount", amount);

        vm.startPrank(user);

        // Give user the tokens
        deal(address(asset), user, amount);

        // Reset all approvals to 0
        IERC20(address(asset)).approve(address(teller), 0);
        IERC20(address(asset)).approve(address(vault), 0);

        // Verify approvals are 0
        assertEq(IERC20(address(asset)).allowance(user, address(teller)), 0);
        assertEq(IERC20(address(asset)).allowance(user, address(vault)), 0);

        // Approve less than the amount we'll try to deposit
        IERC20(address(asset)).approve(address(teller), amount - 1);

        // Also need to reset NestTeller's approval to the vault
        vm.stopPrank();
        vm.startPrank(address(teller));
        IERC20(address(asset)).approve(address(vault), 0);
        vm.stopPrank();

        vm.startPrank(user);

        // Expect revert with insufficient allowance error
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Try to deposit more than approved amount
        teller.deposit(amount, user, user);
        vm.stopPrank();
    }

    // Test deposit with insufficient balance
    function testDepositInsufficientBalance(
        uint256 amount
    ) public {
        amount = 20_000_000e6;

        vm.startPrank(user);
        IERC20(address(asset)).approve(address(teller), amount);

        // Update expected revert message to match actual error
        vm.expectRevert("TRANSFER_FROM_FAILED");
        teller.deposit(amount, user, user);
        vm.stopPrank();
    }
    */

}
