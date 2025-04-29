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

contract RaffleExtraTests is Test {
    Raffle     public raffle;
    SpinStub   public spinStub;
    StubSupra  public supra;
    address    constant ADMIN        = address(0x1);
    address    constant USER         = address(0x2);
    address    constant OTHER        = address(0x3);

    function setUp() public {
        supra    = new StubSupra();
        spinStub = new SpinStub();
        raffle   = new Raffle();

        vm.prank(ADMIN);
        raffle.initialize(address(spinStub), address(supra));
    }

    function testRemovePrizeFlow() public {
        vm.prank(ADMIN);
        raffle.addPrize("Test","Desc",1);
        // Remove prize
        vm.prank(ADMIN);
        raffle.removePrize(1);
        // Now spendRaffle should revert PrizeInactive
        spinStub.setBalance(USER,1);
        vm.prank(USER);
        vm.expectRevert("Prize not available");
        raffle.spendRaffle(1,1);
        // requestWinner should revert PrizeInactive
        vm.prank(ADMIN);
        vm.expectRevert();
        raffle.requestWinner(1);
    }

    function testSpendRaffleZeroTicketsReverts() public {
        vm.prank(ADMIN);
        raffle.addPrize("A","A",1);
        vm.prank(USER);
        vm.expectRevert("Must spend at least 1 ticket");
        raffle.spendRaffle(1,0);
    }

    function testSpendRaffleMultipleEntriesAndTotalUsers() public {
        vm.prank(ADMIN);
        raffle.addPrize("A","A",1);
        // First entry
        spinStub.setBalance(USER,5);
        vm.prank(USER);
        raffle.spendRaffle(1,2);
        (, , , , , , uint256 users1) = raffle.getPrizeDetails(1);
        assertEq(users1, 1);
        // Second entry same user
        spinStub.setBalance(USER,5);
        vm.prank(USER);
        raffle.spendRaffle(1,3);
        (, , , , , , uint256 users2) = raffle.getPrizeDetails(1);
        assertEq(users2, 1, "totalUsers should not increment for repeat entry");
    }

    function testRequestWinnerEmptyPoolReverts() public {
        vm.prank(ADMIN);
        raffle.addPrize("A","A",1);
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(Raffle.EmptyTicketPool.selector));
        raffle.requestWinner(1);
    }

    function testRequestWinnerAlreadyDrawnReverts() public {
        vm.prank(ADMIN);
        raffle.addPrize("A","A",1);
        // add tickets
        spinStub.setBalance(USER,1);
        vm.prank(USER);
        raffle.spendRaffle(1,1);
        
        // first draw
        vm.recordLogs();
        vm.prank(ADMIN);
        raffle.requestWinner(1);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        // Find request ID in logs
        uint256 req = 0;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("WinnerRequested(uint256,uint256)")) {
                req = uint256(logs[i].topics[2]);
                break;
            }
        }
        require(req != 0, "Request ID not found in logs");
        
        uint256[] memory rng = new uint256[](1);
        rng[0] = 0;
        vm.prank(address(supra));
        raffle.handleWinnerSelection(req, rng);
        
        // Check that winnerIndex is set
        (, , , , , uint256 winnerIdx, ) = raffle.getPrizeDetails(1);
        assertEq(winnerIdx, 1, "Winner index should be set");
        
        // Now claim the prize to set winner and make active=false
        vm.prank(USER);
        raffle.claimPrize(1);
        
        // Verify prize no longer active
        (, , , bool active, , , ) = raffle.getPrizeDetails(1);
        assertFalse(active, "Prize should be inactive after claiming");
        
        // second request should revert with "Prize not available" since we've claimed it
        vm.prank(ADMIN);
        vm.expectRevert("Prize not available");
        raffle.requestWinner(1);
    }

    function testHandleWinnerSelectionSetsWinnerIndex() public {
        vm.prank(ADMIN);
        raffle.addPrize("A","A",1);
        spinStub.setBalance(USER,3);
        vm.prank(USER);
        raffle.spendRaffle(1,3);
        
        vm.recordLogs();
        vm.prank(ADMIN);
        raffle.requestWinner(1);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        uint256 req = 0;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("WinnerRequested(uint256,uint256)")) {
                req = uint256(logs[i].topics[2]);
                break;
            }
        }
        require(req != 0, "Request ID not found in logs");

        uint256[] memory rng = new uint256[](1);
        rng[0] = 5;
        vm.prank(address(supra));
        raffle.handleWinnerSelection(req, rng);

        (, , , , , uint256 winnerIdx, ) = raffle.getPrizeDetails(1);
        assertEq(winnerIdx, 3);
    }

    function testClaimPrizeDoubleClaimReverts() public {
        vm.prank(ADMIN);
        raffle.addPrize("A","A",1);
        spinStub.setBalance(USER,1);
        vm.prank(USER);
        raffle.spendRaffle(1,1);

        vm.recordLogs();
        vm.prank(ADMIN);
        raffle.requestWinner(1);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        // Find request ID in logs
        uint256 req = 0;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("WinnerRequested(uint256,uint256)")) {
                req = uint256(logs[i].topics[2]);
                break;
            }
        }
        require(req != 0, "Request ID not found in logs");
        
        uint256[] memory rng = new uint256[](1); 
        rng[0] = 0;
        vm.prank(address(supra)); 
        raffle.handleWinnerSelection(req, rng);

        // first claim
        vm.prank(USER);
        raffle.claimPrize(1);
        // second claim should revert Prize not available
        vm.prank(USER);
        vm.expectRevert("Prize not available");
        raffle.claimPrize(1);
    }

    function testGetUserEntriesAndOverload() public {
        vm.prank(ADMIN);
        raffle.addPrize("A","A",1);
        spinStub.setBalance(USER,4);
        vm.prank(USER); raffle.spendRaffle(1,2);
        vm.prank(USER); raffle.spendRaffle(1,1);

        // getUserEntries(prizeId, user)
        (uint256 count, uint256[] memory wins) = raffle.getUserEntries(1, USER);
        assertEq(count, 3);
        assertEq(wins.length, 0);

        // draw and claim so that wins populated
        vm.recordLogs();
        vm.prank(ADMIN); 
        raffle.requestWinner(1);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        // Find request ID in logs
        uint256 req = 0;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("WinnerRequested(uint256,uint256)")) {
                req = uint256(logs[i].topics[2]);
                break;
            }
        }
        require(req != 0, "Request ID not found in logs");
        
        uint256[] memory rng = new uint256[](1); 
        rng[0] = 1;
        vm.prank(address(supra)); 
        raffle.handleWinnerSelection(req, rng);
        vm.prank(USER); 
        raffle.claimPrize(1);

        (count, wins) = raffle.getUserEntries(1, USER);
        assertEq(wins.length, 1);
        assertEq(wins[0], 1);

        // getUserEntries(user)
        (uint256[] memory ids, uint256[] memory counts, uint256[] memory wlist) = raffle.getUserEntries(USER);
        assertEq(ids.length, 1);
        assertEq(counts[0], 3);
        assertEq(wlist[0], 1);
    }
}

