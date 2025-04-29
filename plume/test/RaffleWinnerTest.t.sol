// test/RaffleWinnerTest.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../src/spin/Raffle.sol";
import "../src/interfaces/ISupraRouterContract.sol";
import "../src/helpers/ArbSys.sol";
import "forge-std/Test.sol";

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

contract RaffleWinnerTests is Test {
    Raffle public raffle;
    SpinStub public spinStub;
    ArbSysMock public arbSys;
    
    address constant ADMIN = address(0x1);
    address constant USER1 = address(0x2);
    address constant USER2 = address(0x3);
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
        
        // Initialize the raffle contract
        vm.prank(ADMIN);
        raffle.initialize(address(spinStub), SUPRA_ORACLE);
        
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
        rng[0] = 1; // Will result in ticket #2
        
        vm.prank(SUPRA_ORACLE);
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
        
        rng[0] = 3; // Will result in ticket #4
        
        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(requestId, rng);
        
        // Verify winner is USER2
        winner = raffle.getWinner(2);
        assertEq(winner, USER2);
    }
    
    function testGetUserWinningStatus() public {
        // Draw winner with ticket #2 (USER1) for prize 1
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
        rng[0] = 1; // Will result in ticket #2
        
        vm.prank(SUPRA_ORACLE);
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
        
        rng[0] = 3; // Will result in ticket #4 (USER2)
        
        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(requestId, rng);
        
        // Check USER2 now has unclaimed win
        (unclaimed, claimed) = raffle.getUserWinningStatus(USER2);
        assertEq(unclaimed.length, 1);
        assertEq(unclaimed[0], 2);
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