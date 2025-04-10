// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.25;

// import "../src/interfaces/ISupraRouterContract.sol";
// import "../src/spin/DateTime.sol";
// import "../src/spin/Spin.sol";
// import "forge-std/Test.sol";
// import "forge-std/console.sol";

// interface IDepositContract {

//     function addContractToWhitelist(
//         address contractAddress
//     ) external;
//     function addClientToWhitelist(address clientAddress, bool snap) external;
//     function depositFundClient() external payable;
//     function isClientWhitelisted(
//         address clientAddress
//     ) external view returns (bool);
//     function isContractWhitelisted(address client, address contractAddress) external view returns (bool);
//     function checkEffectiveBalance(
//         address clientAddress
//     ) external view returns (uint256);
//     function isContractEligible(address client, address contractAddress) external view returns (bool);
//     function setMinBalanceClient(
//         uint256 minBalance
//     ) external;

// }

// contract SpinTest is Test {

//     Spin spin;
//     ISupraRouterContract supraRouter;
//     IDepositContract depositContract;
//     DateTime dateTime;

//     address constant ADMIN = address(0x1);
//     address constant USER = address(0x2);
//     address constant SUPRA_ORACLE = address(0x6D46C098996AD584c9C40D6b4771680f54cE3726);
//     address constant DEPOSIT_CONTRACT = address(0x3B5F96986389f6BaCF58d5b69425fab000D3551e);
//     address constant SUPRA_OWNER = address(0x578DD059Ec425F83cCCC3149ed594d4e067A5307);

//     uint256 constant COOLDOWN_PERIOD = 86_400; // 1 day
//     uint8 constant RNG_COUNT = 1;
//     uint256 constant NUM_CONFIRMATIONS = 1;
//     mapping(bytes32 => uint256) public prizeCounts;

//     function setUp() public payable {
//         // Fork from mainnet for testing with the deployed Supra Oracle
//         vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));

//         // Deploy the DateTime contract from src/DateTime.sol
//         dateTime = new DateTime();
//         vm.warp(dateTime.toTimestamp(2025, 3, 8, 10, 0, 0));

//         // Deploy the Spin contract
//         vm.prank(ADMIN);
//         spin = new Spin();

//         vm.prank(ADMIN);
//         spin.initialize(SUPRA_ORACLE, address(dateTime));

//         vm.prank(ADMIN);
//         spin.setCampaignStartDate();

//         vm.prank(SUPRA_OWNER);
//         IDepositContract(DEPOSIT_CONTRACT).addClientToWhitelist(ADMIN, true);

//         bool isWhitelisted = IDepositContract(DEPOSIT_CONTRACT).isClientWhitelisted(ADMIN);
//         assertTrue(isWhitelisted, "Spin contract is not whitelisted under ADMIN");

//         vm.deal(ADMIN, 1 ether);
//         vm.prank(ADMIN);
//         IDepositContract(DEPOSIT_CONTRACT).depositFundClient{ value: 0.1 ether }();

//         vm.prank(ADMIN);
//         IDepositContract(DEPOSIT_CONTRACT).addContractToWhitelist(address(spin));

//         vm.prank(SUPRA_OWNER);
//         bool isContractWhitelisted = IDepositContract(DEPOSIT_CONTRACT).isContractWhitelisted(ADMIN, address(spin));
//         assertTrue(isContractWhitelisted, "Spin contract is not whitelisted under ADMIN");

//         vm.prank(ADMIN);
//         IDepositContract(DEPOSIT_CONTRACT).setMinBalanceClient(0.05 ether);

//         vm.prank(SUPRA_OWNER);
//         uint256 effectiveBalance = IDepositContract(DEPOSIT_CONTRACT).checkEffectiveBalance(ADMIN);
//         assertGt(effectiveBalance, 0, "Insufficient balance in Supra Deposit Contract");

//         vm.prank(SUPRA_OWNER);
//         bool contractEligible = IDepositContract(DEPOSIT_CONTRACT).isContractEligible(ADMIN, address(spin));
//         assertTrue(contractEligible, "Spin contract is not eligible for VRF");

//         assertTrue(spin.hasRole(spin.DEFAULT_ADMIN_ROLE(), ADMIN), "ADMIN is not the contract admin");
//     }

//     function testStartSpin() public {
//         vm.recordLogs();

//         vm.warp(dateTime.toTimestamp(2025, 3, 10, 10, 0, 0));
//         vm.prank(USER);
//         spin.startSpin();

//         // Expect emit Spin requested
//         Vm.Log[] memory entries = vm.getRecordedLogs();
//         assertEq(entries.length, 2, "No logs emitted");

//         assertEq(entries[1].topics[0], keccak256("SpinRequested(uint256,address)"), "SpinRequested event not emitted");
//         assertEq(entries[1].topics[2], bytes32(uint256(uint160(USER))), "User address incorrect");

//         uint256 nonce = uint256(entries[0].topics[1]);
//         emit log_named_uint("Extracted Nonce", nonce);

//         assertGt(nonce, 0, "Nonce should be greater than 0");
//     }

//     function testVRFCallback() public {
//         // Start spin
//         vm.recordLogs();
//         vm.warp(dateTime.toTimestamp(2025, 3, 9, 10, 0, 0));
//         vm.prank(address(USER));
//         spin.startSpin();

//         Vm.Log[] memory entries = vm.getRecordedLogs();
//         uint256 nonce = uint256(entries[0].topics[1]);

//         uint256[] memory testRNG = new uint256[](1);
//         testRNG[0] = uint256(keccak256(abi.encodePacked(block.timestamp))) % 1_000_000;

//         vm.recordLogs();
//         vm.prank(SUPRA_ORACLE); // Simulate Supra calling
//         spin.handleRandomness(nonce, testRNG);
//         Vm.Log[] memory entries2 = vm.getRecordedLogs();
//         // Check if SpinCompleted event is emitted
//         assertEq(entries2.length, 1, "No logs emitted");
//         assertEq(
//             entries2[0].topics[0], keccak256("SpinCompleted(address,string,uint256)"), "SpinCompleted event not emitted"
//         );

//         emit log_named_string("Prize", abi.decode(entries2[0].data, (string)));
//     }

//     function testCooldownEnforcement() public {
//         // Start spin
//         vm.recordLogs();
//         vm.warp(dateTime.toTimestamp(2025, 3, 9, 10, 0, 0));
//         vm.prank(USER);
//         spin.startSpin();

//         Vm.Log[] memory entries1 = vm.getRecordedLogs();
//         uint256 nonce = uint256(entries1[0].topics[1]);

//         uint256[] memory testRNG = new uint256[](1);
//         testRNG[0] = uint256(keccak256(abi.encodePacked(block.timestamp))) % 1_000_000;

//         vm.prank(SUPRA_ORACLE); // Simulate Supra calling
//         spin.handleRandomness(nonce, testRNG);

//         // Attempt to spin again within cooldown period
//         vm.warp(dateTime.toTimestamp(2025, 3, 9, 14, 0, 0));
//         vm.expectRevert(abi.encodeWithSignature("AlreadySpunToday()"));
//         vm.prank(USER);
//         spin.startSpin();
//     }

//     function testSimulatePrizeHits() public {
//         uint256 baseTimestamp = dateTime.toTimestamp(2025, 3, 10, 10, 0, 0);
//         uint256 spinsPerDay = 100;
//         uint256 userSeed = 1;

//         // Simulate over 7 days
//         for (uint256 day = 1; day <= 7; day++) {
//             for (uint256 i = 0; i < spinsPerDay; i++) {
//                 address user = address(uint160(userSeed + i));
//                 uint256 hour = (i % 24); // spread spins over 24 hours
//                 uint256 minute = (i % 60);

//                 vm.recordLogs();
//                 uint256 ts = baseTimestamp + ((day - 1) * 1 days) + (hour * 1 hours) + (minute * 1 minutes);
//                 vm.warp(ts);

//                 vm.prank(user);
//                 spin.startSpin();
//                 Vm.Log[] memory entries1 = vm.getRecordedLogs();
//                 uint256 nonce = uint256(entries1[0].topics[1]);

//                 uint256[] memory testRNG = new uint256[](1);
//                 testRNG[0] = uint256(keccak256(abi.encodePacked(ts, user))) % 1_000_000;

//                 // Simulate Supra calling
//                 vm.recordLogs();
//                 vm.prank(SUPRA_ORACLE); // simulate Supra VRF callback
//                 spin.handleRandomness(nonce, testRNG);
//                 Vm.Log[] memory entries2 = vm.getRecordedLogs();

//                 string memory rewardCategory = abi.decode(entries2[0].data, (string));
//                 prizeCounts[keccak256(abi.encodePacked(rewardCategory))] += 1;
//             }

//             emit log_string("");
//             emit log_named_uint("Day", day);
//             emit log_named_uint("   Jackpot", prizeCounts[keccak256(abi.encodePacked("Jackpot"))]);
//             emit log_named_uint("   RaffleTicket", prizeCounts[keccak256(abi.encodePacked("Raffle Ticket"))]);
//             emit log_named_uint("   XP", prizeCounts[keccak256(abi.encodePacked("XP"))]);
//             emit log_named_uint("   PlumeToken", prizeCounts[keccak256(abi.encodePacked("Plume Token"))]);
//             emit log_named_uint("   Nothing", prizeCounts[keccak256(abi.encodePacked("Nothing"))]);

//             prizeCounts[keccak256(abi.encodePacked("Jackpot"))] = 0;
//             prizeCounts[keccak256(abi.encodePacked("Raffle Ticket"))] = 0;
//             prizeCounts[keccak256(abi.encodePacked("XP"))] = 0;
//             prizeCounts[keccak256(abi.encodePacked("Plume Token"))] = 0;
//             prizeCounts[keccak256(abi.encodePacked("Nothing"))] = 0;
//         }
//     }

//     function testStreakCount() public {
//         Vm.Log[] memory entries;

//         // Start spin 1
//         vm.recordLogs();
//         vm.warp(dateTime.toTimestamp(2025, 3, 10, 10, 0, 0));
//         vm.prank(address(USER));
//         spin.startSpin();

//         entries = vm.getRecordedLogs();
//         uint256 nonce = uint256(entries[0].topics[1]);

//         uint256[] memory testRNG = new uint256[](1);
//         testRNG[0] = uint256(keccak256(abi.encodePacked(block.timestamp))) % 1_000_000;

//         vm.prank(SUPRA_ORACLE);
//         spin.handleRandomness(nonce, testRNG);

//         // Start spin 2
//         vm.recordLogs();
//         vm.warp(dateTime.toTimestamp(2025, 3, 11, 10, 0, 0));
//         vm.prank(USER);
//         spin.startSpin();

//         entries = vm.getRecordedLogs();
//         nonce = uint256(entries[0].topics[1]);
//         testRNG[0] = uint256(keccak256(abi.encodePacked(block.timestamp))) % 1_000_000;

//         vm.prank(SUPRA_ORACLE);
//         spin.handleRandomness(nonce, testRNG);

//         // Streak count should be maintained till next day even if there is no spin on that day
//         vm.warp(dateTime.toTimestamp(2025, 3, 12, 23, 59, 59)); // Edge case
//         (uint256 streakCount,,,,,,) = spin.getUserData(USER);
//         assertEq(streakCount, 2, "Streak count should be 2");

//         // Streak breaks after 1 day of no spin
//         vm.warp(dateTime.toTimestamp(2025, 3, 13, 0, 0, 0)); // Edge case
//         (streakCount,,,,,,) = spin.getUserData(USER);
//         assertEq(streakCount, 0, "Streak count should be 0");
//     }

// }
