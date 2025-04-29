// test/RaffleMigrationTest.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../src/spin/Raffle.sol";
import "../src/interfaces/ISupraRouterContract.sol";
import "forge-std/Test.sol";

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

/// @notice Stub VRF for SupraRouter
contract StubSupra is ISupraRouterContract {
    event RequestSent(uint256 indexed nonce);
    uint256 private next = 1;
    
    function generateRequest(
        string memory _functionSig,
        uint8 _rngCount,
        uint256 _numConfirmations,
        uint256 _clientSeed,
        address _clientWalletAddress
    ) external override returns (uint256) {
        uint256 n = next++;
        emit RequestSent(n);
        return n;
    }
    
    function generateRequest(
        string memory _functionSig,
        uint8 _rngCount,
        uint256 _numConfirmations,
        address _clientWalletAddress
    ) external override returns (uint256) {
        uint256 n = next++;
        emit RequestSent(n);
        return n;
    }
    
    function rngCallback(
        uint256 nonce,
        uint256[] memory rngList,
        address _clientContractAddress,
        string memory _functionSig
    ) external override returns (bool, bytes memory) {
        return (true, "");
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
    StubSupra public supra;
    
    address constant ADMIN = address(0x1);
    address constant USER1 = address(0x2);
    address constant USER2 = address(0x3);
    address constant USER3 = address(0x4);
    
    function setUp() public {
        supra = new StubSupra();
        spinStub = new SpinStub();
        raffle = new Raffle();
        
        vm.prank(ADMIN);
        raffle.initialize(address(spinStub), address(supra));
        
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
        vm.prank(ADMIN);
        raffle.requestWinner(1);
        
        uint256 requestId = 1;
        uint256[] memory rng = new uint256[](1);
        
        // Test USER1 winning (ticket in range 1-5)
        rng[0] = 3; // Will result in ticket #4
        vm.prank(address(supra));
        raffle.handleWinnerSelection(requestId, rng);
        assertEq(raffle.getWinner(1), USER1);
        
        // Test another prize with USER2 winning (ticket in range 6-8)
        vm.prank(ADMIN);
        raffle.addPrize("Second Migration Test", "Another test", 50);
        
        vm.prank(ADMIN);
        raffle.migrateTickets(2, users, tickets);
        
        vm.prank(ADMIN);
        raffle.requestWinner(2);
        
        requestId = 2;
        rng[0] = 6; // Will result in ticket #7
        vm.prank(address(supra));
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