// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { MockVault } from "../src/mocks/MockVault.sol";
import { pUSD } from "../src/token/pUSD.sol";

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
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

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);

        // Deploy contracts
        asset = new TestUSDC();
        vault = new MockVault();

        // Deploy through proxy
        pUSD impl = new pUSD();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl), abi.encodeCall(pUSD.initialize, (owner, IERC20(address(asset)), address(vault)))
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

        vm.startPrank(user1);
        token.deposit(depositAmount, user1, user1);
        token.redeem(depositAmount, user1, user1);
        vm.stopPrank();

        assertEq(vault.balanceOf(user1), 0);
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

}
