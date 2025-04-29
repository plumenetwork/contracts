// test/RaffleMigrationTest.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../src/spin/Raffle.sol";
import "../src/interfaces/ISupraRouterContract.sol";
import "../src/helpers/ArbSys.sol";
import "forge-std/Test.sol";

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

/// @notice Mock for Arbitrum's ArbSys precompile
contract ArbSysMock is ArbSys {
    uint256 blockNumber;
    
    constructor() {
        blockNumber = 100;
    }
    
    function arbBlockNumber() external view returns (uint256) {
        return blockNumber;
    }
    
    function arbBlockHash(uint256 arbBlockNum) external view returns (bytes32) {
        return blockhash(arbBlockNum);
    }
}

/// @notice Minimal stub implementing ISpin for ticket balances
contract SpinStub is ISpin {
    mapping(address => uint256) public balances;
    
    function setBalance(address user, uint256 amount) external {
        balances[user] = amount;
    }
    
    function updateRaffleTickets(address user, uint256 amount) external override {
        require(balances[user] >= amount, "stub underflow");
        balances[user] -= amount;
    }
    
    function getUserData(address user) external view override returns (
        uint256, uint256, uint256, uint256, uint256, uint256, uint256
    ) {
        return (0,0,0,0, balances[user], 0, 0);
    }
}

contract RaffleMigrationTests is Test {
    Raffle public raffle;
    SpinStub public spinStub;
    ArbSysMock public arbSys;
    
    address constant ADMIN = address(0x1);
    address constant USER1 = address(0x2);
    address constant USER2 = address(0x3);
    address constant USER3 = address(0x4);
    address constant SUPRA_ORACLE = address(0x6D46C098996AD584c9C40D6b4771680f54cE3726);
    address constant DEPOSIT_CONTRACT = address(0x3B5F96986389f6BaCF58d5b69425fab000D3551e);
    address constant SUPRA_OWNER = address(0x578DD059Ec425F83cCCC3149ed594d4e067A5307);
    address constant ARB_SYS_ADDRESS = address(100); // 0x0000000000000000000000000000000000000064
    
    function setUp() public {
        // Fork from test RPC
        vm.createSelectFork(vm.envString("PLUME_TEST_RPC_URL"));
        
        // Setup ArbSys mock at the special address
        arbSys = new ArbSysMock();
        vm.etch(ARB_SYS_ADDRESS, address(arbSys).code);
        
        spinStub = new SpinStub();
        raffle = new Raffle();
        
        // Add admin to whitelist
        vm.prank(SUPRA_OWNER);
        IDepositContract(DEPOSIT_CONTRACT).addClientToWhitelist(ADMIN, true);
        
        // Verify admin is whitelisted
        bool isWhitelisted = IDepositContract(DEPOSIT_CONTRACT).isClientWhitelisted(ADMIN);
        assertTrue(isWhitelisted, "Admin is not whitelisted");
        
        // Fund admin account for deposit
        vm.deal(ADMIN, 200 ether);
        
        // Deposit funds
        vm.prank(ADMIN);
        IDepositContract(DEPOSIT_CONTRACT).depositFundClient{ value: 0.1 ether }();
        
        // Add raffle contract to whitelist
        vm.prank(ADMIN);
        IDepositContract(DEPOSIT_CONTRACT).addContractToWhitelist(address(raffle));
        
        // Verify raffle contract is whitelisted
        vm.prank(SUPRA_OWNER);
        bool isContractWhitelisted = IDepositContract(DEPOSIT_CONTRACT).isContractWhitelisted(ADMIN, address(raffle));
        assertTrue(isContractWhitelisted, "Raffle contract is not whitelisted under ADMIN");
        
        // Set minimum balance
        vm.prank(ADMIN);
        IDepositContract(DEPOSIT_CONTRACT).setMinBalanceClient(0.05 ether);
        
        // Verify balance is sufficient
        vm.prank(SUPRA_OWNER);
        uint256 effectiveBalance = IDepositContract(DEPOSIT_CONTRACT).checkEffectiveBalance(ADMIN);
        assertGt(effectiveBalance, 0, "Insufficient balance in Supra Deposit Contract");
        
        // Verify contract is eligible
        vm.prank(SUPRA_OWNER);
        bool contractEligible = IDepositContract(DEPOSIT_CONTRACT).isContractEligible(ADMIN, address(raffle));
        assertTrue(contractEligible, "Raffle contract is not eligible for VRF");
        
        vm.prank(ADMIN);
        raffle.initialize(address(spinStub), SUPRA_ORACLE);
        
        // Create test prize
        vm.prank(ADMIN);
        raffle.addPrize("Migration Test", "A prize for migration testing", 100);
    }
    
    function testMigrateTickets() public {
        // Create arrays for migration
        address[] memory users = new address[](3);
        users[0] = USER1;
        users[1] = USER2;
        users[2] = USER3;
        
        uint256[] memory tickets = new uint256[](3);
        tickets[0] = 5;  // USER1: 5 tickets
        tickets[1] = 3;  // USER2: 3 tickets
        tickets[2] = 2;  // USER3: 2 tickets
        
        // Migrate tickets
        vm.prank(ADMIN);
        raffle.migrateTickets(1, users, tickets);
        
        // Verify total tickets
        assertEq(raffle.totalTickets(1), 10);
        
        // Verify unique users count
        uint256 uniqueUsers;
        (,,,,,,uniqueUsers) = raffle.getPrizeDetails(1);
        assertEq(uniqueUsers, 3);
        
        // Test getWinner to verify ranges are properly set
        vm.recordLogs();
        vm.prank(ADMIN);
        raffle.requestWinner(1);
        
        // Extract the request ID from logs
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 requestId = 0;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("WinnerRequested(uint256,uint256)")) {
                requestId = uint256(logs[i].topics[2]);
                break;
            }
        }
        require(requestId != 0, "Request ID not found in logs");
        
        uint256[] memory rng = new uint256[](1);
        
        // Test USER1 winning (ticket in range 1-5)
        rng[0] = 3; // Will result in ticket #4
        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(requestId, rng);
        assertEq(raffle.getWinner(1), USER1);
        
        // Test another prize with USER2 winning (ticket in range 6-8)
        vm.prank(ADMIN);
        raffle.addPrize("Second Migration Test", "Another test", 50);
        
        vm.prank(ADMIN);
        raffle.migrateTickets(2, users, tickets);
        
        vm.recordLogs();
        vm.prank(ADMIN);
        raffle.requestWinner(2);
        
        // Extract the request ID from logs for second prize
        logs = vm.getRecordedLogs();
        requestId = 0;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("WinnerRequested(uint256,uint256)")) {
                requestId = uint256(logs[i].topics[2]);
                break;
            }
        }
        require(requestId != 0, "Request ID not found in logs");
        
        rng[0] = 6; // Will result in ticket #7
        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(requestId, rng);
        assertEq(raffle.getWinner(2), USER2);
    }
    
    function testMigrateTicketsWithZeroValues() public {
        // Create arrays with some zero values
        address[] memory users = new address[](4);
        users[0] = USER1;
        users[1] = USER2;
        users[2] = address(0); // Zero address
        users[3] = USER3;
        
        uint256[] memory tickets = new uint256[](4);
        tickets[0] = 5;  // USER1: 5 tickets
        tickets[1] = 0;  // USER2: 0 tickets (should be skipped)
        tickets[2] = 3;  // Zero address: 3 tickets
        tickets[3] = 2;  // USER3: 2 tickets
        
        // Migrate tickets
        vm.prank(ADMIN);
        raffle.migrateTickets(1, users, tickets);
        
        // Verify total tickets (USER2 should be skipped)
        assertEq(raffle.totalTickets(1), 10);
        
        // Verify unique users (USER2 should not be counted)
        uint256 uniqueUsers;
        (,,,,,,uniqueUsers) = raffle.getPrizeDetails(1);
        assertEq(uniqueUsers, 3);
    }
    
    function testMigrateTicketsAlreadyHasTicketsReverts() public {
        // First migration
        address[] memory users = new address[](1);
        users[0] = USER1;
        uint256[] memory tickets = new uint256[](1);
        tickets[0] = 1;
        
        vm.prank(ADMIN);
        raffle.migrateTickets(1, users, tickets);
        
        // Second migration should revert
        vm.prank(ADMIN);
        vm.expectRevert("Already has tickets");
        raffle.migrateTickets(1, users, tickets);
    }
    
    function testMigrateTicketsArrayLengthMismatchReverts() public {
        address[] memory users = new address[](2);
        users[0] = USER1;
        users[1] = USER2;
        
        uint256[] memory tickets = new uint256[](3); // Different length
        tickets[0] = 1;
        tickets[1] = 2;
        tickets[2] = 3;
        
        vm.prank(ADMIN);
        vm.expectRevert("Array length mismatch");
        raffle.migrateTickets(1, users, tickets);
    }
    
    function testMigrateTicketsInactivePrizeReverts() public {
        // Remove prize
        vm.prank(ADMIN);
        raffle.removePrize(1);
        
        address[] memory users = new address[](1);
        users[0] = USER1;
        uint256[] memory tickets = new uint256[](1);
        tickets[0] = 1;
        
        vm.prank(ADMIN);
        vm.expectRevert("Prize not available");
        raffle.migrateTickets(1, users, tickets);
    }
    
    function testMigrateTicketsOnlyAdmin() public {
        address[] memory users = new address[](1);
        users[0] = USER1;
        uint256[] memory tickets = new uint256[](1);
        tickets[0] = 1;
        
        vm.prank(USER1); // Not admin
        
        // Just check that it reverts without specifying the exact error
        vm.expectRevert();
        raffle.migrateTickets(1, users, tickets);
    }
}

interface IDepositContract {
    function addContractToWhitelist(
        address contractAddress
    ) external;
    function addClientToWhitelist(address clientAddress, bool snap) external;
    function depositFundClient() external payable;
    function isClientWhitelisted(
        address clientAddress
    ) external view returns (bool);
    function isContractWhitelisted(address client, address contractAddress) external view returns (bool);
    function checkEffectiveBalance(
        address clientAddress
    ) external view returns (uint256);
    function isContractEligible(address client, address contractAddress) external view returns (bool);
    function setMinBalanceClient(
        uint256 minBalance
    ) external;
}