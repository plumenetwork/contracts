// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IBoringVault } from "../src/interfaces/IBoringVault.sol";
import { MockAccountantWithRateProviders } from "../src/mocks/MockAccountantWithRateProviders.sol";
import { MockERC20 } from "../src/mocks/MockERC20.sol";
import { MockUSDC } from "../src/mocks/MockUSDC.sol";
import { MockVault } from "../src/mocks/MockVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Test } from "forge-std/Test.sol";

abstract contract NestBoringVaultModuleTest is Test {

    address public constant NYSV_PROXY = 0xC27F63B2b4A5819433D1A89765C439Ee0446CFf8;
    address public constant AGGREGATE_TOKEN = 0x81537d879ACc8a290a1846635a0cAA908f8ca3a6;
    address public constant USDC = 0x3938A812c54304fEffD266C7E2E70B48F9475aD6;
    address private constant VAULT_TOKEN = 0x4dA57055E62D8c5a7fD3832868DcF3817b99C959;

    IERC20 public asset;
    IBoringVault public vault;
    MockAccountantWithRateProviders public accountant;

    address public owner;
    address public user;

    function setUp() public virtual {
        owner = address(this);
        user = makeAddr("user");

        // Deploy mocks in specific order
        asset = IERC20(USDC);

        vault = IBoringVault(VAULT_TOKEN); // Use 6 for USDC decimals

        accountant = new MockAccountantWithRateProviders(
            address(vault), // _vault
            address(asset), // _base
            1e6 // startingExchangeRate (1:1 ratio)
        );

        // Deal some tokens to the vault for initial liquidity
        deal(address(asset), address(vault), 1_000_000e6);
    }

    // Common tests that apply to all NestBoringVaultModule implementations
    function testInitialization() public virtual;
    //function testOwnershipAndAuth() public virtual;
    //function testAssetHandling() public virtual;

}
