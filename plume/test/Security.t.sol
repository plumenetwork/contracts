// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/* ──────────────────────────────────────────────────────────── */
/*                        VRF Stub (no interface)             */
/* ──────────────────────────────────────────────────────────── */
/// @notice Minimal stub that only provides generateRequest()
contract StubSupra {
    uint256 private next = 1;
    /// @dev Mimics VRF: each call returns a new nonce
    function generateRequest(
        string calldata,  // callbackSignature
        uint8,            // rngCount
        uint256,          // numConfirmations
        uint256,          // clientSeed
        address           // clientAddress
    ) external returns (uint256) {
        return next++;
    }
}

/* ──────────────────────────────────────────────────────────── */
/*                     Contracts under test                    */
/* ──────────────────────────────────────────────────────────── */
import {Spin}     from "../src/spin/Spin.sol";
import {DateTime} from "../src/spin/DateTime.sol";
import "../src/helpers/ArbSys.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

/* ──────────────────────────────────────────────────────────── */
/*                       ArbSys Mock                           */
/* ──────────────────────────────────────────────────────────── */
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

/* ──────────────────────────────────────────────────────────── */
/*                          Attacker                          */
/* ──────────────────────────────────────────────────────────── */
contract Attacker {
    Spin public immutable spin;
    constructor(Spin _spin) { spin = _spin; }

    /// Fallback during ETH transfer → tries to re-enter startSpin()
    fallback() external payable {
        try spin.startSpin() {
            revert("re-enter succeeded");
        } catch { }
    }

    /// Entry for the first spin
    function launch() external {
        spin.startSpin();
    }

    receive() external payable {}
}

/* ──────────────────────────────────────────────────────────── */
/*                             Test                             */
/* ──────────────────────────────────────────────────────────── */
contract ReentrancyTest is Test {
    Spin      spin;
    DateTime  dt;
    ArbSysMock arbSys;
    address constant ADMIN = address(0x1);
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

        // Deploy the DateTime helper
        dt = new DateTime();

        // Deploy & initialize Spin
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

        // Enable spins and set campaign start
        vm.prank(ADMIN);
        spin.setCampaignStartDate(block.timestamp);
        
        // Important: Enable spinning (this was commented out in the original)
        vm.prank(ADMIN);
        spin.setEnableSpin(true);

        // Give the Spin contract some ETH to pay out
        vm.deal(address(spin), 10 ether);
    }

   function testCannotReenter() public {
        // 1) Deploy attacker
        Attacker atk = new Attacker(spin);

        // 2) Advance one day so canSpin() passes
        vm.warp(block.timestamp + 1 days);

        // 3) Attacker launches the first spin and record logs to get the nonce
        vm.recordLogs();
        vm.prank(address(atk));
        atk.launch();
        
        // Extract nonce from the logs
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 nonce = 0;
        
        // Look for the SpinRequested event to get the nonce
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("SpinRequested(uint256,address)")) {
                nonce = uint256(logs[i].topics[1]);
                break;
            }
        }
        
        // Make sure we got a valid nonce
        require(nonce != 0, "Failed to get nonce from logs");
        console.log("Extracted nonce:", nonce);

        // 4) Prepare RNG to force "Nothing" (no cooldown)
        uint256[] memory rng = new uint256[](1);
        rng[0] = 999_999;

        // 5) Simulate VRF callback with the correct nonce
        vm.prank(SUPRA_ORACLE);
        spin.handleRandomness(nonce, rng);

        // 6) If fallback re-entered successfully, streak > 1; assert it stayed 1
        (uint256 streak,,,,,,) = spin.getUserData(address(atk));
        assertEq(streak, 1, "Re-entrancy guard failed (streak > 1)");
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
