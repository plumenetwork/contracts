// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "../src/BoringVaultPredeposit.sol";

import "../src/proxy/BoringVaultPredepositProxy.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";

import { IAccountantWithRateProviders } from "../src/interfaces/IAccountantWithRateProviders.sol";
import { IAtomicQueue } from "../src/interfaces/IAtomicQueue.sol";
import { IBoringVault } from "../src/interfaces/IBoringVault.sol";
import { ILens } from "../src/interfaces/ILens.sol";
import { BridgeData, ITeller } from "../src/interfaces/ITeller.sol";

contract BoringVaultPredepositTest is Test {

    nYieldStaking public implementation;
    nYieldStaking public staking;
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

    function setUp() public {
        // Fork mainnet
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

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
        nYieldStaking.BoringVault memory boringVaultConfig = nYieldStaking.BoringVault({
            teller: ITeller(0x92A735f600175FE9bA350a915572a86F68EBBE66),
            vault: IBoringVault(0x892DFf5257B39f7afB7803dd7C81E8ECDB6af3E8),
            atomicQueue: IAtomicQueue(0xc7287780bfa0C5D2dD74e3e51E238B1cd9B221ee),
            lens: ILens(0xE3F5867742443Bb34E20D8cFbF755dc70806eA05),
            accountant: IAccountantWithRateProviders(0x5da1A1d004Fe6b63b37228F08dB6CaEb418A6467)
        });

        // Deploy implementation
        implementation = new nYieldStaking();

        // Encode initialize function call
        bytes memory initData =
            abi.encodeWithSelector(nYieldStaking.initialize.selector, timelock, admin, boringVaultConfig);

        // Deploy proxy
        BoringVaultPredepositProxy proxy = new BoringVaultPredepositProxy(address(implementation), initData);

        // Cast proxy to nYieldStaking for easier interaction
        staking = nYieldStaking(payable(address(proxy)));

        // Setup initial state
        vm.startPrank(admin);
        staking.allowStablecoin(USDC);
        staking.allowStablecoin(USDT);
        staking.allowStablecoin(USDe);
        staking.allowStablecoin(sUSDe);
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

    function testDepositToVault() public {
        // Setup
        uint256 depositAmount = 1000e6; // 1000 USDC
        deal(address(USDC), user1, depositAmount);

        vm.startPrank(user1);

        // First stake USDC
        USDC.approve(address(staking), depositAmount);
        staking.stake(depositAmount, USDC);

        // Need to approve both teller and vault to spend USDC
        USDC.approve(nYieldTeller, depositAmount);
        USDC.approve(address(nYIELD), depositAmount); // nYIELD is the vault token

        // Then deposit to vault
        uint256 userInitialBalance = nYIELD.balanceOf(user1);
        uint256 shares = staking.depositToVault(ERC20(address(USDC)));

        // Verify results
        assertEq(shares, depositAmount, "Should receive same amount of shares");
        assertEq(nYIELD.balanceOf(user1), userInitialBalance + depositAmount, "Should receive nYIELD tokens");
        assertEq(USDC.balanceOf(address(staking)), 0, "Should have no USDC left");

        // Verify user state updated
        (, uint256 amountStaked,) = staking.getUserState(user1);
        assertEq(amountStaked, 0, "Should have no stake left");

        vm.stopPrank();
    }

    function testBatchDepositToVault() public {
        // Setup
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;

        ERC20[] memory depositAssets = new ERC20[](2);
        depositAssets[0] = ERC20(address(USDC));
        depositAssets[1] = ERC20(address(USDC));

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000e6; // 1000 USDC
        amounts[1] = 2000e6; // 2000 USDC

        // Fund contract with USDC
        deal(address(USDC), address(staking), 3000e6); // Total needed: 3000 USDC

        // Record initial balances
        uint256 user1InitialBalance = nYIELD.balanceOf(user1);
        uint256 user2InitialBalance = nYIELD.balanceOf(user2);

        // Execute batch deposit as admin
        vm.prank(admin);
        uint256[] memory receivedShares = staking.batchDepositToVault(recipients, depositAssets, amounts);

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
        ERC20[] memory depositAssets = new ERC20[](1);
        uint256[] memory amounts = new uint256[](1);

        vm.prank(user1);
        vm.expectRevert();
        staking.batchDepositToVault(recipients, depositAssets, amounts);
    }

    function testFailDepositToVault_NoBalance() public {
        vm.prank(user1);
        staking.depositToVault(ERC20(address(USDC)));
    }

    function testStaking() public {
        vm.startPrank(user1);
        USDC.approve(address(staking), 100 * 1e6);
        staking.stake(100 * 1e6, USDC);
        vm.stopPrank();

        assertEq(staking.getUserStablecoinAmounts(user1, USDC), 100 * 1e6);
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

        vm.prank(address(staking.getTimelock()));
        staking.setMultisig(newMultisig);

        assertEq(staking.getMultisig(), newMultisig);
    }

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
        assertEq(staking.getTotalAmountStaked(), 0);

        address[] memory users = staking.getUsers();
        assertEq(users.length, 0);

        (uint256 amountSeconds, uint256 amountStaked, uint256 lastUpdate) = staking.getUserState(user1);
        assertEq(amountSeconds, 0);
        assertEq(amountStaked, 0);
        assertEq(lastUpdate, 0);

        IERC20[] memory stablecoins = staking.getAllowedStablecoins();
        assertTrue(stablecoins.length > 0);

        assertTrue(staking.isAllowedStablecoin(USDC));

        assertEq(staking.getEndTime(), 0);

        assertFalse(staking.isPaused());
    }

    function testFailAdminWithdrawAfterEnd() public {
        vm.prank(address(staking.getTimelock()));
        staking.adminWithdraw();

        vm.prank(address(staking.getTimelock()));
        staking.adminWithdraw(); // Should fail as staking has ended
    }

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
        assertEq(staking.getUserStablecoinAmounts(user1, USDC), 50 * 1e6); // Amount in USDC decimals (6)
        assertEq(staking.getTotalAmountStaked(), 50 * 1e6 * 1e12); // This one stays in base units (18 decimals)
    }

    function testBaseUnitConversions() public {
        // Use DAI which has 18 decimals (same as _BASE)
        IERC20 token18 = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F); // DAI address

        vm.startPrank(admin);
        staking.allowStablecoin(token18);
        vm.stopPrank();

        // Deal some DAI to user1
        deal(address(token18), user1, 1 ether);

        // Test _toBaseUnits with 18 decimals
        vm.startPrank(user1);
        token18.approve(address(staking), 1 ether);
        staking.stake(1 ether, token18);
        vm.stopPrank();

        // Should be equal since decimals == _BASE
        assertEq(staking.getUserStablecoinAmounts(user1, token18), 1 ether); // Fixed function name

        // Test withdraw to verify _fromBaseUnits
        vm.prank(user1);
        staking.withdraw(0.5 ether, token18);

        assertEq(token18.balanceOf(user1), 0.5 ether);
        assertEq(staking.getUserStablecoinAmounts(user1, token18), 0.5 ether); // Fixed function name
    }

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
        staking.allowStablecoin(USDC); // Should revert with AlreadyAllowedStablecoin
    }

}
