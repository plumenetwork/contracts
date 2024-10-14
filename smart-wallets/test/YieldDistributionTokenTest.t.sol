// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/token/AssetToken.sol";
import "../src/extensions/AssetVault.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/interfaces/ISmartWallet.sol";
import "../src/interfaces/ISignedOperations.sol";
import "../src/interfaces/IYieldReceiver.sol";
import "../src/interfaces/IAssetToken.sol";
import "../src/interfaces/IYieldToken.sol";
import "../src/interfaces/IAssetVault.sol";

import { MockSmartWallet } from "../src/mocks/MockSmartWallet.sol";


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
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
//ISmartWallet
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

contract YieldDistributionTokenTest is Test {
    address public constant OWNER = address(1);
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 1e18;

    // Contracts
    MockYieldCurrency yieldCurrency;
    AssetToken assetToken;
    MockDEX mockDEX;
    AssetVault assetVault;

    // Wallets and addresses
    MockSmartWallet public makerWallet;
    MockSmartWallet public takerWallet;
    address user1;
    address user2;
    address user3;
    address beneficiary;
    address userWallet;
    address proxyAdmin;

    function setUp() public {
        // Start impersonating OWNER
        vm.startPrank(OWNER);

        // Deploy MockYieldCurrency
        yieldCurrency = new MockYieldCurrency();

        // Deploy AssetToken
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
        //yieldCurrency.approve(address(assetVault), type(uint256).max);

        yieldCurrency.mint(OWNER, 3000000000000000000000);
        //yieldCurrency.mint(address(assetToken), 1_000_000_000_000_000_000_000);

        // Deploy MockDEX and register it
        mockDEX = new MockDEX(assetToken);
        assetToken.registerDEX(address(mockDEX));

        // Create maker's and taker's smart wallets
        makerWallet = new MockSmartWallet();
        takerWallet = new MockSmartWallet();

        // Create user addresses
        user1 = address(101);
        user2 = address(102);
        user3 = address(103);

        // Assign beneficiary and proxy admin addresses
        beneficiary = address(201);
        proxyAdmin = address(401);
        vm.stopPrank();
        // Create a user wallet and deploy AssetVault as that user
        userWallet = address(new MockSmartWallet());
        vm.prank(userWallet);
        assetVault = new AssetVault();

        vm.prank(OWNER);
        assetToken.mint(address(assetVault), 1e24); // Mint 1,000,000 tokens to the vault

        // Resume pranking as OWNER after deploying AssetVault
        vm.startPrank(OWNER);

        // Mint tokens to maker's wallet
        assetToken.mint(address(makerWallet), 100_000 * 1e18);

        // Mint tokens to user1 and user2 for tests
        assetToken.mint(user1, 100_000 * 1e18);
        assetToken.mint(user2, 200_000 * 1e18);

        // Stop impersonating OWNER
        vm.stopPrank();
    }

    function testRegisterAndUnregisterDEX() public {
        vm.startPrank(OWNER);

        address newDEX = address(4);

        assetToken.registerDEX(newDEX);
        assertTrue(
            assetToken.isDexAddressWhitelisted(newDEX),
            "DEX should be registered"
        );

        assetToken.unregisterDEX(newDEX);
        assertFalse(
            assetToken.isDexAddressWhitelisted(newDEX),
            "DEX should be unregistered"
        );

        vm.stopPrank();
    }


/*
    function testCreateAndCancelOrder() public {
        uint256 orderAmount = 10_000 * 1e18;

        // Maker approves the DEX to spend their tokens
        vm.startPrank(address(makerWallet));
        assetToken.approve(address(mockDEX), orderAmount);
        vm.stopPrank();

        // DEX creates an order on behalf of the maker
        vm.prank(address(mockDEX));
        mockDEX.createOrder(address(makerWallet), orderAmount);

        assertEq(
            assetToken.balanceOf(address(makerWallet)),
            90_000 * 1e18,
            "Maker's balance should decrease"
        );
        assertEq(
            assetToken.balanceOf(address(mockDEX)),
            orderAmount,
            "DEX should hold the tokens"
        );

        // DEX cancels the order and returns tokens to the maker
        vm.prank(address(mockDEX));
        mockDEX.cancelOrder(address(makerWallet), orderAmount);

        assertEq(
            assetToken.balanceOf(address(makerWallet)),
            100_000 * 1e18,
            "Maker's balance should be restored"
        );
        assertEq(
            assetToken.balanceOf(address(mockDEX)),
            0,
            "DEX should have zero balance"
        );
    }
*/
/*
    function testYieldDistribution() public {
        uint256 orderAmount = 10_000 * 1e18;
        uint256 yieldAmount = 1_000 * 1e18;

        // Maker approves the DEX to spend their tokens
        vm.startPrank(address(makerWallet));
        assetToken.approve(address(mockDEX), orderAmount);
        vm.stopPrank();

        // DEX creates an order on behalf of the maker
        vm.prank(address(mockDEX));
        mockDEX.createOrder(address(makerWallet), orderAmount);

        // Owner mints MockYieldCurrency to themselves
        vm.prank(OWNER);
        yieldCurrency.mint(OWNER, yieldAmount);

        // Owner approves the AssetToken to spend MockYieldCurrency
        vm.prank(OWNER);
        yieldCurrency.approve(address(assetToken), yieldAmount);

        // Advance block.timestamp to simulate passage of time
        vm.warp(block.timestamp + 1);

        // Owner deposits yield into the AssetToken with timestamp = block.timestamp
        vm.prank(OWNER);
        assetToken.depositYield(yieldAmount);

        // Advance the block timestamp to simulate passage of time
        vm.warp(block.timestamp + 1);

        // Maker claims yield
        vm.prank(address(makerWallet));
        (IERC20 claimedToken, uint256 claimedAmount) = assetToken.claimYield(
            address(makerWallet)
        );

        // Expected yield calculation
        uint256 totalSupply = assetToken.totalSupply();
        uint256 makerTotalBalance = assetToken.balanceOf(address(makerWallet)) +
            assetToken.tokensHeldOnDEXs(address(makerWallet));
        uint256 expectedYield = (yieldAmount * makerTotalBalance) / totalSupply;

        assertEq(
            address(claimedToken),
            address(yieldCurrency),
            "Claimed token should be yield currency"
        );
        assertEq(
            claimedAmount,
            expectedYield,
            "Claimed amount should match expected yield"
        );
    }
*/

// TODO: change to startprank
/*
function testMultipleYieldDepositsAndAccruals() public {
    uint256 yieldAmount1 = 500 * 1e18;
    uint256 yieldAmount2 = 1_000 * 1e18;
    uint256 yieldAmount3 = 1_500 * 1e18;

    // Get initial balances
    uint256 initialBalance1 = assetToken.balanceOf(address(user1));
    uint256 initialBalance2 = assetToken.balanceOf(address(user2));

    vm.prank(OWNER);
    assetToken.mint(address(user1), 100_000 * 1e18);
    
    vm.prank(OWNER);
    assetToken.mint(address(user2), 200_000 * 1e18);

    uint256 totalSupply = assetToken.totalSupply();

    // Advance time and deposit first yield
    vm.warp(block.timestamp + 1);
    vm.prank(OWNER);
    assetToken.depositYield(yieldAmount1);

    // Advance time and deposit second yield
    vm.warp(block.timestamp + 1);
    vm.prank(OWNER);
    assetToken.depositYield(yieldAmount2);

    // Transfer tokens from user1 to user2
    vm.prank(address(user1));
    assetToken.transfer(address(user2), 50_000 * 1e18);

    // Advance time and deposit third yield
    vm.warp(block.timestamp + 1);
    vm.prank(OWNER);
    assetToken.depositYield(yieldAmount3);

    // Advance time before claiming yield
    vm.warp(block.timestamp + 1);

    // Users claim their yield
    vm.prank(address(user1));
    (, uint256 claimedAmount1) = assetToken.claimYield(address(user1));

    vm.prank(address(user2));
    (, uint256 claimedAmount2) = assetToken.claimYield(address(user2));

    // Calculate expected yields
    uint256 expectedYield1 = (yieldAmount1 * (initialBalance1 + 100_000 * 1e18) / totalSupply) +
                             (yieldAmount2 * (initialBalance1 + 100_000 * 1e18) / totalSupply) +
                             (yieldAmount3 * (initialBalance1 + 50_000 * 1e18) / totalSupply);

    uint256 expectedYield2 = (yieldAmount1 * (initialBalance2 + 200_000 * 1e18) / totalSupply) +
                             (yieldAmount2 * (initialBalance2 + 200_000 * 1e18) / totalSupply) +
                             (yieldAmount3 * (initialBalance2 + 250_000 * 1e18) / totalSupply);

    // Assert the claimed amounts match expected yields
    assertEq(
        claimedAmount1,
        expectedYield1,
        "User1 claimed yield should match expected yield"
    );
    assertEq(
        claimedAmount2,
        expectedYield2,
        "User2 claimed yield should match expected yield"
    );

    // Print debug information
    console.log("Total Supply:", totalSupply);
    console.log("User1 Initial Balance:", initialBalance1);
    console.log("User2 Initial Balance:", initialBalance2);
    console.log("User1 Claimed Amount:", claimedAmount1);
    console.log("User1 Expected Yield:", expectedYield1);
    console.log("User2 Claimed Amount:", claimedAmount2);
    console.log("User2 Expected Yield:", expectedYield2);
}
*/
    /*

    function testDepositYieldWithZeroTotalSupply() public {
        uint256 yieldAmount = 1_000 * 1e18;

        // Attempt to deposit yield when total supply is zero
        vm.expectRevert(); // Expect any revert
        vm.prank(OWNER);
        assetToken.depositYield(yieldAmount);
    }
*/
   function testClaimYieldWithZeroBalance() public {
        uint256 yieldAmount = 1_000 * 1e18;

        vm.startPrank(OWNER);
        // Mint yield currency to OWNER
        yieldCurrency.mint(OWNER, yieldAmount);

        // Approve AssetToken to spend yield currency
        yieldCurrency.approve(address(assetToken), yieldAmount);

        // Advance time and deposit yield
        vm.warp(block.timestamp + 1);
        assetToken.depositYield(yieldAmount);

        // Advance time before claiming yield
        vm.warp(block.timestamp + 1);
        vm.stopPrank();

        // User with zero balance attempts to claim yield
        vm.prank(address(user3));
        (IERC20 claimedToken, uint256 claimedAmount) = assetToken.claimYield(address(user3));

        // Assert that claimed amount is zero
        assertEq(claimedAmount, 0, "Claimed amount should be zero");
    }

/*
function testDepositYieldWithPastTimestamp() public {
     vm.warp(2);
    uint256 yieldAmount = 1_000 * 1e18;

    vm.startPrank(OWNER);
    // Mint yield currency to OWNER
    yieldCurrency.mint(OWNER, yieldAmount);

    // Approve AssetToken to spend yield currency
    yieldCurrency.approve(address(assetToken), yieldAmount);

    // Warp to timestamp 2
   
    vm.warp(1);
    // Attempt to deposit yield with timestamp 1 (past)
    vm.expectRevert(abi.encodeWithSelector(InvalidTimestamp.selector, 2, 1));
    assetToken.depositYield(yieldAmount);

    vm.stopPrank();
}
*/
    function testAccrueYieldWithoutAdvancingTime() public {
        uint256 yieldAmount = 1_000 * 1e18;
        vm.startPrank(OWNER);

        // Mint tokens to OWNER
        assetToken.mint(OWNER, 100_000 * 1e18);

        // Mint yield currency to OWNER
        yieldCurrency.mint(OWNER, yieldAmount);

        // Approve AssetToken to spend yield currency
        yieldCurrency.approve(address(assetToken), yieldAmount);

        // Deposit yield
        assetToken.depositYield(yieldAmount);

        // Attempt to claim yield without advancing time
        (IERC20 claimedToken, uint256 claimedAmount) = assetToken.claimYield(OWNER);

        // Assert that claimed amount is zero
        assertEq(claimedAmount, 0, "Claimed amount should be zero");
        vm.stopPrank();
    }
/*
    function testPartialOrderFill() public {
        uint256 orderAmount = 10_000 * 1e18;
        uint256 fillAmount = 4_000 * 1e18;

        vm.prank(OWNER);
        // Mint tokens to maker
        assetToken.mint(address(makerWallet), 20_000 * 1e18);

        // Maker approves the DEX to spend their tokens
        vm.prank(address(makerWallet));
        assetToken.approve(address(mockDEX), orderAmount);

        // DEX creates an order on behalf of the maker
        vm.prank(address(mockDEX));
        mockDEX.createOrder(address(makerWallet), orderAmount);

        // Simulate partial fill by transferring tokens from DEX to taker
        vm.prank(address(mockDEX));
        assetToken.transfer(address(takerWallet), fillAmount);

        // Assert balances
        uint256 dexBalance = assetToken.balanceOf(address(mockDEX));
        assertEq(
            dexBalance,
            orderAmount - fillAmount,
            "DEX balance should reflect partial fill"
        );

        uint256 takerBalance = assetToken.balanceOf(address(takerWallet));
        assertEq(
            takerBalance,
            fillAmount,
            "Taker should receive the filled amount"
        );
    }
    */
/*
function testCancelingPartiallyFilledOrder() public {
    uint256 orderAmount = 10_000 * 1e18;
    uint256 fillAmount = 4_000 * 1e18;
    uint256 cancelAmount = orderAmount - fillAmount;

    vm.startPrank(OWNER);
    // Mint tokens to maker
    assetToken.mint(address(makerWallet), 20_000 * 1e18);
    vm.stopPrank();

    // Maker approves the DEX to spend their tokens
    vm.prank(address(makerWallet));
    assetToken.approve(address(mockDEX), orderAmount);

    // DEX creates an order on behalf of the maker
    vm.prank(address(mockDEX));
    mockDEX.createOrder(address(makerWallet), orderAmount);

    // Simulate partial fill by transferring tokens from DEX to taker
    vm.prank(address(mockDEX));
    assetToken.transfer(address(takerWallet), fillAmount);

    // DEX cancels the remaining order
    vm.prank(address(mockDEX));
    mockDEX.cancelOrder(address(makerWallet), cancelAmount);

    // Assert that maker's balance is restored for the unfilled amount
    uint256 makerBalance = assetToken.balanceOf(address(makerWallet));
    // TODO: how do we get to 116000000000000000000000
    assertEq(makerBalance, 116000000000000000000000, "Maker's balance should reflect the unfilled amount returned");

}
*/

/*
    function testOrderOverfillAttempt() public {
        uint256 orderAmount = 10_000 * 1e18;
        uint256 overfillAmount = 12_000 * 1e18;

        vm.prank(OWNER);
        // Mint tokens to maker
        assetToken.mint(address(makerWallet), 10_000 * 1e18);

        // Maker approves the DEX to spend their tokens
        vm.prank(address(makerWallet));
        assetToken.approve(address(mockDEX), orderAmount);

        // DEX creates an order on behalf of the maker
        vm.prank(address(mockDEX));
        mockDEX.createOrder(address(makerWallet), orderAmount);

        // Attempt to overfill the order
        vm.expectRevert(abi.encodeWithSelector(AssetToken.InsufficientBalance.selector, address(mockDEX)));



        vm.prank(address(mockDEX));
        assetToken.transfer(address(takerWallet), overfillAmount);
    }
    */
/*
    function testYieldAllowances() public {
        uint256 allowanceAmount = 50_000 * 1e18;
        uint256 expiration = block.timestamp + 30 days;

        // User wallet updates yield allowance for beneficiary
        vm.prank(address(userWallet));
        assetVault.updateYieldAllowance(
            assetToken,
            address(beneficiary),
            allowanceAmount,
            expiration
        );

        // Beneficiary accepts the yield allowance
        vm.prank(address(beneficiary));
        assetVault.acceptYieldAllowance(
            assetToken,
            allowanceAmount,
            expiration
        );

        // Assert that yield distribution is created
        uint256 balanceLocked = assetVault.getBalanceLocked(assetToken);
        assertEq(
            balanceLocked,
            allowanceAmount,
            "Balance locked should equal allowance amount"
        );
    }

function testRedistributeYield() public {
    uint256 yieldAmount = 1_000 * 1e18;
    uint256 allowanceAmount = 50_000 * 1e18;
    uint256 expiration = block.timestamp + 30 days;



    vm.prank(address(assetToken));
    yieldCurrency.mint(address(assetVault), 5 * yieldAmount);
    yieldCurrency.mint(address(yieldCurrency), 5 * yieldAmount);
    yieldCurrency.mint(address(userWallet), yieldAmount);


    // Set up yield allowance and accept it
    testYieldAllowances();

    // Advance time and deposit yield
    vm.warp(block.timestamp + 1);
    vm.prank(OWNER);
    assetToken.depositYield(yieldAmount);

    // Debug: Check AssetToken balance of AssetVault
    uint256 assetVaultBalance = assetToken.balanceOf(address(assetVault));
    console.log("AssetVault balance before redistribution:", assetVaultBalance);

    // Debug: Check YieldCurrency balance of AssetToken
    uint256 assetTokenYieldBalance = yieldCurrency.balanceOf(address(assetToken));
    console.log("AssetToken yield balance before redistribution:", assetTokenYieldBalance);

    // User wallet redistributes yield
    vm.prank(address(userWallet));
    assetVault.redistributeYield(assetToken, yieldCurrency, yieldAmount);

    // Debug: Check YieldCurrency balance of AssetVault
    uint256 assetVaultYieldBalance = yieldCurrency.balanceOf(address(assetVault));
    console.log("AssetVault yield balance after redistribution:", assetVaultYieldBalance);

    // Assert that beneficiary received yield
    uint256 beneficiaryYieldBalance = yieldCurrency.balanceOf(address(beneficiary));
    console.log("Beneficiary yield balance:", beneficiaryYieldBalance);

    // Debug: Check if the yield was claimed successfully
    (IERC20 claimedToken, uint256 claimedAmount) = assetToken.claimYield(address(assetVault));
    console.log("Claimed token:", address(claimedToken));
    console.log("Claimed amount:", claimedAmount);

    // Debug: Check the balance locked in AssetVault
    uint256 balanceLocked = assetVault.getBalanceLocked(assetToken);
    console.log("Balance locked in AssetVault:", balanceLocked);

    assertTrue(
        beneficiaryYieldBalance > 0,
        "Beneficiary should receive yield"
    );
}

    function testRenounceYieldDistributions() public {
        uint256 allowanceAmount = 50_000 * 1e18;
        uint256 expiration = block.timestamp + 30 days;

        // Set up yield allowance and accept it
        testYieldAllowances();

        // Beneficiary renounces their yield distribution
        vm.prank(address(beneficiary));

        // one day + 1
        vm.warp(86401);

        uint256 amountRenounced = assetVault.renounceYieldDistribution(
            assetToken,
            allowanceAmount,
            expiration
        );

        // Assert that the full amount was renounced
        assertEq(
            amountRenounced,
            allowanceAmount,
            "Amount renounced should equal allowance amount"
        );
    }
*/
/*
function testClearExpiredYieldDistributions() public {
    uint256 allowanceAmount = 50_000 * 1e18;
    uint256 expiration = block.timestamp + 1 days;

    vm.prank(address(userWallet));
    assetVault.updateYieldAllowance(assetToken, address(beneficiary), allowanceAmount, expiration);

    vm.prank(address(beneficiary));
    assetVault.acceptYieldAllowance(assetToken, allowanceAmount, expiration);

    // Check the yield distributions
    (address[] memory beneficiaries, uint256[] memory amounts, uint256[] memory expirations) = assetVault.getYieldDistributions(assetToken);
    require(beneficiaries.length > 0, "No yield distributions found");
    require(beneficiaries[0] == address(beneficiary), "Beneficiary not stored correctly");
    require(amounts[0] == allowanceAmount, "Amount not stored correctly");
    require(expirations[0] == expiration, "Expiration not stored correctly");

    uint256 initialBalanceLocked = assetVault.getBalanceLocked(assetToken);
    assertEq(initialBalanceLocked, allowanceAmount, "Balance locked should equal allowance amount");

    // Advance time past the expiration
    vm.warp(expiration + 1);

    // Clear expired yield distributions
    assetVault.clearYieldDistributions(assetToken);

    // Assert that balance locked is zero
    uint256 finalBalanceLocked = assetVault.getBalanceLocked(assetToken);
    assertEq(finalBalanceLocked, 0, "Balance locked should be zero after clearing");
}
*/
    function testTransferBetweenUsers() public {
        
        uint256 user1Balance_before = assetToken.balanceOf(address(user1));
        uint256 user2Balance_before = assetToken.balanceOf(address(user2));

        vm.prank(OWNER);
        // Mint tokens to user1
        assetToken.mint(address(user1), 100_000 * 1e18);

        // User1 transfers tokens to user2
        vm.prank(address(user1));
        assetToken.transfer(address(user2), 50_000 * 1e18);

        // Assert balances
        uint256 user1Balance = assetToken.balanceOf(address(user1));
        uint256 user2Balance = assetToken.balanceOf(address(user2));
        assertEq(user1Balance, user1Balance_before + (50_000 * 1e18), "User1 balance should decrease");
        assertEq(user2Balance, user2Balance_before + (50_000 * 1e18), "User2 balance should increase");
    }

    function testTransferToEOA() public {

        uint256 user1Balance_before = assetToken.balanceOf(address(user1));
        uint256 user3Balance_before = assetToken.balanceOf(address(user3));

        vm.prank(OWNER);
        // Mint tokens to user1
        assetToken.mint(address(user1), 100_000 * 1e18);

        // User1 transfers tokens to EOA (user3)
        vm.prank(address(user1));
        assetToken.transfer(address(user3), 50_000 * 1e18);

        // Assert balances
        uint256 user1Balance = assetToken.balanceOf(address(user1));
        uint256 user3Balance = assetToken.balanceOf(address(user3));
        assertEq(user1Balance, user1Balance_before + 50_000 * 1e18, "User1 balance should decrease");
        assertEq(user3Balance, user3Balance_before + 50_000 * 1e18, "User3 balance should increase");
    }

    function testTransferToNonSmartWalletContract() public {
        // Deploy a simple contract that does not implement ISmartWallet
        NonSmartWalletContract nonSmartWallet = new NonSmartWalletContract();
        uint256 user1Balance_before = assetToken.balanceOf(address(user1));



        vm.prank(OWNER);
        // Mint tokens to user1
        assetToken.mint(address(user1), 100_000 * 1e18);

        // User1 transfers tokens to the non-smart wallet contract
        vm.prank(address(user1));
        assetToken.transfer(address(nonSmartWallet), 50_000 * 1e18);

        // Assert balances
        uint256 user1Balance = assetToken.balanceOf(address(user1));
        uint256 contractBalance = assetToken.balanceOf(address(nonSmartWallet));
//        assertEq(user1Balance, 50_000 * 1e18, "User1 balance should decrease");
        assertEq(user1Balance, user1Balance_before + 50_000 * 1e18, "User1 balance should decrease");

        assertEq(
            contractBalance,
            50_000 * 1e18,
            "Contract balance should increase"
        );


        
    }

    function testUnauthorizedMinting() public {
        // Attempt to mint tokens from non-owner address
        // TODO: add OwnableUnauthorizedAccount.selector
        vm.expectRevert();
        vm.prank(address(user1));
        assetToken.mint(address(user1), 10_000 * 1e18);
    }

function testUnauthorizedYieldDeposit() public {
    uint256 yieldAmount = 1_000 * 1e18;

    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(user1)));
    vm.prank(address(user1));
    assetToken.depositYield(yieldAmount);
}

    function testUnauthorizedYieldAllowanceUpdate() public {
        uint256 allowanceAmount = 50_000 * 1e18;
        uint256 expiration = block.timestamp + 30 days;

        // Attempt to update yield allowance from non-wallet address
        vm.expectRevert(
            abi.encodeWithSelector(UnauthorizedCall.selector, address(user1))
        );
        vm.prank(address(user1));
        assetVault.updateYieldAllowance(
            assetToken,
            address(beneficiary),
            allowanceAmount,
            expiration
        );
    }

function testLargeTokenBalances() public {
    uint256 initialBalance1 = assetToken.balanceOf(address(user1));
    uint256 initialBalance2 = assetToken.balanceOf(address(user2));
    uint256 largeAmount = type(uint256).max / 2 - initialBalance1;

    vm.prank(OWNER);
    assetToken.mint(address(user1), largeAmount);

    uint256 user1Balance = assetToken.balanceOf(address(user1));
    
    console.log("User1 initial balance: ", initialBalance1);
    console.log("User2 initial balance: ", initialBalance2);
    console.log("Amount minted to User1:", largeAmount);
    console.log("User1 final balance:   ", user1Balance);
    console.log("Expected max balance:  ", type(uint256).max / 2);

    assertEq(user1Balance, type(uint256).max / 2, "User1 balance should be maximum");

    // Attempt to transfer tokens
    vm.prank(address(user1));
    assetToken.transfer(address(user2), user1Balance / 2);

    uint256 user2Balance = assetToken.balanceOf(address(user2));
    uint256 expectedUser2Balance = (type(uint256).max / 4) + initialBalance2;

    console.log("User2 final balance:   ", user2Balance);
    console.log("Expected User2 balance:", expectedUser2Balance);

    assertEq(user2Balance, expectedUser2Balance, "User2 balance should be half of user1's balance plus initial balance");
}
/*
    function testSmallYieldAmounts() public {
        uint256 smallYield = 1; // Smallest unit
        vm.prank(OWNER);
        // Mint tokens to user1
        assetToken.mint(address(user1), 100_000 * 1e18);

        // Advance time and deposit small yield
        vm.warp(block.timestamp + 1);
        vm.prank(OWNER);
        assetToken.depositYield(smallYield);

        // Advance time before claiming yield
        vm.warp(block.timestamp + 1000);

        // User1 claims yield
        vm.prank(address(user1));
        (, uint256 claimedAmount) = assetToken.claimYield(address(user1));

        // Assert that claimed amount is accurate
        assertEq(
            claimedAmount,
            smallYield,
            "Claimed amount should match small yield"
        );
    }
*/
    function testInvalidFunctionCalls() public {
        // Attempt to call a non-existent function
        bytes memory data = abi.encodeWithSignature("nonExistentFunction()");
        (bool success, ) = address(assetToken).call(data);
        assertTrue(!success, "Call to non-existent function should fail");
    }
}
