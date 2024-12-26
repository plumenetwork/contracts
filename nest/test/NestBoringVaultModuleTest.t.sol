// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { MockAccountantWithRateProviders } from "../src/mocks/MockAccountantWithRateProviders.sol";
import { MockERC20 } from "../src/mocks/MockERC20.sol";
import { MockUSDC } from "../src/mocks/MockUSDC.sol";
import { MockVault } from "../src/mocks/MockVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Test } from "forge-std/Test.sol";

abstract contract NestBoringVaultModuleTest is Test {

    MockUSDC public asset;
    MockVault public vault;
    MockAccountantWithRateProviders public accountant;

    address public owner;
    address public user;

    function setUp() public virtual {
        owner = address(this);
        user = makeAddr("user");

        // Deploy mocks in specific order
        asset = new MockUSDC();
        
vault = new MockVault(owner, "Mock Vault", "mVault", 6); // Use 6 for USDC decimals
/*
        vault = new MockVault(
            owner,          // _owner
            "Mock Vault",   // _name
            "MVLT",        // _symbol
            address(asset)  // _usdc
        );
*/
        accountant = new MockAccountantWithRateProviders(
            address(vault), // _vault
            address(asset), // _base
            1e18 // startingExchangeRate (1:1 ratio)
        );

        // Deal some tokens to the vault for initial liquidity
        deal(address(asset), address(vault), 1000000e6);
    }

    // Common tests that apply to all NestBoringVaultModule implementations
    function testInitialization() public virtual;
    //function testOwnershipAndAuth() public virtual;
    //function testAssetHandling() public virtual;

}
