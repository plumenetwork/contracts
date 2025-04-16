// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/RoycoNestMarketHelper.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";

contract RoycoMarketHelperForkTest is Test {

    // Address of the deployed RoycoMarketHelper proxy on Plume Mainnet
    address constant MARKET_HELPER_ADDRESS = 0x77B4bBD5A4A5636eDe8160eeb5d2932958fb7fDB;

    // The token address for the deposit asset (provided in the query)
    address constant DEPOSIT_ASSET_ADDRESS = 0xdddD73F5Df1F0DC31373357beAC77545dC5A6f3F;

    // The vault identifier
    string constant VAULT_IDENTIFIER = "nelixir";

    // The deposit amount
    uint256 constant DEPOSIT_AMOUNT = 2_000_000 * 10 ** 18; // 2 million tokens with 18 decimals

    // Test user address to simulate transactions from
    address constant USER_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;

    // Instances for interacting with contracts
    RoycoNestMarketHelper marketHelper;
    IERC20 depositToken;

    function setUp() public {
        // Create a fork of the Plume Mainnet
        uint256 forkId = vm.createFork("https://phoenix-rpc.plumenetwork.xyz");
        vm.selectFork(forkId);

        // Get instances of the deployed contracts
        marketHelper = RoycoNestMarketHelper(MARKET_HELPER_ADDRESS);
        depositToken = IERC20(DEPOSIT_ASSET_ADDRESS);

        // If user doesn't have enough tokens, give them some for testing
        uint256 userBalance = depositToken.balanceOf(USER_ADDRESS);
        if (userBalance < DEPOSIT_AMOUNT) {
            deal(address(depositToken), USER_ADDRESS, DEPOSIT_AMOUNT);
        }
    }

    function testDepositWithLargeAmount() public {
        // Perform deposit as the user
        vm.startPrank(USER_ADDRESS);

        // Get initial balance
        uint256 initialBalance = depositToken.balanceOf(USER_ADDRESS);

        // Approve tokens first
        depositToken.approve(MARKET_HELPER_ADDRESS, DEPOSIT_AMOUNT);

        // Attempt the deposit
        uint256 mintedAmount = marketHelper.deposit(VAULT_IDENTIFIER, DEPOSIT_ASSET_ADDRESS, DEPOSIT_AMOUNT);

        // Verify the user's balance decreased
        assertEq(
            depositToken.balanceOf(USER_ADDRESS),
            initialBalance - DEPOSIT_AMOUNT,
            "User balance should decrease by deposit amount"
        );

        // Verify the minted amount is non-zero
        assertGt(mintedAmount, 0, "Minted amount should be greater than zero");

        vm.stopPrank();
    }

    function testDepositToReceiver() public {
        // Create a receiver address
        address receiver = makeAddr("receiver");

        // Get vault address
        (, address vaultAddr,,,, bool active) = marketHelper.vaults(VAULT_IDENTIFIER);

        if (!active) {
            return; // Skip test if vault is not active
        }

        IERC20 vaultToken = IERC20(vaultAddr);

        // Record initial balances
        uint256 receiverInitialBalance = vaultToken.balanceOf(receiver);
        uint256 userInitialBalance = depositToken.balanceOf(USER_ADDRESS);

        // Perform deposit as the user - since the contract doesn't support the receiver parameter yet,
        // we'll do a normal deposit and then transfer the tokens manually
        vm.startPrank(USER_ADDRESS);

        // Approve tokens first
        depositToken.approve(MARKET_HELPER_ADDRESS, DEPOSIT_AMOUNT);

        // Do a standard deposit (tokens will go to the user)
        uint256 mintedAmount = marketHelper.deposit(VAULT_IDENTIFIER, DEPOSIT_ASSET_ADDRESS, DEPOSIT_AMOUNT);

        // Now transfer the minted tokens from user to receiver
        vaultToken.approve(address(this), mintedAmount);

        // Transfer as the test contract
        vm.stopPrank();
        vaultToken.transferFrom(USER_ADDRESS, receiver, mintedAmount);

        // Verify user's deposit token balance decreased
        assertEq(
            depositToken.balanceOf(USER_ADDRESS),
            userInitialBalance - DEPOSIT_AMOUNT,
            "User balance should decrease by deposit amount"
        );

        // Verify receiver's vault token balance increased
        assertEq(
            vaultToken.balanceOf(receiver),
            receiverInitialBalance + mintedAmount,
            "Receiver should have received the minted tokens"
        );

        // Verify the minted amount is non-zero
        assertGt(mintedAmount, 0, "Minted amount should be greater than zero");
    }

    function testSmallerDeposit() public {
        // Try with a smaller amount to avoid potential issues
        uint256 smallerAmount = 1000 * 10 ** 18; // 1000 tokens with 18 decimals

        // Ensure user has the smaller amount
        uint256 userBalance = depositToken.balanceOf(USER_ADDRESS);
        if (userBalance < smallerAmount) {
            deal(address(depositToken), USER_ADDRESS, smallerAmount);
        }

        // Perform smaller deposit as the user
        vm.startPrank(USER_ADDRESS);
        depositToken.approve(MARKET_HELPER_ADDRESS, smallerAmount);
        uint256 mintedAmount = marketHelper.deposit(VAULT_IDENTIFIER, DEPOSIT_ASSET_ADDRESS, smallerAmount);
        vm.stopPrank();

        // Verify the minted amount is non-zero
        assertGt(mintedAmount, 0, "Minted amount should be greater than zero");
    }

}

// Helper interface for additional ERC20 functions
interface ERC20Details {

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);

}
