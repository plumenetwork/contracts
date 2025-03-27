// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../src/interfaces/ISupraRouterContract.sol";
import "../src/spin/DateTime.sol";
import "../src/spin/Spin.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

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

    address constant ADMIN = address(0x1);
    address constant USER = address(0x2);
    address constant SUPRA_ORACLE = address(0x6D46C098996AD584c9C40D6b4771680f54cE3726);
    address constant DEPOSIT_CONTRACT = address(0x3B5F96986389f6BaCF58d5b69425fab000D3551e);
    address constant SUPRA_OWNER = address(0x578DD059Ec425F83cCCC3149ed594d4e067A5307);

    uint256 constant COOLDOWN_PERIOD = 86_400; // 1 day
    uint8 constant RNG_COUNT = 1;
    uint256 constant NUM_CONFIRMATIONS = 1;

    function setUp() public payable {
        // Fork from mainnet for testing with the deployed Supra Oracle
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));

        // Deploy the DateTime contract from src/DateTime.sol
        dateTime = new DateTime();
        vm.warp(dateTime.toTimestamp(2025, 3, 1, 10, 0, 0));

        // Deploy the Spin contract
        vm.prank(ADMIN);
        spin = new Spin();

        vm.prank(ADMIN);
        spin.initialize(SUPRA_ORACLE, address(dateTime));

        vm.prank(SUPRA_OWNER);
        IDepositContract(DEPOSIT_CONTRACT).addClientToWhitelist(ADMIN, true);

        bool isWhitelisted = IDepositContract(DEPOSIT_CONTRACT).isClientWhitelisted(ADMIN);
        assertTrue(isWhitelisted, "Spin contract is not whitelisted under ADMIN");

        vm.deal(ADMIN, 1 ether);
        vm.prank(ADMIN);
        IDepositContract(DEPOSIT_CONTRACT).depositFundClient{ value: 0.1 ether }();

        vm.prank(ADMIN);
        IDepositContract(DEPOSIT_CONTRACT).addContractToWhitelist(address(spin));

        vm.prank(SUPRA_OWNER);
        bool isContractWhitelisted = IDepositContract(DEPOSIT_CONTRACT).isContractWhitelisted(ADMIN, address(spin));
        assertTrue(isContractWhitelisted, "Spin contract is not whitelisted under ADMIN");

        vm.prank(ADMIN);
        IDepositContract(DEPOSIT_CONTRACT).setMinBalanceClient(0.05 ether);

        vm.prank(SUPRA_OWNER);
        uint256 effectiveBalance = IDepositContract(DEPOSIT_CONTRACT).checkEffectiveBalance(ADMIN);
        assertGt(effectiveBalance, 0, "Insufficient balance in Supra Deposit Contract");

        vm.prank(SUPRA_OWNER);
        bool contractEligible = IDepositContract(DEPOSIT_CONTRACT).isContractEligible(ADMIN, address(spin));
        assertTrue(contractEligible, "Spin contract is not eligible for VRF");

        assertTrue(spin.hasRole(spin.DEFAULT_ADMIN_ROLE(), ADMIN), "ADMIN is not the contract admin");
    }

    function testStartSpin() public {
        // Ensure last spin date is set correctly
        vm.record();
        vm.warp(dateTime.toTimestamp(2025, 3, 2, 10, 0, 0));
        vm.prank(USER);
        spin.startSpin();
        // Retrieve the recorded storage accesses
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(spin));

        // Get the call data size
        uint256 callDataSize = writes.length * 32; // Each slot is 32 bytes

        // Log the size (useful for debugging)
        emit log_named_uint("Call Data Size (bytes)", callDataSize);

        // Assert that the call data is non-zero
        assertGt(callDataSize, 0, "Call Data Size should be greater than 0");
    }

    function testCooldownEnforcement() public {
        // Start spin
        vm.warp(dateTime.toTimestamp(2025, 3, 9, 10, 0, 0));
        vm.prank(USER);
        uint256 nonce = spin.startSpin();

        uint256[] memory testRNG = new uint256[](1);
        testRNG[0] = uint256(keccak256(abi.encodePacked(block.timestamp))) % 1_000_000;

        vm.prank(SUPRA_ORACLE); // Simulate Supra calling
        spin.handleRandomness(nonce, testRNG, 1);

        // Attempt to spin again within cooldown period
        vm.warp(dateTime.toTimestamp(2025, 3, 9, 14, 0, 0));
        vm.expectRevert(abi.encodeWithSignature("AlreadySpunToday()"));
        vm.prank(USER);
        spin.startSpin();
    }

    function testSimulateVRFCallback() public {
        vm.warp(dateTime.toTimestamp(2025, 3, 9, 10, 0, 0));
        vm.prank(address(10));
        spin.startSpin();

        vm.prank(address(9));
        uint256 nonce = spin.startSpin();
        uint256[] memory testRNG = new uint256[](1);
        testRNG[0] = uint256(keccak256(abi.encodePacked(block.timestamp))) % 1_000_000;

        vm.prank(SUPRA_ORACLE); // Simulate Supra calling
        spin.handleRandomness(nonce, testRNG, 1);
    }

    function testMassSimulateJackpotHits() public {
        uint256 baseTimestamp = dateTime.toTimestamp(2025, 3, 10, 0, 0, 0);
        vm.warp(baseTimestamp);
        vm.prank(ADMIN);
        spin.setCampaignStartDate();
        baseTimestamp = dateTime.toTimestamp(2025, 3, 10, 10, 0, 0);
        uint256 spinsPerDay = 100;
        uint256 userSeed = 100; // Avoid low-address collisions

        // Simulate over 7 days
        for (uint256 day = 1; day <= 7; day++) {
            for (uint256 i = 0; i < spinsPerDay; i++) {
                address user = address(uint160(userSeed + i));
                uint256 hour = (i % 24); // spread spins over 24 hours
                uint256 minute = (i % 60);
                uint256 ts = baseTimestamp + ((day - 1) * 1 days) + (hour * 1 hours) + (minute * 1 minutes);
                vm.warp(ts);

                vm.prank(user);
                uint256 nonce = spin.startSpin();

                uint256[] memory testRNG = new uint256[](1);
                testRNG[0] = uint256(keccak256(abi.encodePacked(ts, user))) % 1_000_000;

                vm.prank(SUPRA_ORACLE); // simulate Supra VRF callback
                spin.handleRandomness(nonce, testRNG, uint8(day));
            }

            userSeed += spinsPerDay; // Next day new users
        }

        // Log daily prize distribution
        for (uint8 day = 1; day <= 7; day++) {
            uint256[5] memory counts = spin.getWeeklyPrizeStats(day);
            console.log(" Day", day);
            console.log(" Jackpot      :", counts[0]);
            console.log(" RaffleTicket:", counts[1]);
            console.log(" XP           :", counts[2]);
            console.log(" PlumeToken   :", counts[3]);
            console.log("  Nothing      :", counts[4]);
        }
    }

}
