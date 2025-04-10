// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.25;

// import "../src/interfaces/ISupraRouterContract.sol";
// import "../src/spin/DateTime.sol";

// import "../src/spin/Raffle.sol";
// import "../src/spin/Spin.sol";
// import "forge-std/Test.sol";
// import "forge-std/console.sol";

// contract RaffleTest is Test {

//     Spin spin;
//     Raffle raffle;
//     ISupraRouterContract supraRouter;
//     DateTime dateTime;

//     address constant ADMIN = address(0x1);
//     address constant USER = address(0x2);
//     address constant SUPRA_ORACLE = address(0x6D46C098996AD584c9C40D6b4771680f54cE3726);
//     address constant DEPOSIT_CONTRACT = address(0x3B5F96986389f6BaCF58d5b69425fab000D3551e);
//     address constant SUPRA_OWNER = address(0x578DD059Ec425F83cCCC3149ed594d4e067A5307);

//     function setUp() public {
//         vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));

//         // Deploy the Spin contract
//         dateTime = new DateTime();

//         vm.warp(dateTime.toTimestamp(2025, 3, 10, 10, 0, 0));
//         vm.prank(ADMIN);
//         spin = new Spin();
//         spin.initialize(SUPRA_ORACLE, address(dateTime));

//         vm.prank(ADMIN);
//         raffle = new Raffle();

//         vm.prank(ADMIN);
//         raffle.initialize(address(spin), SUPRA_ORACLE);

//         assertTrue(raffle.hasRole(raffle.DEFAULT_ADMIN_ROLE(), ADMIN), "ADMIN is not the contract admin");
//     }

//     // function testInspectStorageSlots() public {
//     //     // Loop through a range of storage slots to find where userData is stored
//     //     bytes32 SPIN_STORAGE_LOCATION = 0x35fc247836aa7388208f5bf12c548be42b83fa7b653b6690498b1d90754d0b00;

//     //     console.log("Base storage location:", uint256(SPIN_STORAGE_LOCATION));

//     //     for (uint256 i = 0; i < 10; i++) {
//     //         bytes32 slot = bytes32(uint256(SPIN_STORAGE_LOCATION) + i);
//     //         bytes32 value = vm.load(address(spin), slot);
//     //         console.log("Slot", i, ":", uint256(value));
//     //     }

//     //     // Try a few different approaches for mapping access
//     //     bytes32 userDataMappingSlot = SPIN_STORAGE_LOCATION;
//     //     bytes32 userSlot = keccak256(abi.encode(USER, userDataMappingSlot));

//     //     console.log("User base slot:", uint256(userSlot));

//     //     // Check the first few slots of the user's data
//     //     for (uint256 i = 0; i < 10; i++) {
//     //         bytes32 slot = bytes32(uint256(userSlot) + i);
//     //         bytes32 value = vm.load(address(spin), slot);
//     //         console.log("User data slot", i, ":", uint256(value));
//     //     }
//     // }

//     function testSetRaffleTicketsViaStore() public {
//         vm.warp(dateTime.toTimestamp(2025, 3, 11, 10, 0, 0));
//         bytes32 SPIN_STORAGE_SLOT = 0x35fc247836aa7388208f5bf12c548be42b83fa7b653b6690498b1d90754d0b00;
//         address user = USER;

//         // Step 1: Offset of `userData` mapping inside SpinStorage struct
//         uint256 userDataFieldOffset = 2;

//         // Step 2: Hash for slot inside namespaced storage
//         bytes32 userDataSlot = keccak256(abi.encodePacked(bytes32(userDataFieldOffset), SPIN_STORAGE_SLOT));

//         // Step 3: Compute full key slot for user in mapping
//         bytes32 userSlot = keccak256(abi.encode(user, userDataSlot));

//         // Step 4: Field index 2 (raffleTicketsBalance) in UserData struct
//         // Stucts are packed in storage, so we need to calculate the exact slot
//         bytes32 raffleBalanceSlot = bytes32(uint256(userSlot) + 2);

//         // Step 5: Store raffle balance
//         vm.store(address(spin), raffleBalanceSlot, bytes32(uint256(1000)));

//         // Step 6: Check
//         (,,, uint256 raffleBal,,,) = spin.getUserData(user);
//         assertEq(raffleBal, 1000, "Raffle balance should be 1000");
//     }

// }
