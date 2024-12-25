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

        // Deploy mocks
        asset = new MockUSDC();
        vault = new MockVault(
            owner, // _owner
            "Mock Vault", // _name
            "MVLT", // _symbol
            address(asset) // _usdc
        );

        accountant = new MockAccountantWithRateProviders(
            address(vault), // _vault
            address(asset), // _base
            1e18 // startingExchangeRate (1:1 ratio)
        );
    }

    // Common tests that apply to all NestBoringVaultModule implementations
    function testInitialization() public virtual;
    //function testOwnershipAndAuth() public virtual;
    //function testAssetHandling() public virtual;

}
