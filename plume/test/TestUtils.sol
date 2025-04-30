// TestUtils.sol - Shared utilities, mocks, and setup helpers
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../src/helpers/ArbSys.sol";
import "../src/spin/Spin.sol";
import "../src/spin/DateTime.sol";
import "../src/interfaces/ISupraRouterContract.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

// Shared constants used across tests
address payable constant ADMIN = payable(address(0x1));
address payable constant USER = payable(address(0x2));
address constant USER2 = address(0x3);
address constant USER3 = address(0x4);
address payable constant USER4 = payable(address(0x5));
address payable constant USER5 = payable(address(0x6));
address constant SUPRA_ORACLE = address(0x6D46C098996AD584c9C40D6b4771680f54cE3726);
address constant DEPOSIT_CONTRACT = address(0x3B5F96986389f6BaCF58d5b69425fab000D3551e);
address constant SUPRA_OWNER = address(0x578DD059Ec425F83cCCC3149ed594d4e067A5307);
address constant ARB_SYS_ADDRESS = address(100); // 0x0000000000000000000000000000000000000064

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

/// @notice Interface for the Supra Deposit Contract
interface IDepositContract {
    function addContractToWhitelist(address contractAddress) external;
    function addClientToWhitelist(address clientAddress, bool snap) external;
    function depositFundClient() external payable;
    function isClientWhitelisted(address clientAddress) external view returns (bool);
    function isContractWhitelisted(address client, address contractAddress) external view returns (bool);
    function checkEffectiveBalance(address clientAddress) external view returns (uint256);
    function isContractEligible(address client, address contractAddress) external view returns (bool);
    function setMinBalanceClient(uint256 minBalance) external;
}

/// @notice Interface for the Spin contract used in Raffle tests
interface ISpin {
    function updateRaffleTickets(address _user, uint256 _amount) external;
    function getUserData(
        address _user
    ) external view returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256);
}

/// @notice Minimal stub implementing ISpin for ticket balances in tests
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

/// @notice Base test contract with common setup logic
abstract contract PlumeTestBase is Test {
    ArbSysMock public arbSys;
    
    function setupArbSys() internal {
        // Setup ArbSys mock at the special address
        arbSys = new ArbSysMock();
        vm.etch(ARB_SYS_ADDRESS, address(arbSys).code);
    }
    
    function setupFork() internal {
        // Fork from test RPC
        vm.createSelectFork(vm.envString("PLUME_TEST_RPC_URL"));
    }
    
    function whitelistContract(address clientAdmin, address contractToWhitelist) internal {
        // Add admin to whitelist
        vm.prank(SUPRA_OWNER);
        IDepositContract(DEPOSIT_CONTRACT).addClientToWhitelist(clientAdmin, true);
        
        // Verify admin is whitelisted
        bool isWhitelisted = IDepositContract(DEPOSIT_CONTRACT).isClientWhitelisted(clientAdmin);
        assertTrue(isWhitelisted, "Admin is not whitelisted");
        
        // Fund admin account for deposit
        vm.deal(clientAdmin, 200 ether);
        
        // Deposit funds
        vm.prank(clientAdmin);
        IDepositContract(DEPOSIT_CONTRACT).depositFundClient{ value: 0.1 ether }();
        
        // Add contract to whitelist
        vm.prank(clientAdmin);
        IDepositContract(DEPOSIT_CONTRACT).addContractToWhitelist(contractToWhitelist);
        
        // Verify contract is whitelisted
        vm.prank(SUPRA_OWNER);
        bool isContractWhitelisted = IDepositContract(DEPOSIT_CONTRACT).isContractWhitelisted(clientAdmin, contractToWhitelist);
        assertTrue(isContractWhitelisted, "Contract is not whitelisted under admin");
        
        // Set minimum balance
        vm.prank(clientAdmin);
        IDepositContract(DEPOSIT_CONTRACT).setMinBalanceClient(0.05 ether);
        
        // Verify balance is sufficient
        vm.prank(SUPRA_OWNER);
        uint256 effectiveBalance = IDepositContract(DEPOSIT_CONTRACT).checkEffectiveBalance(clientAdmin);
        assertGt(effectiveBalance, 0, "Insufficient balance in Supra Deposit Contract");
        
        // Verify contract is eligible
        vm.prank(SUPRA_OWNER);
        bool contractEligible = IDepositContract(DEPOSIT_CONTRACT).isContractEligible(clientAdmin, contractToWhitelist);
        assertTrue(contractEligible, "Contract is not eligible for VRF");
    }
    
    // Helper to extract request ID from event logs for VRF requests
    function extractRequestIdFromLogs(Vm.Log[] memory logs, bytes32 eventSignature) internal pure returns (uint256) {
        uint256 requestId = 0;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSignature) {
                requestId = uint256(logs[i].topics[2]);
                break;
            }
        }
        require(requestId != 0, "Request ID not found in logs");
        return requestId;
    }
    
    // Helper to extract nonce from SpinRequested event logs
    function extractNonceFromLogs(Vm.Log[] memory logs) internal pure returns (uint256) {
        uint256 nonce = 0;
        bytes32 eventSignature = keccak256("SpinRequested(uint256,address)");
        
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSignature) {
                nonce = uint256(logs[i].topics[1]);
                break;
            }
        }
        require(nonce != 0, "Nonce not found in logs");
        return nonce;
    }
}

/// @notice Base contract for Spin tests with common setup and utilities
abstract contract SpinTestBase is PlumeTestBase {
    Spin public spin;
    DateTime public dateTime;
    
    // Common setup for Spin test contracts
    function setupSpin(uint16 year, uint8 month, uint8 day, uint8 hour, uint8 minute, uint8 second) internal {
        // Fork and setup ArbSys
        setupFork();
        setupArbSys();
        
        // Deploy DateTime and set time
        dateTime = new DateTime();
        vm.warp(dateTime.toTimestamp(year, month, day, hour, minute, second));
        
        // Deploy Spin contract
        vm.prank(ADMIN);
        spin = new Spin();
        
        // Initialize Spin
        vm.prank(ADMIN);
        spin.initialize(SUPRA_ORACLE, address(dateTime));
        
        // Set campaign start date to now
        vm.prank(ADMIN);
        spin.setCampaignStartDate(block.timestamp);
        
        // Enable spins
        vm.prank(ADMIN);
        spin.setEnableSpin(true);
        
        // Whitelist contract with Supra Oracle
        whitelistContract(ADMIN, address(spin));
        
        // Fund the contract
        (bool success, ) = address(spin).call{ value: 100 ether }("");
        require(success, "Failed to fund spin contract");
        
        // Verify admin role
        assertTrue(spin.hasRole(spin.DEFAULT_ADMIN_ROLE(), ADMIN), "ADMIN is not the contract admin");
    }
    
    // Perform a spin and get the nonce
    function performSpin(address user) internal returns (uint256) {
        vm.recordLogs();
        vm.prank(user);
        spin.startSpin();
        
        return extractNonceFromLogs(vm.getRecordedLogs());
    }
    
    // Complete a spin with given RNG result
    function completeSpin(uint256 nonce, uint256 rngValue) internal {
        uint256[] memory rng = new uint256[](1);
        rng[0] = rngValue;
        
        vm.prank(SUPRA_ORACLE);
        spin.handleRandomness(nonce, rng);
    }
}
