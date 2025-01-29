// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "../src/nYIELDStaking.sol";

import "../src/proxy/PlumenYieldStaking.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";

import { IAccountantWithRateProviders } from "../src/interfaces/IAccountantWithRateProviders.sol";
import { IAtomicQueue } from "../src/interfaces/IAtomicQueue.sol";
import { IBoringVault } from "../src/interfaces/IBoringVault.sol";
import { ILens } from "../src/interfaces/ILens.sol";
import { ITeller } from "../src/interfaces/ITeller.sol";

contract nYieldStakingTest is Test {

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
        PlumenYieldStaking proxy = new PlumenYieldStaking(address(implementation), initData);

        // Cast proxy to nYieldStaking for easier interaction
        staking = nYieldStaking(address(proxy));

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

    function test_StorageSlot() public {
        // Calculate the storage slot
        bytes32 slot =
            keccak256(abi.encode(uint256(keccak256("plume.storage.nYieldStaking")) - 1)) & ~bytes32(uint256(0xff));

        // Log the results for verification
        console.logBytes32(keccak256("plume.storage.nYieldStaking"));
        console.log("Minus 1:");
        console.logBytes32(bytes32(uint256(keccak256("plume.storage.nYieldStaking")) - 1));
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
        address teller = address(0x123); // Replace with actual teller address

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
        address teller = address(0x123); // Replace with actual teller address
        staking.convertToBoringVault(USDC, ITeller(teller), 50 * 1e6);
        vm.stopPrank();
    }

    function testBatchTransferShares() public {
        address teller = address(0x123); // Replace with actual teller address

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

}
