// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { BoringVaultPredeposit } from "../src/BoringVaultPredeposit.sol";
import "../src/proxy/BoringVaultPredepositProxy.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "forge-std/Test.sol";

import { IBoringVault } from "../src/interfaces/IBoringVault.sol";
import { BridgeData, ITeller } from "../src/interfaces/ITeller.sol";
import { console2 } from "forge-std/console2.sol";

contract BoringVaultPredepositTest is Test {

    BoringVaultPredeposit public implementation;
    BoringVaultPredeposit public staking;
    address public admin;
    address public user1;
    address public user2;
    TimelockController public timelock;

    // Real token addresses
    IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 constant USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20 constant USDe = IERC20(0x4c9EDD5852cd905f086C759E8383e09bff1E68B3);
    IERC20 constant sUSDe = IERC20(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497);
    IERC20 constant nYIELD = IERC20(0x892DFf5257B39f7afB7803dd7C81E8ECDB6af3E8);

    address constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address nYieldTeller = 0x92A735f600175FE9bA350a915572a86F68EBBE66;
    address nYieldVault = 0x892DFf5257B39f7afB7803dd7C81E8ECDB6af3E8;

    using SafeERC20 for IERC20;

    function setUp() public {
        // Fork mainnet (Speciying a block number allows us to cache the state at that block)
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), 21_769_985);

        // Setup accounts
        admin = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy timelock
        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        proposers[0] = admin;
        executors[0] = admin;
        timelock = new TimelockController(0, proposers, executors, admin);

        // Create BoringVault config
        BoringVaultPredeposit.BoringVault memory boringVaultConfig =
            BoringVaultPredeposit.BoringVault({ teller: ITeller(nYieldTeller), vault: IBoringVault(nYieldVault) });

        // Deploy implementation
        implementation = new BoringVaultPredeposit();

        bytes32 salt = keccak256(abi.encodePacked(block.timestamp, "nYieldPredeposit"));

        // Encode initialize function call
        bytes memory initData =
            abi.encodeWithSelector(BoringVaultPredeposit.initialize.selector, timelock, admin, boringVaultConfig, salt);

        // Deploy proxy
        BoringVaultPredepositProxy proxy = new BoringVaultPredepositProxy(address(implementation), initData);

        // Cast proxy to BoringVaultPredeposit for easier interaction
        staking = BoringVaultPredeposit(payable(address(proxy)));

        // Setup initial state
        vm.startPrank(admin);
        staking.allowToken(USDC);
        staking.allowToken(USDT);
        staking.allowToken(USDe);
        staking.allowToken(sUSDe);
        staking.setVaultConversionStartTime(block.timestamp + 1 days);
        vm.stopPrank();

        // Fund test accounts
        deal(address(USDC), user1, 1000 * 1e6);
        deal(address(USDC), user2, 1000 * 1e6);
        deal(address(USDT), user1, 1000 * 1e6);
        deal(address(USDT), user2, 1000 * 1e6);
        deal(address(USDe), user1, 1000 * 1e18);
        deal(address(USDe), user2, 1000 * 1e18);
    }

    function testStorageSlot() public {
        // Calculate the storage slot
        bytes32 slot = keccak256(abi.encode(uint256(keccak256("plume.storage.nYieldBoringVaultPredeposit")) - 1))
            & ~bytes32(uint256(0xff));

        // Log the results for verification
        console.logBytes32(keccak256("plume.storage.nYieldBoringVaultPredeposit"));
        console.log("Minus 1:");
        console.logBytes32(bytes32(uint256(keccak256("plume.storage.nYieldBoringVaultPredeposit")) - 1));
        console.log("Final slot:");
        console.logBytes32(slot);

        // Optional: Convert to uint256 for decimal representation
        console.log("Slot as uint256:", uint256(slot));
    }

    function testDepositToVault_RevertBeforeStart() public {
        // Setup
        uint256 depositAmount = 1000e6; // 1000 USDC
        deal(address(USDC), user1, depositAmount);

        vm.startPrank(user1);
        USDC.approve(address(staking), depositAmount);
        staking.deposit(depositAmount, USDC);

        // Try to deposit before start time
        vm.expectRevert(
            abi.encodeWithSelector(
                BoringVaultPredeposit.ConversionNotStarted.selector,
                block.timestamp,
                staking.getVaultConversionStartTime()
            )
        );
        staking.depositAllTokensToVault(9900);
        vm.stopPrank();
    }
    /*
    function testBatchDepositGas() public {
        // Setup test data
        uint256 batchSize = 1000; // Reduced from 20000 to 1000

        address[] memory recipients = new address[](batchSize);
        IERC20[] memory tokens = new IERC20[](batchSize);
        // Ensure contract has enough ETH for gas
        vm.deal(address(staking), 100 ether);
        uint256 initialBalance = address(staking).balance;
        console2.log("Initial contract balance (ETH):", initialBalance / 1e18);
        // Fill arrays with test data
        for (uint256 i = 0; i < batchSize; i++) {
            recipients[i] = address(uint160(i + 1));
            tokens[i] = USDC; // Use USDC for all users

            // Fund and stake some USDC for each user
            deal(address(USDC), recipients[i], 1000 * 1e6); // Give each user 1000 USDC
            vm.startPrank(recipients[i]);
            USDC.approve(address(staking), 1000 * 1e6);
            staking.deposit(1000 * 1e6, USDC);
            vm.stopPrank();
        }

        // Set conversion start time to now
        vm.prank(admin);
        staking.setVaultConversionStartTime(block.timestamp);

        // Call as timelock
        vm.startPrank(address(timelock));
        // Measure gas
        uint256 startGas = gasleft();
        staking.batchDepositToVault(recipients, tokens, 9500);
        uint256 gasUsed = startGas - gasleft();
        vm.stopPrank();

        uint256 gweiPrice = 3.919e9; // 3.919 gwei in wei
        uint256 ethPrice = 3500; // $3,500 per ETH

        uint256 ethCost = (gasUsed * gweiPrice) / 1e18;
        uint256 usdCost = ethCost * ethPrice;

        uint256 finalBalance = address(staking).balance;
        uint256 actualEthUsed = initialBalance - finalBalance;

        console2.log("Final contract balance (ETH):", finalBalance / 1e18);
        console2.log("Actual ETH used:", actualEthUsed / 1e18);

        console2.log("Gas used:", gasUsed);
        console2.log("Estimated cost in ETH:", ethCost);
        console2.log("Estimated cost in USD:", usdCost);

        // Extrapolate to 20k users
        console2.log("Estimated total gas for 20k users:", gasUsed * 20);
        console2.log("Estimated total ETH cost for 20k users:", ethCost * 20);
        console2.log("Estimated total USD cost for 20k users:", usdCost * 20);
    }
    */

    function testDepositToVault() public {
        // Setup
        uint256 depositAmount = 1000e6; // 1000 USDC
        deal(address(USDC), user1, depositAmount);

        // Set conversion start time to now
        vm.prank(admin);
        staking.setVaultConversionStartTime(block.timestamp);

        vm.startPrank(user1);

        // First stake USDC
        USDC.approve(address(staking), depositAmount);
        staking.deposit(depositAmount, USDC);

        // Need to approve vault to spend USDC
        USDC.approve(address(nYIELD), depositAmount);

        // Then deposit to vault
        uint256 minimumMintBps = 9900;
        uint256[] memory shares = staking.depositAllTokensToVault(minimumMintBps);

        // Verify results - check the USDC position in the shares array
        assertEq(shares[0], depositAmount, "Should receive same amount of shares");
        assertEq(nYIELD.balanceOf(user1), depositAmount, "Should receive nYIELD tokens");
        assertEq(USDC.balanceOf(address(staking)), 0, "Should have no USDC left");

        vm.stopPrank();
    }

    function testBatchDepositToVault_RevertBeforeStart() public {
        // Setup users with deposits
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = USDC;
        tokens[1] = USDC;

        // Give users USDC and let them deposit
        deal(address(USDC), user1, 1e9);
        vm.startPrank(user1);
        USDC.approve(address(staking), 1e9);
        staking.deposit(1e9, USDC);
        vm.stopPrank();

        deal(address(USDC), user2, 2e9);
        vm.startPrank(user2);
        USDC.approve(address(staking), 2e9);
        staking.deposit(2e9, USDC);
        vm.stopPrank();

        // Set future conversion start time
        uint256 startTime = block.timestamp + 1 days;
        vm.prank(admin);
        staking.setVaultConversionStartTime(startTime);

        // Try to batch deposit before start time
        vm.startPrank(address(timelock));
        vm.expectRevert(abi.encodeWithSelector(BoringVaultPredeposit.VaultConversionNotStarted.selector));
        staking.batchDepositToVault(users, tokens, 1);
        vm.stopPrank();
    }

    function testBatchDepositToVault() public {
        // Setup
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;

        IERC20[] memory depositAssets = new IERC20[](2);
        depositAssets[0] = IERC20(address(USDC));
        depositAssets[1] = IERC20(address(USDC));

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000 * 1e6; // 1000 USDC
        amounts[1] = 2000 * 1e6; // 2000 USDC

        // Fund users with USDC
        deal(address(USDC), user1, amounts[0]);
        deal(address(USDC), user2, amounts[1]);

        // First have users stake their tokens
        vm.startPrank(user1);
        USDC.approve(address(staking), amounts[0]);
        staking.deposit(amounts[0], USDC);
        vm.stopPrank();

        vm.startPrank(user2);
        USDC.approve(address(staking), amounts[1]);
        staking.deposit(amounts[1], USDC);
        vm.stopPrank();

        // Set conversion start time to now
        vm.prank(admin);
        staking.setVaultConversionStartTime(block.timestamp);

        // Record initial balances
        uint256 user1InitialBalance = nYIELD.balanceOf(user1);
        uint256 user2InitialBalance = nYIELD.balanceOf(user2);

        // Execute batch deposit as timelock
        vm.startPrank(address(timelock));
        uint256 minimumMint = 9900; // 9900 / 10000 = 99%
        uint256[] memory receivedShares = staking.batchDepositToVault(recipients, depositAssets, minimumMint);
        vm.stopPrank();

        // Verify results
        assertEq(receivedShares[0], amounts[0], "User1 should receive correct shares");
        assertEq(receivedShares[1], amounts[1], "User2 should receive correct shares");
        assertEq(
            nYIELD.balanceOf(user1), user1InitialBalance + amounts[0], "User1 should receive correct nYIELD amount"
        );
        assertEq(
            nYIELD.balanceOf(user2), user2InitialBalance + amounts[1], "User2 should receive correct nYIELD amount"
        );
        assertEq(USDC.balanceOf(address(staking)), 0, "Contract should have no USDC left");
    }

    function testBatchDepositToVault_RevertOnNonAdmin() public {
        address[] memory recipients = new address[](1);
        IERC20[] memory depositAssets = new IERC20[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256 minimumMintBps = 9900; // 99%

        vm.prank(user1);
        vm.expectRevert();
        staking.batchDepositToVault(recipients, depositAssets, minimumMintBps);
    }

    function test_RevertWhen_NoBalance() public {
        vm.prank(user1);
        staking.depositAllTokensToVault(9900);
    }

    function testStaking() public {
        vm.startPrank(user1);
        USDC.approve(address(staking), 100 * 1e6);
        staking.deposit(100 * 1e6, USDC);
        vm.stopPrank();

        // Get user state for specific token
        (uint256 tokenAmount, uint256 lastUpdate) = staking.getUserStateForToken(user1, USDC);

        // Verify amounts
        assertEq(tokenAmount, 100 * 1e18); // Amount in base unit decimals (e18)
        assertTrue(lastUpdate > 0);
        assertEq(staking.getUserTokenAmounts(user1, USDC), 100 * 1e18);
    }

    function test_RevertWhen_StakingUnallowedToken() public {
        // Create a random token address that's not allowed
        address randomToken = address(0x123);
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(BoringVaultPredeposit.NotAllowedToken.selector, randomToken));
        staking.deposit(100 * 1e6, IERC20(randomToken));
    }

    function testSetVaultConversionStartTime() public {
        uint256 newStartTime = block.timestamp + 7 days;
        vm.prank(admin);
        staking.setVaultConversionStartTime(newStartTime);
        assertEq(staking.getVaultConversionStartTime(), newStartTime);
    }

    function test_RevertWhen_NonAdminSetsStartTime() public {
        vm.prank(user1);
        vm.expectRevert();
        staking.setVaultConversionStartTime(block.timestamp + 1 days);
    }

    function testReinitialize() public {
        address newMultisig = address(0x123);
        TimelockController newTimelock = new TimelockController(0, new address[](0), new address[](0), address(this));

        vm.prank(admin);
        staking.reinitialize(newMultisig, newTimelock);

        assertEq(staking.getMultisig(), newMultisig);
        assertEq(address(staking.getTimelock()), address(newTimelock));
    }

    function testSetMultisig() public {
        address newMultisig = address(0x123);

        // Get current timelock
        address timelock_ = address(staking.getTimelock());

        // Grant admin role to timelock if it doesn't have it
        bytes32 adminRole = staking.ADMIN_ROLE();
        vm.prank(admin);
        staking.grantRole(adminRole, timelock_);

        // Set new multisig using timelock
        vm.prank(timelock_);
        staking.setMultisig(newMultisig);

        // Verify the change
        assertEq(staking.getMultisig(), newMultisig);
    }
    /*
    function testAdminWithdraw() public {
        // Setup initial state
        vm.startPrank(user1);
        USDC.approve(address(staking), 100 * 1e6);
        staking.deposit(100 * 1e6, USDC);
        vm.stopPrank();

        uint256 initialBalance = USDC.balanceOf(staking.getMultisig());

        vm.prank(address(staking.getTimelock()));
        staking.adminWithdraw();

        uint256 finalBalance = USDC.balanceOf(staking.getMultisig());
        assertEq(finalBalance - initialBalance, 100 * 1e6);
        assertGt(staking.getEndTime(), 0);
    }
    */

    function testPause() public {
        vm.prank(admin);
        staking.pause();

        assertTrue(staking.isPaused());
    }

    function testUnpause() public {
        vm.startPrank(admin);
        staking.pause();
        staking.unpause();
        vm.stopPrank();

        assertFalse(staking.isPaused());
    }

    function testGetters() public {
        assertEq(staking.getTotalAmount(USDC), 0);

        address[] memory users = staking.getUsers();
        assertEq(users.length, 0);

        // Get user state with new return types
        (IERC20[] memory tokens, uint256[] memory amounts, uint256 lastUpdate) = staking.getUserState(user1);

        // Check general state
        assertEq(lastUpdate, 0);

        // Check USDC state specifically
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == USDC) {
                assertEq(amounts[i], 0);
                break;
            }
        }

        IERC20[] memory stablecoins = staking.getTokenList();
        assertTrue(stablecoins.length > 0);

        assertTrue(staking.isAllowedToken(USDC));

        assertFalse(staking.isPaused());
    }
    /*
    function testFailAdminWithdrawAfterEnd() public {
        vm.prank(address(staking.getTimelock()));
        staking.adminWithdraw();

        vm.prank(address(staking.getTimelock()));
        staking.adminWithdraw(); // Should fail as staking has ended
    }
    */

    function test_RevertWhen_PausingAlreadyPaused() public {
        vm.startPrank(admin);
        staking.pause();
        vm.expectRevert(BoringVaultPredeposit.AlreadyPaused.selector);
        staking.pause(); // Should fail
        vm.stopPrank();
    }

    function test_RevertWhen_UnpausingWhenNotPaused() public {
        vm.prank(admin);
        vm.expectRevert(BoringVaultPredeposit.NotPaused.selector);
        staking.unpause(); // Should fail as contract is not paused
    }

    function testWithdraw() public {
        // Setup
        vm.startPrank(user1);
        USDC.approve(address(staking), 100 * 1e6);
        staking.deposit(100 * 1e6, USDC);
        vm.stopPrank();

        uint256 initialBalance = USDC.balanceOf(user1);

        // Withdraw
        vm.prank(user1);
        staking.withdraw(50 * 1e6, USDC);

        // Assertions
        assertEq(USDC.balanceOf(user1), initialBalance + 50 * 1e6);
        assertEq(staking.getUserTokenAmounts(user1, USDC), 50 * 1e18); // Amount in bae unit decimals (e18)
        assertEq(staking.getTotalAmount(USDC), 50 * 1e18); // Amount in bae unit decimals (e18)
    }

    function testBaseUnitConversions() public {
        // Use DAI which has 18 decimals (same as _BASE)
        IERC20 token18 = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F); // DAI address

        vm.startPrank(admin);
        staking.allowToken(token18);
        vm.stopPrank();

        // Deal some DAI to user1
        deal(address(token18), user1, 1 ether);

        // Test _toBaseUnits with 18 decimals
        vm.startPrank(user1);
        token18.approve(address(staking), 1 ether);
        staking.deposit(1 ether, token18);
        vm.stopPrank();

        // Get user state and verify amounts
        (uint256 tokenAmount, uint256 lastUpdate) = staking.getUserStateForToken(user1, token18);
        assertEq(tokenAmount, 1 ether);
        assertTrue(lastUpdate > 0);

        // Test withdraw to verify _fromBaseUnits
        vm.prank(user1);
        staking.withdraw(0.5 ether, token18);

        // Verify final state
        (tokenAmount, lastUpdate) = staking.getUserStateForToken(user1, token18);
        assertEq(tokenAmount, 0.5 ether);
        assertEq(token18.balanceOf(user1), 0.5 ether);
    }

    function test_RevertWhen_WithdrawingInsufficientBalance() public {
        // Setup
        vm.startPrank(user1);
        USDC.approve(address(staking), 100 * 1e6);
        staking.deposit(100 * 1e6, USDC);
        vm.stopPrank();

        // Try to withdraw more than staked
        vm.prank(user1);

        vm.expectRevert(
            abi.encodeWithSelector(
                BoringVaultPredeposit.InsufficientStaked.selector,
                user1,
                USDC,
                150e18, // Amount in base units
                100e18 // Current balance in base units
            )
        );
        staking.withdraw(150 * 1e6, USDC); // Should revert with InsufficientStaked
    }

    function test_RevertWhen_AllowingAlreadyAllowedStablecoin() public {
        // USDC is already allowed in setUp()
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(BoringVaultPredeposit.AlreadyAllowedToken.selector, USDC));
        staking.allowToken(USDC); // Should revert with AlreadyAllowedStablecoin
    }

    function testRequestAutomigration() public {
        // Setup
        uint256 depositAmount = 1000e6; // 1000 USDC
        vm.prank(admin);
        staking.setAutomigrationCap(100);
        vm.prank(admin);
        staking.setMinTokenDepositForAutomigration(USDC, 500e6); // 500 USDC minimum

        // Deposit enough to meet requirements
        vm.startPrank(user1);
        USDC.approve(address(staking), depositAmount);
        staking.deposit(depositAmount, USDC);

        // Request automigration
        staking.requestAutomigration();
        vm.stopPrank();

        assertTrue(staking.hasRequestedAutomigration(user1));
        assertEq(staking.getRemainingAutomigrationSlots(), 99);
    }

    function testRequestAutomigrationWithMultipleTokens() public {
        // Setup automigration parameters
        vm.startPrank(admin);
        staking.setAutomigrationCap(100);
        staking.setMinTokenDepositForAutomigration(USDC, 1000e6); // 1000 USDC
        staking.setMinTokenDepositForAutomigration(USDT, 1000e6); // 1000 USDT (same as USDC)
        vm.stopPrank();

        // Setup user balances and deposits
        vm.startPrank(user1);

        // For USDC (6 decimals)
        deal(address(USDC), user1, 600e6); // 600 USDC
        USDC.safeIncreaseAllowance(address(staking), 600e6);
        staking.deposit(600e6, USDC);

        // For USDT (6 decimals)
        deal(address(USDT), user1, 300e6); // 300 USDT
        USDT.safeIncreaseAllowance(address(staking), 300e6);
        staking.deposit(300e6, USDT);

        // Create arrays for the expected error
        IERC20[] memory tokens = new IERC20[](4);
        tokens[0] = USDC;
        tokens[1] = USDT;
        tokens[2] = IERC20(0x4c9EDD5852cd905f086C759E8383e09bff1E68B3);
        tokens[3] = IERC20(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497);

        uint256[] memory amounts = new uint256[](4);
        amounts[0] = 600e18; // 600 in base units (e18)
        amounts[1] = 300e18; // 300 in base units (e18)
        amounts[2] = 0;
        amounts[3] = 0;

        uint256[] memory minAmounts = new uint256[](4);
        minAmounts[0] = 1000e6; // 1000 USDC minimum
        minAmounts[1] = 1000e6; // 1000 USDT minimum (same as USDC)
        minAmounts[2] = 0;
        minAmounts[3] = 0;

        vm.expectRevert(
            abi.encodeWithSelector(
                BoringVaultPredeposit.InsufficientDepositForAutomigration.selector, tokens, amounts, minAmounts
            )
        );

        staking.requestAutomigration();
        vm.stopPrank();
    }

    function test_RevertWhen_InsufficientDepositForAutomigration() public {
        // Setup
        vm.prank(admin);
        staking.setAutomigrationCap(100);
        vm.prank(admin);
        staking.setMinTokenDepositForAutomigration(USDC, 1000e6); // 1000 USDC minimum

        // Deposit less than minimum
        vm.startPrank(user1);
        USDC.approve(address(staking), 500e6);
        staking.deposit(500e6, USDC);

        vm.expectRevert();
        // Should fail
        staking.requestAutomigration();
        vm.stopPrank();
    }

    function test_RevertWhen_AutomigrationCapReached() public {
        // Setup
        vm.prank(admin);
        staking.setAutomigrationCap(1);
        vm.prank(admin);
        staking.setMinTokenDepositForAutomigration(USDC, 500e6);

        // First user requests automigration
        vm.startPrank(user1);
        USDC.approve(address(staking), 1000e6);
        staking.deposit(1000e6, USDC);
        staking.requestAutomigration();
        vm.stopPrank();

        // Second user tries to request (should fail)
        vm.startPrank(user2);
        USDC.approve(address(staking), 1000e6);
        staking.deposit(1000e6, USDC);

        vm.expectRevert(BoringVaultPredeposit.AutomigrationCapReached.selector);
        staking.requestAutomigration();
        vm.stopPrank();
    }

    function testCancelAutomigrationRequest() public {
        // Setup
        vm.prank(admin);
        staking.setAutomigrationCap(100);
        vm.prank(admin);
        staking.setMinTokenDepositForAutomigration(USDC, 500e6);

        // Request automigration
        vm.startPrank(user1);
        USDC.approve(address(staking), 1000e6);
        staking.deposit(1000e6, USDC);
        staking.requestAutomigration();

        // Cancel request
        staking.cancelAutomigrationRequest();
        vm.stopPrank();

        assertFalse(staking.hasRequestedAutomigration(user1));
        assertEq(staking.getRemainingAutomigrationSlots(), 100);
    }

    function test_RevertWhen_CancelingNonexistentAutomigrationRequest() public {
        vm.prank(user1);
        vm.expectRevert(BoringVaultPredeposit.NoAutomigrationRequest.selector);
        staking.cancelAutomigrationRequest();
    }

    function testAutomigrationStatusAfterWithdraw() public {
        // Setup
        vm.prank(admin);
        staking.setAutomigrationCap(100);
        vm.prank(admin);
        staking.setMinTokenDepositForAutomigration(USDC, 500e6); // 500 USDC minimum

        // Request automigration
        vm.startPrank(user1);
        USDC.approve(address(staking), 1000e6);
        staking.deposit(1000e6, USDC);
        staking.requestAutomigration();

        // Withdraw enough to fall below minimum (600e6)
        // This should leave 400e6 which is below the 500e6 minimum
        staking.withdraw(600e6, USDC);
        vm.stopPrank();

        // Check automigration was cancelled
        assertFalse(staking.hasRequestedAutomigration(user1));
        assertEq(staking.getRemainingAutomigrationSlots(), 100);
    }

    function testBatchDepositToVaultWithAutomigration() public {
        // Setup
        vm.prank(admin);
        staking.setAutomigrationCap(100);
        vm.prank(admin);
        staking.setMinTokenDepositForAutomigration(USDC, 500e6); // 500 USDC minimum

        // Setup users
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        // Setup tokens
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = USDC;
        tokens[1] = USDC;

        // Set conversion start time to now
        vm.prank(admin);
        staking.setVaultConversionStartTime(block.timestamp);

        // Setup deposits and automigration requests
        for (uint256 i = 0; i < users.length; i++) {
            deal(address(USDC), users[i], 1000e6); // Give users USDC
            vm.startPrank(users[i]);
            USDC.approve(address(staking), 1000e6);
            staking.deposit(1000e6, USDC);
            staking.requestAutomigration();
            vm.stopPrank();
        }

        // Execute batch deposit
        vm.startPrank(address(timelock));
        uint256[] memory shares = staking.batchDepositToVault(users, tokens, 9900);
        vm.stopPrank();

        // Verify results
        for (uint256 i = 0; i < users.length; i++) {
            assertEq(shares[i], 1000e6, "Should receive correct shares");
            assertTrue(staking.hasRequestedAutomigration(users[i]), "Automigration request should remain active");
            assertEq(staking.getUserVaultShares(users[i], tokens[i]), 1000e6, "Should receive correct vault tokens");
        }

        // Verify automigration cap remains unchanged
        assertEq(staking.getRemainingAutomigrationSlots(), 98, "Automigration slots should remain unchanged");
    }

}
