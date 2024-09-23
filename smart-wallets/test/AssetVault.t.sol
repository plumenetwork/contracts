// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";

import "../src/extensions/AssetVault.sol";

import "../src/interfaces/IAssetToken.sol";
import "../src/interfaces/IAssetVault.sol";
import "../src/token/AssetToken.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock YieldCurrency ERC20 for testing
contract YieldCurrency is ERC20, Ownable {

    constructor(string memory name, string memory symbol, address owner) ERC20(name, symbol) Ownable(owner) { }

    function mint(address account, uint256 amount) public onlyOwner {
        _mint(account, amount);
    }

}

contract AssetVaultTest is Test {

    YieldCurrency public yieldCurrency;
    AssetVault public assetVault;
    AssetToken public assetToken;

    address public constant OWNER = address(1);
    address public constant HOLDER_1 = address(2);
    address public constant HOLDER_2 = address(3);
    uint256 initialSupply = 1_000_000;

    function setUp() public {
        // Setup mock ERC20 YieldCurrency and AssetToken
        yieldCurrency = new YieldCurrency("USDC", "USDC", OWNER);
        assetToken = new AssetToken(
            OWNER, // Address of the owner
            "AssetToken", // Name of the token
            "AT", // Symbol of the token
            yieldCurrency, // ERC20 currency token
            18, // Decimals for the asset token
            "uri://asset", // Token URI
            initialSupply, // Initial supply of AssetToken
            1_000_000 // Total value of all AssetTokens
        );

        vm.prank(OWNER);
        assetVault = new AssetVault();

        // Transfer some AssetTokens to the AssetVault
        vm.prank(OWNER);
        assetToken.transfer(address(assetVault), initialSupply);

        assertEq(assetToken.balanceOf(address(assetVault)), initialSupply);
    }

    // /// @dev Test accepting yield allowance
    function testAcceptYieldAllowance() public {
        // OWNER updates allowance for HOLDER_1
        vm.prank(OWNER);
        assetVault.updateYieldAllowance(assetToken, HOLDER_1, 500_000, block.timestamp + 30 days);

        // HOLDER_1 accepts the yield allowance
        vm.prank(HOLDER_1);
        assetVault.acceptYieldAllowance(assetToken, 500_000, block.timestamp + 30 days);

        // Check locked balance
        uint256 lockedBalance = assetVault.getBalanceLocked(assetToken);
        assertEq(lockedBalance, 500_000);
    }

}
