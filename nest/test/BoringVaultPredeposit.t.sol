// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { BoringVaultPredeposit } from "../src/BoringVaultPredeposit.sol";
import "../src/proxy/BoringVaultPredepositProxy.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";

import { IBoringVault } from "../src/interfaces/IBoringVault.sol";
import { BridgeData, ITeller } from "../src/interfaces/ITeller.sol";

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

    function setUp() public {
        // Fork mainnet (Speciying a block number allows us to cache the state at that block)
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), 21_769_985);

        // Setup accounts
        admin = address(this);
        user1 = address(0x1);
        user2 = address(0x2);

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
        staking.stake(depositAmount, USDC);

        // Try to deposit before start time
        vm.expectRevert(
            abi.encodeWithSelector(
                BoringVaultPredeposit.ConversionNotStarted.selector,
                block.timestamp,
                staking.getVaultConversionStartTime()
            )
        );
        staking.depositToVault(IERC20(address(USDC)), depositAmount);
        vm.stopPrank();
    }

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
        staking.stake(depositAmount, USDC);

        // Need to approve both teller and vault to spend USDC
        USDC.approve(nYieldTeller, depositAmount);
        USDC.approve(address(nYIELD), depositAmount);

        // Then deposit to vault
        uint256 minimumMint = depositAmount * 99 / 100; // 1% slippage
        uint256 shares = staking.depositToVault(IERC20(address(USDC)), minimumMint);

        // Verify results
        assertEq(shares, depositAmount, "Should receive same amount of shares");
        assertEq(nYIELD.balanceOf(user1), depositAmount, "Should receive nYIELD tokens");
        assertEq(USDC.balanceOf(address(staking)), 0, "Should have no USDC left");

        vm.stopPrank();
    }

    function testBatchDepositToVault_RevertBeforeStart() public {
        // Setup
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;

        IERC20[] memory depositAssets = new IERC20[](2);
        depositAssets[0] = IERC20(address(USDC));
        depositAssets[1] = IERC20(address(USDC));

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000 * 1e6;
        amounts[1] = 2000 * 1e6;

        // Fund users and have them stake
        deal(address(USDC), user1, amounts[0]);
        deal(address(USDC), user2, amounts[1]);

        vm.startPrank(user1);
        USDC.approve(address(staking), amounts[0]);
        staking.stake(amounts[0], USDC);
        vm.stopPrank();

        vm.startPrank(user2);
        USDC.approve(address(staking), amounts[1]);
        staking.stake(amounts[1], USDC);
        vm.stopPrank();

        // Try to batch deposit before start time
        vm.startPrank(address(timelock));
        vm.expectRevert(
            abi.encodeWithSelector(
                BoringVaultPredeposit.ConversionNotStarted.selector,
                block.timestamp,
                staking.getVaultConversionStartTime()
            )
        );
        staking.batchDepositToVault(recipients, depositAssets, amounts, 1);
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
        staking.stake(amounts[0], USDC);
        vm.stopPrank();

        vm.startPrank(user2);
        USDC.approve(address(staking), amounts[1]);
        staking.stake(amounts[1], USDC);
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
        uint256[] memory receivedShares = staking.batchDepositToVault(recipients, depositAssets, amounts, minimumMint);
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
        staking.batchDepositToVault(recipients, depositAssets, amounts, minimumMintBps);
    }

    function testFailDepositToVault_NoBalance() public {
        uint256 minimumMint = 0;
        vm.prank(user1);
        staking.depositToVault(IERC20(address(USDC)), minimumMint);
    }

    function testStaking() public {
        vm.startPrank(user1);
        USDC.approve(address(staking), 100 * 1e6);
        staking.stake(100 * 1e6, USDC);
        vm.stopPrank();

        // getUserTokenAmounts returns amount in 18 decimals (1e18)
        // so 100 USDC (100 * 1e6) becomes (100 * 1e18)
        uint256 expectedAmount = 100 * 1e6 * 1e12; // Convert 6 decimals to 18 decimals
        assertEq(staking.getUserTokenAmounts(user1, USDC), expectedAmount);
    }

    function testFailStakingUnallowedToken() public {
        // Create a random token address that's not allowed
        address randomToken = address(0x123);
        vm.prank(user1);
        staking.stake(100 * 1e6, IERC20(randomToken));
    }

    function testSetVaultConversionStartTime() public {
        uint256 newStartTime = block.timestamp + 7 days;
        vm.prank(admin);
        staking.setVaultConversionStartTime(newStartTime);
        assertEq(staking.getVaultConversionStartTime(), newStartTime);
    }

    function testFailNonAdminSetStartTime() public {
        vm.prank(user1);
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
        staking.stake(100 * 1e6, USDC);
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
        assertEq(staking.getTotalAmountStaked(USDC), 0);

        address[] memory users = staking.getUsers();
        assertEq(users.length, 0);

        // Get user state with new return types
        (IERC20[] memory tokens, BoringVaultPredeposit.UserTokenState[] memory states, uint256 lastUpdate) =
            staking.getUserState(user1);

        // Check general state
        assertEq(lastUpdate, 0);

        // Check USDC state specifically
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == USDC) {
                assertEq(states[i].amountSeconds, 0);
                assertEq(states[i].tokenAmount, 0);
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

    function testFailPauseWhenPaused() public {
        vm.startPrank(admin);
        staking.pause();
        staking.pause(); // Should fail
        vm.stopPrank();
    }

    function testFailUnpauseWhenNotPaused() public {
        vm.prank(admin);
        staking.unpause(); // Should fail as contract is not paused
    }

    function testWithdraw() public {
        // Setup
        vm.startPrank(user1);
        USDC.approve(address(staking), 100 * 1e6);
        staking.stake(100 * 1e6, USDC);
        vm.stopPrank();

        uint256 initialBalance = USDC.balanceOf(user1);

        // Withdraw
        vm.prank(user1);
        staking.withdraw(50 * 1e6, USDC);

        // Assertions
        assertEq(USDC.balanceOf(user1), initialBalance + 50 * 1e6);
        assertEq(staking.getUserTokenAmounts(user1, USDC), 50 * 1e18); // Amount in bae unit decimals (e18)
        assertEq(staking.getTotalAmountStaked(USDC), 50 * 1e18); // Amount in bae unit decimals (e18)
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
        staking.stake(1 ether, token18);
        vm.stopPrank();

        // Should be equal since decimals == _BASE
        assertEq(staking.getUserTokenAmounts(user1, token18), 1 ether); // Fixed function name

        // Test withdraw to verify _fromBaseUnits
        vm.prank(user1);
        staking.withdraw(0.5 ether, token18);

        assertEq(token18.balanceOf(user1), 0.5 ether);
        assertEq(staking.getUserTokenAmounts(user1, token18), 0.5 ether); // Fixed function name
    }
    /*
    function testFailWithdrawAfterEnd() public {
        // Setup
        vm.startPrank(user1);
        USDC.approve(address(staking), 100 * 1e6);
        staking.stake(100 * 1e6, USDC);
        vm.stopPrank();

        // End staking
        vm.prank(address(staking.getTimelock()));
        staking.adminWithdraw();

        // Try to withdraw after end
        vm.prank(user1);
        staking.withdraw(50 * 1e6, USDC); // Should revert
    }
    */

    function testFailWithdrawInsufficientBalance() public {
        // Setup
        vm.startPrank(user1);
        USDC.approve(address(staking), 100 * 1e6);
        staking.stake(100 * 1e6, USDC);
        vm.stopPrank();

        // Try to withdraw more than staked
        vm.prank(user1);
        staking.withdraw(150 * 1e6, USDC); // Should revert with InsufficientStaked
    }

    function testFailAllowAlreadyAllowedStablecoin() public {
        // USDC is already allowed in setUp()
        vm.prank(admin);
        staking.allowToken(USDC); // Should revert with AlreadyAllowedStablecoin
    }

}
