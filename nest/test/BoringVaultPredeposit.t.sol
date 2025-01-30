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

    function testConvertToBoringVault() public {
        // Setup
        vm.startPrank(user1);
        USDC.approve(address(staking), 100 * 1e6);
        staking.stake(100 * 1e6, USDC);
        vm.stopPrank();

        // Advance time past conversion start
        vm.warp(block.timestamp + 2 days);

        // Get teller address from deployment
        address teller = nYieldTeller; // Replace with actual teller address

        // Convert to vault
        vm.startPrank(user1);
        USDC.approve(address(teller), 50 * 1e6);
        staking.convertToBoringVault(USDC, ITeller(teller), 50 * 1e6);
        vm.stopPrank();

        // Check balances
        assertEq(staking.getUserStablecoinAmounts(user1, USDC), 50 * 1e6);
        assertEq(staking.getUserVaultShares(user1, USDC), 50 * 1e6);
    }

    function testFailConvertBeforeStartTime() public {
        vm.startPrank(user1);
        USDC.approve(address(staking), 100 * 1e6);
        staking.stake(100 * 1e6, USDC);

        // Try to convert before start time
        address teller = nYieldTeller; // Replace with actual teller address
        staking.convertToBoringVault(USDC, ITeller(teller), 50 * 1e6);
        vm.stopPrank();
    }

    function testBatchTransferShares() public {
        address teller = nYieldTeller; // Replace with actual teller address

        // Setup users with shares
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        // Stake and convert for both users
        for (uint256 i = 0; i < users.length; i++) {
            vm.startPrank(users[i]);
            USDC.approve(address(staking), 100 * 1e6);
            staking.stake(100 * 1e6, USDC);
            vm.stopPrank();
        }

        // Advance time and convert
        vm.warp(block.timestamp + 2 days);
        for (uint256 i = 0; i < users.length; i++) {
            vm.startPrank(users[i]);
            staking.convertToBoringVault(USDC, ITeller(teller), 50 * 1e6);
            vm.stopPrank();
        }

        // Batch transfer shares
        vm.prank(admin);
        staking.batchTransferVaultShares(USDC, users);

        // Verify shares were transferred
        for (uint256 i = 0; i < users.length; i++) {
            assertEq(staking.getUserVaultShares(users[i], USDC), 0);
            assertEq(nYIELD.balanceOf(users[i]), 50 * 1e6);
        }
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

    function testAdminBridge() public {
        // Setup initial state
        vm.startPrank(user1);
        USDC.approve(address(staking), 100 * 1e6);
        staking.stake(100 * 1e6, USDC);
        vm.stopPrank();

        // Get teller address from deployment
        address teller = nYieldTeller;

        // Deal some ETH to the timelock for bridge fees
        vm.deal(address(staking.getTimelock()), 1 ether);

        // Approve both teller and vault to spend USDC
        vm.startPrank(address(staking));
        USDC.approve(teller, 100 * 1e6);
        USDC.approve(address(0x892DFf5257B39f7afB7803dd7C81E8ECDB6af3E8), 100 * 1e6); // Approve vault
        vm.stopPrank();

        BridgeData memory bridgeData = BridgeData({
            chainSelector: 30_318, // Actual chain selector
            destinationChainReceiver: address(0x04354e44ed31022716e77eC6320C04Eda153010c), // Actual receiver
            bridgeFeeToken: IERC20(NATIVE), // Using native ETH for fees
            messageGas: 100_000, // Actual gas limit
            data: "" // Additional data
         });

        vm.prank(address(staking.getTimelock()));
        // Increase ETH value to cover the bridge fee
        staking.adminBridge{ value: 0.1 ether }(ITeller(teller), bridgeData);

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

        assertEq(staking.getVaultTotalShares(USDC), 0);
    }

    function testFailAdminWithdrawAfterEnd() public {
        vm.prank(address(staking.getTimelock()));
        staking.adminWithdraw();

        vm.prank(address(staking.getTimelock()));
        staking.adminWithdraw(); // Should fail as staking has ended
    }

    function testFailAdminBridgeAfterEnd() public {
        vm.prank(address(staking.getTimelock()));
        staking.adminWithdraw();

        BridgeData memory bridgeData = BridgeData({
            chainSelector: 1,
            destinationChainReceiver: address(0x123),
            bridgeFeeToken: USDC,
            messageGas: 200_000,
            data: ""
        });

        vm.prank(address(staking.getTimelock()));
        staking.adminBridge(ITeller(nYieldTeller), bridgeData); // Should fail as staking has ended
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
    /*
    function testBatchTransferShares() public {
    // Setup
    vm.startPrank(user1);
    USDC.approve(address(staking), 100 * 1e6);
    staking.stake(100 * 1e6, USDC);
    
    USDT.approve(address(staking), 50 * 1e6);
    staking.stake(50 * 1e6, USDT);
    vm.stopPrank();

    // Convert to vault shares
    vm.startPrank(user1);
    staking.convertToBoringVault(USDC, ITeller(nYieldTeller), 60 * 1e6);
    staking.convertToBoringVault(USDT, ITeller(nYieldTeller), 30 * 1e6);
    vm.stopPrank();

    IERC20[] memory stablecoins = new IERC20[](2);
    stablecoins[0] = USDC;
    stablecoins[1] = USDT;

    address[] memory recipients = new address[](2);
    recipients[0] = user2;
    recipients[1] = user2;

    uint256[] memory amounts = new uint256[](2);
    amounts[0] = 30 * 1e6;
    amounts[1] = 15 * 1e6;

    // Transfer shares
    vm.prank(user1);
    staking.batchTransferShares(stablecoins, recipients, amounts);

    // Assertions
    assertEq(staking.getUserVaultShares(user1, USDC), 30 * 1e6);
    assertEq(staking.getUserVaultShares(user2, USDC), 30 * 1e6);
    assertEq(staking.getUserVaultShares(user1, USDT), 15 * 1e6);
    assertEq(staking.getUserVaultShares(user2, USDT), 15 * 1e6);
    }
    */

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

    function testFailBatchTransferSharesWithMismatchedArrays() public {
        IERC20[] memory stablecoins = new IERC20[](2);
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](2);

        vm.prank(user1);
        staking.batchTransferShares(stablecoins, recipients, amounts); // Should revert
    }

    function testFailBatchTransferSharesWithInvalidRecipient() public {
        IERC20[] memory stablecoins = new IERC20[](1);
        stablecoins[0] = USDC;

        address[] memory recipients = new address[](1);
        recipients[0] = address(0);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e6;

        vm.prank(user1);
        staking.batchTransferShares(stablecoins, recipients, amounts); // Should revert
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

    function testFailBatchTransferSharesInsufficientBalance() public {
        // Setup
        vm.startPrank(user1);
        USDC.approve(address(staking), 100 * 1e6);
        staking.stake(100 * 1e6, USDC);

        // Convert to vault shares
        vm.warp(block.timestamp + 2 days);
        staking.convertToBoringVault(USDC, ITeller(nYieldTeller), 60 * 1e6);
        vm.stopPrank();

        IERC20[] memory stablecoins = new IERC20[](1);
        stablecoins[0] = USDC;

        address[] memory recipients = new address[](1);
        recipients[0] = user2;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 * 1e6; // Try to transfer more than converted

        // Should revert with insufficient balance
        vm.prank(user1);
        staking.batchTransferShares(stablecoins, recipients, amounts);
    }

}
