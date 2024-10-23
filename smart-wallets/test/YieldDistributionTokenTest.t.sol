// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../src/SmartWallet.sol";
import "../src/WalletFactory.sol";
import "../src/WalletProxy.sol";
import "../src/extensions/AssetVault.sol";
import "../src/token/AssetToken.sol";
import "forge-std/Test.sol";

import "../src/interfaces/IAssetToken.sol";

import "../src/interfaces/IAssetVault.sol";
import "../src/interfaces/ISignedOperations.sol";
import "../src/interfaces/ISmartWallet.sol";
import "../src/interfaces/IYieldReceiver.sol";
import "../src/interfaces/IYieldToken.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { MockYieldCurrency } from "../src/mocks/MockYieldCurrency.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Declare the custom errors
error InvalidTimestamp(uint256 provided, uint256 expected);
error UnauthorizedCall(address invalidUser);

contract NonSmartWalletContract {
// This contract does not implement ISmartWallet
}

contract YieldDistributionTokenTest is Test, WalletUtils {

    address public constant OWNER = address(1);
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 1e18;

    MockYieldCurrency yieldCurrency;
    AssetToken assetToken;
    AssetVault assetVault;

    SmartWallet smartWalletImplementation;
    WalletFactory walletFactory;
    WalletProxy walletProxy;

    address user1SmartWallet;
    address user2SmartWallet;
    address user3;
    address beneficiary;
    address proxyAdmin;

    function setUp() public {
        vm.startPrank(OWNER);

        yieldCurrency = new MockYieldCurrency();

        assetToken = new AssetToken(
            OWNER, "Asset Token", "AT", yieldCurrency, 18, "uri://asset", INITIAL_SUPPLY, 1_000_000 * 1e18, false
        );

        yieldCurrency.approve(address(assetToken), type(uint256).max);
        yieldCurrency.mint(OWNER, 3_000_000_000_000_000_000_000);

        // Deploy SmartWallet infrastructure
        smartWalletImplementation = new SmartWallet();
        walletFactory = new WalletFactory(OWNER, ISmartWallet(address(smartWalletImplementation)));
        walletProxy = new WalletProxy(walletFactory);

        // Deploy SmartWallets for users
        user1SmartWallet = address(new WalletProxy(walletFactory));
        user2SmartWallet = address(new WalletProxy(walletFactory));
        vm.stopPrank();
        vm.prank(user1SmartWallet);
        ISmartWallet(user1SmartWallet).deployAssetVault();

        vm.prank(user2SmartWallet);
        ISmartWallet(user2SmartWallet).deployAssetVault();

        vm.startPrank(OWNER);

        user3 = address(0x3); // Regular EOA

        // Mint tokens to smart wallets and user3
        assetToken.mint(user1SmartWallet, 100_000 * 1e18);
        assetToken.mint(user2SmartWallet, 200_000 * 1e18);
        assetToken.mint(user3, 50_000 * 1e18);

        // Deploy AssetVaults for SmartWallets

        beneficiary = address(0x201);
        proxyAdmin = address(0x401);

        vm.stopPrank();

        // Deploy AssetVault
        assetVault = new AssetVault();
    }

}
