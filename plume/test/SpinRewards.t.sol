// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../src/spin/Spin.sol";
import "../src/spin/DateTime.sol";
import "../src/spin/Raffle.sol";
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

// --------------------------------------
// Spin reward tests (patched Split Rewards and handleRandomness)
// --------------------------------------
contract SpinRewardsTest is Test {
    Spin public spin;
    DateTime public dt;
    ArbSysMock public arbSys;
    address constant ADMIN = address(0x1);
    address constant USER = address(0x2);
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
        
        dt = new DateTime();
        vm.warp(dt.toTimestamp(2025, 3, 8, 10, 0, 0));

        vm.prank(ADMIN);
        spin = new Spin();
        
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
        
        // Add spin contract to whitelist
        vm.prank(ADMIN);
        IDepositContract(DEPOSIT_CONTRACT).addContractToWhitelist(address(spin));
        
        // Verify spin contract is whitelisted
        vm.prank(SUPRA_OWNER);
        bool isContractWhitelisted = IDepositContract(DEPOSIT_CONTRACT).isContractWhitelisted(ADMIN, address(spin));
        assertTrue(isContractWhitelisted, "Spin contract is not whitelisted under ADMIN");
        
        // Set minimum balance
        vm.prank(ADMIN);
        IDepositContract(DEPOSIT_CONTRACT).setMinBalanceClient(0.05 ether);
        
        // Verify balance is sufficient
        vm.prank(SUPRA_OWNER);
        uint256 effectiveBalance = IDepositContract(DEPOSIT_CONTRACT).checkEffectiveBalance(ADMIN);
        assertGt(effectiveBalance, 0, "Insufficient balance in Supra Deposit Contract");
        
        // Verify contract is eligible
        vm.prank(SUPRA_OWNER);
        bool contractEligible = IDepositContract(DEPOSIT_CONTRACT).isContractEligible(ADMIN, address(spin));
        assertTrue(contractEligible, "Spin contract is not eligible for VRF");
        
        // Initialize the spin contract
        vm.prank(ADMIN);
        spin.initialize(SUPRA_ORACLE, address(dt));
        
        vm.prank(ADMIN);
        spin.setCampaignStartDate(block.timestamp);
        
        vm.prank(ADMIN);
        spin.setEnableSpin(true);

        // fund contract so it can pay out jackpots
        vm.deal(address(spin), 10_000 ether);
    }

    function _startSpin(uint256 ts) internal returns (uint256) {
        vm.warp(ts);
        vm.recordLogs();
        vm.prank(USER);
        spin.startSpin();
        Vm.Log[] memory L = vm.getRecordedLogs();
        
        // Find the SpinRequested event to get the nonce
        uint256 nonce = 0;
        for (uint i = 0; i < L.length; i++) {
            if (L[i].topics[0] == keccak256("SpinRequested(uint256,address)")) {
                nonce = uint256(L[i].topics[1]);
                break;
            }
        }
        require(nonce != 0, "Nonce not found in logs");
        
        return nonce;
    }

    function testNothingKeepsStreakAlive() public {
        uint256 nonce = _startSpin(dt.toTimestamp(2025, 3, 9, 10, 0, 0));
        uint256[] memory rng = new uint256[](1);
        rng[0] = 950_000; // >900k = Nothing

        vm.prank(SUPRA_ORACLE);
        vm.recordLogs();
        spin.handleRandomness(nonce, rng);
        Vm.Log[] memory L = vm.getRecordedLogs();

        (string memory cat, uint256 amt) = abi.decode(
            L[0].data,
            (string, uint256)
        );
        assertEq(cat, "Nothing");
        assertEq(amt, 0);

        (uint256 streak, , , , , , ) = spin.getUserData(USER);
        assertEq(streak, 1);
    }

    // If a user hits the Jackpot but doesn't have enough streak, they should get nothing
    // If they then hit the Jackpot with enough streak, they should get the Jackpot
    function testJackpotInsufficientThenSufficientStreak() public {
        // Day 0, streak=0 => Nothing
        uint256 n0 = _startSpin(dt.toTimestamp(2025, 3, 8, 10, 0, 0));
        uint256[] memory r0 = new uint256[](1);
        r0[0] = 0; // force jackpot

        vm.prank(SUPRA_ORACLE);
        vm.recordLogs();
        spin.handleRandomness(n0, r0);
        Vm.Log[] memory L0 = vm.getRecordedLogs();
        // Log[0] = NotEnoughStreak, Log[1] = SpinCompleted
        (string memory cat0, uint256 amt0) = abi.decode(
            L0[1].data,
            (string, uint256)
        );
        assertEq(cat0, "Nothing");
        assertEq(amt0, 0);

        // Day 1, streak=1 => Still Nothing (streak too low)
        uint256 n1 = _startSpin(dt.toTimestamp(2025, 3, 9, 10, 0, 0));
        uint256[] memory r1 = new uint256[](1);
        r1[0] = 0;

        vm.prank(SUPRA_ORACLE);
        vm.recordLogs();
        spin.handleRandomness(n1, r1);
        Vm.Log[] memory L1 = vm.getRecordedLogs();
        (string memory cat1, uint256 amt1) = abi.decode(
            L1[1].data,
            (string, uint256)
        );
        assertEq(cat1, "Nothing");
        assertEq(amt1, 0);

        // Day 2, streak=2 => Now should get Jackpot
        uint256 n2 = _startSpin(dt.toTimestamp(2025, 3, 10, 10, 0, 0));
        uint256[] memory r2 = new uint256[](1);
        r2[0] = 0;

        vm.prank(SUPRA_ORACLE);
        vm.recordLogs();
        spin.handleRandomness(n2, r2);
        Vm.Log[] memory L2 = vm.getRecordedLogs();
        (string memory cat2, uint256 amt2) = abi.decode(
            L2[0].data,
            (string, uint256)
        );
        assertEq(cat2, "Jackpot");
        assertEq(amt2, 5000);
        assertEq(USER.balance, 5000 ether);
    }

    function testPlumeTokenRewardAndTransfer() public {
        vm.prank(ADMIN);
        spin.whitelist(USER);

        uint256 n = _startSpin(block.timestamp);
        uint256[] memory r = new uint256[](1);
        r[0] = 100_123; // 1–200k = Plume Token

        vm.prank(SUPRA_ORACLE);
        vm.recordLogs();
        spin.handleRandomness(n, r);
        Vm.Log[] memory L = vm.getRecordedLogs();
        (string memory c, uint256 a) = abi.decode(L[0].data, (string, uint256));
        assertEq(c, "Plume Token");
        assertEq(a, 1);
        assertEq(USER.balance, 1 ether);
    }

    function testRaffleTicketReward() public {
        vm.prank(ADMIN);
        spin.whitelist(USER);

        uint256 n = _startSpin(block.timestamp);
        uint256[] memory r = new uint256[](1);
        r[0] = 300_000; // 200–600k = Raffle Ticket

        vm.prank(SUPRA_ORACLE);
        vm.recordLogs();
        spin.handleRandomness(n, r);
        Vm.Log[] memory L = vm.getRecordedLogs();
        (string memory c, uint256 a) = abi.decode(L[0].data, (string, uint256));
        assertEq(c, "Raffle Ticket");
        assertEq(a, 8); // base 8 * (0+1)

        (, , , , uint256 bal, , ) = spin.getUserData(USER);
        assertEq(bal, 8);
    }

    function testPPReward() public {
        vm.prank(ADMIN);
        spin.whitelist(USER);

        uint256 n = _startSpin(block.timestamp);
        uint256[] memory r = new uint256[](1);
        r[0] = 700_000; // 600–900k = PP

        vm.prank(SUPRA_ORACLE);
        vm.recordLogs();
        spin.handleRandomness(n, r);
        Vm.Log[] memory L = vm.getRecordedLogs();
        (string memory c, uint256 a) = abi.decode(L[0].data, (string, uint256));
        assertEq(c, "PP");
        assertEq(a, 100);

        (, , , , , uint256 pp, ) = spin.getUserData(USER);
        assertEq(pp, 100);
    }
}

// --------------------------------------
// Raffle flow tests (unchanged)
// --------------------------------------
contract SpinStub is ISpin {
    mapping(address => uint256) public balances;
    function setBalance(address u, uint256 v) external {
        balances[u] = v;
    }
    function updateRaffleTickets(address u, uint256 a) external override {
        require(balances[u] >= a, "stub underflow");
        balances[u] -= a;
    }
    function getUserData(
        address u
    )
        external
        view
        override
        returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256)
    {
        return (0, 0, 0, 0, balances[u], 0, 0);
    }
}

contract RaffleFlowTest is Test {
    Raffle public raffle;
    SpinStub public spinStub;
    ArbSysMock public arbSys;
    address constant ADMIN = address(0x1);
    address constant USER = address(0x2);
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
    }

    function testAddAndGetPrizeDetails() public {
        vm.prank(ADMIN);
        raffle.addPrize("Gold", "Shiny", 0);
        (string memory n, string memory d, uint256 t, , address w, , ) = raffle
            .getPrizeDetails(1);
        assertEq(n, "Gold");
        assertEq(d, "Shiny");
        assertEq(t, 0);
        assertEq(w, address(0));
    }

    function testRemovePrize() public {
        vm.prank(ADMIN);
        raffle.addPrize("X", "X", 0);
        vm.prank(ADMIN);
        raffle.removePrize(1);
        (, , , bool active, , , ) = raffle.getPrizeDetails(1);
        assertFalse(active);
    }

    function testSpendRaffleSuccess() public {
        vm.prank(ADMIN);
        raffle.addPrize("A", "A", 0);
        spinStub.setBalance(USER, 10);
        vm.prank(USER);
        raffle.spendRaffle(1, 5);
        assertEq(spinStub.balances(USER), 5);
        (, , uint256 pool, , , , ) = raffle.getPrizeDetails(1);
        assertEq(pool, 5);
    }

    function testSpendRaffleInsufficient() public {
        vm.prank(ADMIN);
        raffle.addPrize("A", "A", 0);
        spinStub.setBalance(USER, 1);
        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(Raffle.InsufficientTickets.selector)
        );
        raffle.spendRaffle(1, 2);
    }

    function testRequestWinnerAndSelection() public {
        vm.prank(ADMIN);
        raffle.addPrize("A", "A", 0);
        spinStub.setBalance(USER, 3);
        vm.prank(USER);
        raffle.spendRaffle(1, 3);

        vm.recordLogs();
        vm.prank(ADMIN);
        raffle.requestWinner(1);
        Vm.Log[] memory L = vm.getRecordedLogs();
        assertEq(L[1].topics[0], keccak256("WinnerRequested(uint256,uint256)"));
        uint256 req = uint256(L[1].topics[2]);

        uint256[] memory r = new uint256[](1);
        r[0] = 1;
        vm.recordLogs();
        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(req, r);
        L = vm.getRecordedLogs();
        assertEq(L[0].topics[0], keccak256("WinnerSelected(uint256,uint256)"));
    }

    function testClaimPrizeSuccess() public {
        vm.prank(ADMIN);
        raffle.addPrize("A", "A", 0);

        // Increase ticket amount to make sure the total is properly updated
        spinStub.setBalance(USER, 1);
        vm.prank(USER);
        raffle.spendRaffle(1, 1);

        // First verify tickets were spent
        (, , uint256 pool, , , , ) = raffle.getPrizeDetails(1);
        assertEq(pool, 1); // Make sure tickets were added to the pool

        vm.recordLogs();
        vm.prank(ADMIN);
        raffle.requestWinner(1);
        Vm.Log[] memory L1 = vm.getRecordedLogs();

        // Find the correct request ID from logs
        uint256 req = 0;
        for (uint i = 0; i < L1.length; i++) {
            if (
                L1[i].topics[0] == keccak256("WinnerRequested(uint256,uint256)")
            ) {
                req = uint256(L1[i].topics[2]);
                break;
            }
        }

        // Generate a random number that will select the user's ticket
        // Since we know there's only 1 ticket (index 1), we pass a value that will result in index 1
        // Random value mod totalTickets (1) + 1 = 1
        uint256[] memory r = new uint256[](1);
        r[0] = 0; // 0 % 1 + 1 = 1

        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(req, r);

        vm.recordLogs();
        vm.prank(USER);
        raffle.claimPrize(1);
        Vm.Log[] memory L2 = vm.getRecordedLogs();

        // Verify the PrizeClaimed event
        bool foundEvent = false;
        for (uint i = 0; i < L2.length; i++) {
            if (L2[i].topics[0] == keccak256("PrizeClaimed(address,uint256)")) {
                foundEvent = true;
                break;
            }
        }
        assertTrue(foundEvent, "PrizeClaimed event not found");
    }

    function testClaimPrizeNotWinner() public {
        vm.prank(ADMIN);
        raffle.addPrize("A", "A", 0);

        // Ensure we spend tickets so total is > 0
        spinStub.setBalance(USER, 2); // Increase to 2 tickets
        vm.prank(USER);
        raffle.spendRaffle(1, 2); // Spend 2 tickets

        // Verify tickets were spent
        (, , uint256 pool, , , , ) = raffle.getPrizeDetails(1);
        assertEq(pool, 2); // Tickets should be in the pool

        vm.recordLogs();
        vm.prank(ADMIN);
        raffle.requestWinner(1);
        Vm.Log[] memory L1 = vm.getRecordedLogs();

        // Find the request ID from logs
        uint256 req = 0;
        for (uint i = 0; i < L1.length; i++) {
            if (
                L1[i].topics[0] == keccak256("WinnerRequested(uint256,uint256)")
            ) {
                req = uint256(L1[i].topics[2]);
                break;
            }
        }

        // Generate a random number that will select a winning ticket
        // We have 2 tickets (index 1-2), and USER owns both
        // Set different user as claimer who doesn't own any tickets
        uint256[] memory r = new uint256[](1);
        r[0] = 0; // 0 % 2 + 1 = 1 (first ticket)

        vm.prank(SUPRA_ORACLE);
        raffle.handleWinnerSelection(req, r);

        // Try to claim with a different address
        vm.prank(address(0x3));
        vm.expectRevert(Raffle.NotAWinner.selector);
        raffle.claimPrize(1);
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


