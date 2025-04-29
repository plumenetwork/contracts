// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../src/interfaces/ISupraRouterContract.sol";
import "../src/interfaces/IDateTime.sol";
import "../src/spin/DateTime.sol";
import "../src/spin/Spin.sol";
import "../src/helpers/ArbSys.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

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

contract SpinTest is Test {
    Spin spin;
    ISupraRouterContract supraRouter;
    IDepositContract depositContract;
    DateTime dateTime;
    ArbSysMock arbSys;

    address payable constant ADMIN = payable(address(0x1));
    address constant USER = address(0x2);
    address constant SUPRA_ORACLE = address(0x6D46C098996AD584c9C40D6b4771680f54cE3726);
    address constant DEPOSIT_CONTRACT = address(0x3B5F96986389f6BaCF58d5b69425fab000D3551e);
    address constant SUPRA_OWNER = address(0x578DD059Ec425F83cCCC3149ed594d4e067A5307);
    address constant ARB_SYS_ADDRESS = address(100); // 0x0000000000000000000000000000000000000064

    uint256 constant COOLDOWN_PERIOD = 86_400; // 1 day
    uint8 constant RNG_COUNT = 1;
    uint256 constant NUM_CONFIRMATIONS = 1;
    mapping(bytes32 => uint256) public prizeCounts;

    function setUp() public payable {
        // Fork from mainnet for testing with the deployed Supra Oracle
        vm.createSelectFork(vm.envString("PLUME_TEST_RPC_URL"));

        // Deploy and set up ArbSysMock at the special address
        arbSys = new ArbSysMock();
        vm.etch(ARB_SYS_ADDRESS, address(arbSys).code);

        // Deploy the DateTime contract from src/DateTime.sol
        dateTime = new DateTime();
        vm.warp(dateTime.toTimestamp(2025, 3, 8, 10, 0, 0));

        // Deploy the Spin contract
        vm.prank(ADMIN);
        spin = new Spin();

        vm.prank(ADMIN);
        spin.initialize(SUPRA_ORACLE, address(dateTime));

        vm.prank(ADMIN);
        spin.setCampaignStartDate(block.timestamp);

        vm.prank(ADMIN);
        spin.setEnableSpin(true);

        vm.prank(SUPRA_OWNER);
        IDepositContract(DEPOSIT_CONTRACT).addClientToWhitelist(ADMIN, true);
        console.log("Client whitelisted");

        bool isWhitelisted = IDepositContract(DEPOSIT_CONTRACT).isClientWhitelisted(ADMIN);
        assertTrue(isWhitelisted, "Spin contract is not whitelisted under ADMIN");
        console.log("Whitelist verified");

        vm.deal(ADMIN, 200 ether);
        vm.prank(ADMIN);
        IDepositContract(DEPOSIT_CONTRACT).depositFundClient{ value: 0.1 ether }();
        console.log("Funds deposited");

        vm.prank(ADMIN);
        IDepositContract(DEPOSIT_CONTRACT).addContractToWhitelist(address(spin));
        console.log("Contract whitelisted");

        vm.prank(SUPRA_OWNER);
        bool isContractWhitelisted = IDepositContract(DEPOSIT_CONTRACT).isContractWhitelisted(ADMIN, address(spin));
        assertTrue(isContractWhitelisted, "Spin contract is not whitelisted under ADMIN");

        vm.prank(ADMIN);
        IDepositContract(DEPOSIT_CONTRACT).setMinBalanceClient(0.05 ether);

        vm.prank(SUPRA_OWNER);
        uint256 effectiveBalance = IDepositContract(DEPOSIT_CONTRACT).checkEffectiveBalance(ADMIN);
        console.log("Effective balance:", effectiveBalance);
        assertGt(effectiveBalance, 0, "Insufficient balance in Supra Deposit Contract");

        vm.prank(SUPRA_OWNER);
        bool contractEligible = IDepositContract(DEPOSIT_CONTRACT).isContractEligible(ADMIN, address(spin));
        assertTrue(contractEligible, "Spin contract is not eligible for VRF");
        console.log("Contract eligible verified");

        vm.prank(ADMIN);
        address(spin).call{ value: 100 ether }("");

        assertTrue(spin.hasRole(spin.DEFAULT_ADMIN_ROLE(), ADMIN), "ADMIN is not the contract admin");
    }

    function testStartSpin() public {
        vm.recordLogs();

        vm.warp(dateTime.toTimestamp(2025, 3, 10, 10, 0, 0));
        vm.prank(USER);
        spin.startSpin();

        // Expect emit Spin requested
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 2, "No logs emitted");

        assertEq(entries[1].topics[0], keccak256("SpinRequested(uint256,address)"), "SpinRequested event not emitted");
        assertEq(entries[1].topics[2], bytes32(uint256(uint160(USER))), "User address incorrect");

        uint256 nonce = uint256(entries[0].topics[1]);
        emit log_named_uint("Extracted Nonce", nonce);

        assertGt(nonce, 0, "Nonce should be greater than 0");
    }
}
