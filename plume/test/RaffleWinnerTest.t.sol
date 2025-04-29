// test/RaffleWinnerTest.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../src/spin/Raffle.sol";
import "../src/interfaces/ISupraRouterContract.sol";
import "forge-std/Test.sol";

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
        // No implementation needed for stub
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

contract RaffleWinnerTests is Test {
    Raffle public raffle;
    SpinStub public spinStub;
    StubSupra public supra;
    
    address constant ADMIN = address(0x1);
    address constant USER1 = address(0x2);
    address constant USER2 = address(0x3);
    
    function setUp() public {
        supra = new StubSupra();
        spinStub = new SpinStub();
        raffle = new Raffle();
        
        vm.prank(ADMIN);
        raffle.initialize(address(spinStub), address(supra));
        
        // Setup test prize
        vm.prank(ADMIN);
        raffle.addPrize("Test Prize", "A test prize", 100);
        
        // Add tickets for different users
        spinStub.setBalance(USER1, 5);
        vm.prank(USER1);
        raffle.spendRaffle(1, 3); // USER1: tickets 1-3
        
        spinStub.setBalance(USER2, 5);
        vm.prank(USER2);
        raffle.spendRaffle(1, 2); // USER2: tickets 4-5
    }
    
    function testGetWinner() public {
        // Draw winner with ticket #2 (USER1)
        vm.prank(ADMIN);
        raffle.requestWinner(1);
        
        uint256 requestId = 1; // From stub
        uint256[] memory rng = new uint256[](1);
        rng[0] = 1; // Will result in ticket #2
        
        vm.prank(address(supra));
        raffle.handleWinnerSelection(requestId, rng);
        
        // Verify winner is USER1
        address winner = raffle.getWinner(1);
        assertEq(winner, USER1);
        
        // Test with ticket #4 (USER2)
        vm.prank(ADMIN);
        raffle.addPrize("Second Prize", "Another prize", 100);
        
        spinStub.setBalance(USER1, 2);
        vm.prank(USER1);
        raffle.spendRaffle(2, 2);
        
        spinStub.setBalance(USER2, 2);
        vm.prank(USER2);
        raffle.spendRaffle(2, 2);
        
        vm.prank(ADMIN);
        raffle.requestWinner(2);
        
        requestId = 2; // From stub
        rng[0] = 3; // Will result in ticket #4
        
        vm.prank(address(supra));
        raffle.handleWinnerSelection(requestId, rng);
        
        // Verify winner is USER2
        winner = raffle.getWinner(2);
        assertEq(winner, USER2);
    }
    
    function testGetUserWinningStatus() public {
        // Draw winner with ticket #2 (USER1) for prize 1
        vm.prank(ADMIN);
        raffle.requestWinner(1);
        
        uint256 requestId = 1;
        uint256[] memory rng = new uint256[](1);
        rng[0] = 1; // Will result in ticket #2
        
        vm.prank(address(supra));
        raffle.handleWinnerSelection(requestId, rng);
        
        // Check unclaimed wins for USER1
        (uint256[] memory unclaimed, uint256[] memory claimed) = raffle.getUserWinningStatus(USER1);
        assertEq(unclaimed.length, 1);
        assertEq(unclaimed[0], 1);
        assertEq(claimed.length, 0);
        
        // USER1 claims prize
        vm.prank(USER1);
        raffle.claimPrize(1);
        
        // Check claimed wins updated
        (unclaimed, claimed) = raffle.getUserWinningStatus(USER1);
        assertEq(unclaimed.length, 0);
        assertEq(claimed.length, 1);
        assertEq(claimed[0], 1);
        
        // No wins for USER2
        (unclaimed, claimed) = raffle.getUserWinningStatus(USER2);
        assertEq(unclaimed.length, 0);
        assertEq(claimed.length, 0);
        
        // Setup another prize where USER2 wins
        vm.prank(ADMIN);
        raffle.addPrize("Second Prize", "Another prize", 100);
        
        spinStub.setBalance(USER1, 2);
        vm.prank(USER1);
        raffle.spendRaffle(2, 2);
        
        spinStub.setBalance(USER2, 2);
        vm.prank(USER2);
        raffle.spendRaffle(2, 2);
        
        vm.prank(ADMIN);
        raffle.requestWinner(2);
        
        requestId = 2;
        rng[0] = 3; // Will result in ticket #4 (USER2)
        
        vm.prank(address(supra));
        raffle.handleWinnerSelection(requestId, rng);
        
        // Check USER2 now has unclaimed win
        (unclaimed, claimed) = raffle.getUserWinningStatus(USER2);
        assertEq(unclaimed.length, 1);
        assertEq(unclaimed[0], 2);
    }
}