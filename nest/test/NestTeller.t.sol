// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { NestTeller } from "../src/vault/NestTeller.sol";
import { NestBoringVaultModuleTest } from "./NestBoringVaultModuleTest.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract NestTellerTest is NestBoringVaultModuleTest {

    NestTeller public teller;
    address public endpoint;
    uint256 public constant MINIMUM_MINT_PERCENTAGE = 9900; // 99%

    function setUp() public override {
        super.setUp();
        endpoint = makeAddr("endpoint");

        // Deal some tokens to the vault for initial liquidity
        deal(address(asset), address(vault), 1_000_000e6);

        // Setup initial rates in accountant
        accountant.setRateInQuote(1e18); // 1:1 ratio

        teller = new NestTeller(
            owner, address(vault), address(accountant), endpoint, address(asset), MINIMUM_MINT_PERCENTAGE
        );

        // Approve teller to spend vault's tokens
        vm.prank(address(vault));
        IERC20(address(asset)).approve(address(teller), type(uint256).max);
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

        // Approve teller
        vm.startPrank(user);
        IERC20(address(asset)).approve(address(teller), amount);

        // Deposit
        uint256 shares = teller.deposit(amount, user, user);

        // Verify
        assertGt(shares, 0, "Should have received shares");
        assertEq(IERC20(address(asset)).balanceOf(address(vault)), amount, "Vault should have received tokens");
        vm.stopPrank();
    }

}
