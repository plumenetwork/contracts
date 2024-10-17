// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/token/AssetToken.sol";
import "../src/extensions/AssetVault.sol";
import "../src/SmartWallet.sol";
import "../src/WalletFactory.sol";
import "../src/WalletProxy.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/interfaces/ISmartWallet.sol";
import "../src/interfaces/ISignedOperations.sol";
import "../src/interfaces/IYieldReceiver.sol";
import "../src/interfaces/IAssetToken.sol";
import "../src/interfaces/IYieldToken.sol";
import "../src/interfaces/IAssetVault.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

// Declare the custom errors
error InvalidTimestamp(uint256 provided, uint256 expected);
error UnauthorizedCall(address invalidUser);

contract NonSmartWalletContract {
    // This contract does not implement ISmartWallet
}

// Mock YieldCurrency for testing
contract MockYieldCurrency is ERC20 {
    constructor() ERC20("Yield Currency", "YC") {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

// Mock DEX contract for testing
contract MockDEX {
    AssetToken public assetToken;

    constructor(AssetToken _assetToken) {
        assetToken = _assetToken;
    }

    function createOrder(address maker, uint256 amount) external {
        assetToken.registerMakerOrder(maker, amount);
    }

    function cancelOrder(address maker, uint256 amount) external {
        assetToken.unregisterMakerOrder(maker, amount);
    }
}
contract YieldDistributionTokenTest is Test, WalletUtils {
    address public constant OWNER = address(1);
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 1e18;

    MockYieldCurrency yieldCurrency;
    AssetToken assetToken;
    MockDEX mockDEX;
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
            OWNER,
            "Asset Token",
            "AT",
            yieldCurrency,
            18,
            "uri://asset",
            INITIAL_SUPPLY,
            1_000_000 * 1e18,
            false
        );

        yieldCurrency.approve(address(assetToken), type(uint256).max);
        yieldCurrency.mint(OWNER, 3000000000000000000000);

        // Deploy SmartWallet infrastructure
        smartWalletImplementation = new SmartWallet();
        walletFactory = new WalletFactory(
            OWNER,
            ISmartWallet(address(smartWalletImplementation))
        );
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

        mockDEX = new MockDEX(assetToken);
        assetToken.registerDEX(address(mockDEX));

        beneficiary = address(0x201);
        proxyAdmin = address(0x401);

        vm.stopPrank();

        // Deploy AssetVault
        assetVault = new AssetVault();
    }
    /*
function testTransferBetweenSmartWallets() public {
    uint256 transferAmount = 50_000 * 1e18;

    vm.startPrank(OWNER);
    assetToken.mint(user1SmartWallet, 100_000 * 1e18);
    vm.stopPrank();

    console.log("Before transfer - User1 balance:", assetToken.balanceOf(user1SmartWallet));
    console.log("Before transfer - User2 balance:", assetToken.balanceOf(user2SmartWallet));

    vm.prank(user1SmartWallet);
    bool success = assetToken.transfer(user2SmartWallet, transferAmount);

    console.log("Transfer success:", success);
    console.log("After transfer - User1 balance:", assetToken.balanceOf(user1SmartWallet));
    console.log("After transfer - User2 balance:", assetToken.balanceOf(user2SmartWallet));

    assertTrue(success, "Transfer should succeed");
    assertEq(assetToken.balanceOf(user1SmartWallet), 50_000 * 1e18, "User1 balance should decrease");
    assertEq(assetToken.balanceOf(user2SmartWallet), 250_000 * 1e18, "User2 balance should increase");
}

function testTransferFromSmartWalletToEOA() public {
    uint256 transferAmount = 50_000 * 1e18;

    vm.startPrank(OWNER);
    assetToken.mint(user1SmartWallet, 100_000 * 1e18);
    vm.stopPrank();

    console.log("Before transfer - User1 balance:", assetToken.balanceOf(user1SmartWallet));
    console.log("Before transfer - User3 balance:", assetToken.balanceOf(user3));

    vm.prank(user1SmartWallet);
    bool success = assetToken.transfer(user3, transferAmount);

    console.log("Transfer success:", success);
    console.log("After transfer - User1 balance:", assetToken.balanceOf(user1SmartWallet));
    console.log("After transfer - User3 balance:", assetToken.balanceOf(user3));

    assertTrue(success, "Transfer should succeed");
    assertEq(assetToken.balanceOf(user1SmartWallet), 50_000 * 1e18, "User1 balance should decrease");
    assertEq(assetToken.balanceOf(user3), 100_000 * 1e18, "User3 balance should increase");
}
*/
    function testSmartWalletYieldClaim() public {
        uint256 yieldAmount = 1_000 * 1e18;
        uint256 tokenAmount = 10_000 * 1e18;

        vm.startPrank(OWNER);
        // Mint tokens to the smart wallet
        assetToken.mint(user1SmartWallet, tokenAmount);

        yieldCurrency.mint(OWNER, yieldAmount);
        yieldCurrency.approve(address(assetToken), yieldAmount);

        // Advance block timestamp
        vm.warp(block.timestamp + 1);
        assetToken.depositYield(yieldAmount);

        // Advance time to allow yield accrual
        vm.warp(block.timestamp + 30 days);
        vm.stopPrank();

        vm.prank(user1SmartWallet);
        (IERC20 claimedToken, uint256 claimedAmount) = assetToken.claimYield(
            user1SmartWallet
        );

        assertGt(claimedAmount, 0, "Claimed yield should be greater than zero");
        assertEq(
            address(claimedToken),
            address(yieldCurrency),
            "Claimed token should be yield currency"
        );
    }

    function testSmartWalletInteractionWithDEX() public {
        uint256 orderAmount = 10_000 * 1e18;

        bytes memory approveData = abi.encodeWithSelector(
            assetToken.approve.selector,
            address(mockDEX),
            orderAmount
        );

        vm.prank(user1SmartWallet);
        (bool success, ) = user1SmartWallet.call(approveData);
        require(success, "Approval failed");

        vm.prank(address(mockDEX));
        mockDEX.createOrder(user1SmartWallet, orderAmount);

        assertEq(
            assetToken.tokensHeldOnDEXs(user1SmartWallet),
            orderAmount,
            "DEX should hold the tokens"
        );
    }
}
