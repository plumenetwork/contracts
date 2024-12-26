// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { MockAccountantWithRateProviders } from "../src/mocks/MockAccountantWithRateProviders.sol";

import { IBoringVault } from "../src/interfaces/IBoringVault.sol";
import { MockLayerZeroEndpoint } from "../src/mocks/MockLayerZeroEndpoint.sol";
import { MockUSDC } from "../src/mocks/MockUSDC.sol";
import { MockVault } from "../src/mocks/MockVault.sol";

import { NestBoringVaultModule } from "../src/vault/NestBoringVaultModule.sol";
import { NestTeller } from "../src/vault/NestTeller.sol";
import { NestBoringVaultModuleTest } from "./NestBoringVaultModuleTest.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Auth } from "@solmate/auth/Auth.sol";

import { Authority, RolesAuthority } from "@solmate/auth/authorities/RolesAuthority.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { console } from "forge-std/console.sol";

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
    }

    // Add this function to implement the Authority interface
    function canCall(address user, address target, bytes4 sig) external view returns (bool) {
        // Allow all calls for testing
        return true;
    }

    // Helper function to get panic reason
    function getPanicReason(
        uint256 errorCode
    ) internal pure returns (string memory) {
        if (errorCode == 0x01) {
            return "Assertion failed";
        }
        if (errorCode == 0x11) {
            return "Arithmetic overflow/underflow";
        }
        if (errorCode == 0x12) {
            return "Division by zero";
        }
        if (errorCode == 0x21) {
            return "Invalid enum value";
        }
        if (errorCode == 0x22) {
            return "Storage write to inaccessible slot";
        }
        if (errorCode == 0x31) {
            return "Pop from empty array";
        }
        if (errorCode == 0x32) {
            return "Array access out of bounds";
        }
        if (errorCode == 0x41) {
            return "Zero initialization of uninitialized variable";
        }
        if (errorCode == 0x51) {
            return "Invalid memory access";
        }
        return string(abi.encodePacked("Unknown panic code: ", uint2str(errorCode)));
    }

    // Helper function to convert uint to string
    function uint2str(
        uint256 _i
    ) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    // Helper function to convert bytes4 to string
    function bytes4ToString(
        bytes4 _bytes
    ) internal pure returns (string memory) {
        bytes memory bytesArray = new bytes(8);
        uint256 value = uint256(uint32(_bytes));
        for (uint256 i; i < 4; i++) {
            uint8 temp = uint8(value / (2 ** (8 * (3 - i))));
            bytesArray[i * 2] = bytes1(uint8((temp / 16) + (temp / 16 < 10 ? 48 : 87)));
            bytesArray[i * 2 + 1] = bytes1(uint8((temp % 16) + (temp % 16 < 10 ? 48 : 87)));
        }
        return string(bytesArray);
    }

    function testInitialization() public override {
        assertEq(teller.owner(), owner);
        assertEq(address(teller.vaultContract()), address(vault));
        assertEq(address(teller.accountantContract()), address(accountant));
        assertEq(teller.asset(), address(asset));
        assertEq(teller.minimumMintPercentage(), MINIMUM_MINT_PERCENTAGE);
    }

    function testDeposit(
        uint256 amount
    ) public {
        // Bound the amount to reasonable values
        amount = bound(amount, 1e6, 1_000_000e6);

        // Give user some tokens
        deal(address(asset), user, amount);

        // Record initial vault balance
        uint256 vaultBalanceBefore = IERC20(address(asset)).balanceOf(address(vault));

        // Approve teller
        vm.startPrank(user);
        IERC20(address(asset)).approve(address(teller), amount);

        // Deposit
        uint256 shares = teller.deposit(amount, user, user);

        // Verify
        assertGt(shares, 0, "Should have received shares");

        uint256 vaultBalanceAfter = IERC20(address(asset)).balanceOf(address(vault));
        assertEq(vaultBalanceAfter - vaultBalanceBefore, amount, "Vault should have received correct amount of tokens");
        vm.stopPrank();
    }

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
        vm.expectRevert(NestBoringVaultModule.InvalidDelegate.selector);
        new NestTeller(
            address(0), address(vault), address(accountant), endpoint, address(asset), MINIMUM_MINT_PERCENTAGE
        );
    }

    function testConstructorInvalidVault() public {
        vm.expectRevert(NestBoringVaultModule.ZeroVault.selector);
        new NestTeller(owner, address(0), address(accountant), endpoint, address(asset), MINIMUM_MINT_PERCENTAGE);
    }

    function testConstructorInvalidAccountant() public {
        vm.expectRevert(NestBoringVaultModule.ZeroAccountant.selector);
        new NestTeller(owner, address(vault), address(0), endpoint, address(asset), MINIMUM_MINT_PERCENTAGE);
    }

    function testConstructorInvalidEndpoint() public {
        vm.expectRevert(NestBoringVaultModule.ZeroEndpoint.selector);
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
        deal(address(asset), user, amount);

        vm.startPrank(user);
        IERC20(address(asset)).approve(address(teller), amount - 1); // Approve less than amount

        vm.expectRevert(); // Should revert with insufficient allowance
        teller.deposit(amount, user, user);
        vm.stopPrank();
    }

    // Test deposit with insufficient balance
    function testDepositInsufficientBalance(
        uint256 amount
    ) public {
        amount = bound(amount, 1e6, 1_000_000e6);
        deal(address(asset), user, amount - 1); // Give less than amount

        vm.startPrank(user);
        IERC20(address(asset)).approve(address(teller), amount);

        vm.expectRevert(); // Should revert with insufficient balance
        teller.deposit(amount, user, user);
        vm.stopPrank();
    }

}
