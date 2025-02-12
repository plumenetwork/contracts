// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../src/interfaces/ISupraRouterContract.sol";
import "../src/spin/DateTime.sol";
import "../src/spin/Spin.sol";
import "forge-std/Test.sol";

interface IDepositContract {

    function addContractToWhitelist(
        address contractAddress
    ) external;
    function addClientToWhitelist(address clientAddress, bool snap) external;
    function depositFundClient() external payable;
    function isClientWhitelisted(address clientAddress) external view returns (bool);
    function isContractWhitelisted(address client ,address contractAddress) external view returns (bool);
    function checkEffectiveBalance(address clientAddress) external view returns (uint256);
    function isContractEligible(address client ,address contractAddress) external view returns (bool);
    function setMinBalanceClient(uint256 minBalance) external;

}

contract SpinTest is Test {

    Spin spin;
    ISupraRouterContract supraRouter;
    IDepositContract depositContract;
    DateTime dateTime;

    address constant ADMIN = address(0x1);
    address constant USER = address(0x2);
    address constant SUPRA_ORACLE = address(0x3280Ffd457A354E21A34F7Adf131136bD55E6596);
    address constant DEPOSIT_CONTRACT = address(0xBBcCF3Bb8733764674DE47Ff045e055cf76ADe1A);
    address constant SUPRA_OWNER = address(0x02340FDa8666c74d5B562F2b126C621240f1E819);

    uint256 constant COOLDOWN_PERIOD = 86_400; // 1 day
    uint8 constant RNG_COUNT = 1;
    uint256 constant NUM_CONFIRMATIONS = 1;

    function setUp() public payable {
        // Fork from mainnet for testing with the deployed Supra Oracle
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));

        // Deploy the DateTime contract from src/DateTime.sol
        dateTime = new DateTime();

        // Deploy the Spin contract
        vm.prank(ADMIN);
        spin = new Spin();

        vm.prank(ADMIN);
        spin.initialize(SUPRA_ORACLE, address(dateTime), COOLDOWN_PERIOD);

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
        (uint256 streak, uint256 feathers) = spin.getStreakAndFeathers(USER);
        assertEq(streak, 0, "Initial streak should be 0");
        assertEq(feathers, 0, "Initial feathers should be 0");

        vm.prank(USER);
        spin.startSpin();

    }

    function testCooldownEnforcement() public {
        // Start spin
        vm.prank(USER);
        spin.startSpin();

        // Attempt to spin again within cooldown period
        vm.warp(block.timestamp + 1000);
        vm.expectRevert(abi.encodeWithSignature("AlreadySpunToday()"));
        vm.prank(USER);
        spin.startSpin();
    }

}
