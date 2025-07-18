pragma solidity ^0.8.22;

import "forge-std/console.sol";

import { Packet } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import { MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { MessagingReceipt, OAppSender } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppSender.sol";
import { IOFT, SendParam, OFTReceipt } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import { TestHelper } from "./helpers/TestHelper.sol";

import { ArbNativeOFTAdapter } from "../src/L3/ArbNativeOFTAdapter.sol";
import { MockArbNativeOFTAdapter } from "./mocks/MockArbNativeOFTAdapter.sol";
import { MockOFT } from "./mocks/MockOFT.sol";
import { MockNativeTokenManager } from "./mocks/MockNativeTokenManager.sol";

contract NativeOFTAdapterMsgValueTransferTest is TestHelper {
    using OptionsBuilder for bytes;

    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint32 eid_a = 1;
    uint32 eid_b = 2;

    MockArbNativeOFTAdapter nativeOFTV2;
    MockOFT remoteOFTV2;
    MockNativeTokenManager mockNativeTokenManager = MockNativeTokenManager(address(0x73));

    function setUp() public virtual override {
        super.setUp();

        setUpEndpoints(2, LibraryType.UltraLightNode);

        MockNativeTokenManager _mockNativeTokenManager = new MockNativeTokenManager();
        vm.etch(address(mockNativeTokenManager), address(_mockNativeTokenManager).code);

        vm.startPrank(owner);

        nativeOFTV2 = new MockArbNativeOFTAdapter(18, endpoints[eid_a], owner);
        remoteOFTV2 = new MockOFT("MyToken", "MTK", endpoints[eid_b], owner);

        nativeOFTV2.setPeer(eid_b, bytes32(uint(uint160(address(remoteOFTV2)))));
        remoteOFTV2.setPeer(eid_a, bytes32(uint(uint160(address(nativeOFTV2)))));
        vm.stopPrank();
    }

    function test_constructor() public view {
        assertEq(nativeOFTV2.owner(), owner);
        assertEq(nativeOFTV2.token(), address(0));
        assertEq(nativeOFTV2.approvalRequired(), false);
    }

    function test_send_with_enough_native() public {
        uint256 initialAliceBalance = 20 ether;
        vm.deal(alice, initialAliceBalance);

        assertEq(mockNativeTokenManager.mintedAmount(), 0);
        assertEq(mockNativeTokenManager.burnedAmount(), 0);
        assertEq(remoteOFTV2.balanceOf(alice), 0);
        assertEq(address(nativeOFTV2).balance, 0);

        vm.startPrank(alice);
        uint256 totalAmount = 4 ether + 1 wei;
        uint256 totalAmountMinusDust = 4 ether;

        SendParam memory sendParam = SendParam(
            eid_b,
            addressToBytes32(alice),
            totalAmount,
            totalAmountMinusDust,
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0),
            "",
            ""
        );
        MessagingFee memory fee = nativeOFTV2.quoteSend(sendParam, false);
        uint256 messageValue = fee.nativeFee + totalAmountMinusDust;

        nativeOFTV2.send{ value: messageValue }(sendParam, fee, alice);
        verifyPackets(eid_b, addressToBytes32(address(remoteOFTV2)));

        assertEq(alice.balance, initialAliceBalance - totalAmountMinusDust - fee.nativeFee);
        assertEq(address(nativeOFTV2).balance, 0);
        assertEq(mockNativeTokenManager.mintedAmount(), 0);
        assertEq(mockNativeTokenManager.burnedAmount(), totalAmountMinusDust);
        assertEq(remoteOFTV2.balanceOf(alice), totalAmountMinusDust);
        assertEq(remoteOFTV2.totalSupply(), totalAmountMinusDust);
    }

    function test_send_from_main_to_other_chain_using_default() public {
        uint256 initialAliceBalance = 20 ether;
        uint256 initialBobBalance = 0 ether;
        deal(alice, initialAliceBalance);
        deal(bob, initialBobBalance);

        assertEq(mockNativeTokenManager.mintedAmount(), 0);
        assertEq(mockNativeTokenManager.burnedAmount(), 0);
        assertEq(remoteOFTV2.balanceOf(alice), 0);
        assertEq(address(nativeOFTV2).balance, 0);

        uint256 totalAmount = 8 ether;

        SendParam memory sendParam = SendParam(
            eid_b,
            addressToBytes32(alice),
            totalAmount,
            totalAmount,
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0),
            "",
            ""
        );
        MessagingFee memory fee = nativeOFTV2.quoteSend(sendParam, false);
        uint256 messageValue = fee.nativeFee + totalAmount;
        
        vm.prank(alice);
        nativeOFTV2.send{ value: messageValue }(sendParam, fee, alice);

        verifyPackets(eid_b, addressToBytes32(address(remoteOFTV2)));

        assertEq(alice.balance, initialAliceBalance - totalAmount - fee.nativeFee);
        assertEq(address(nativeOFTV2).balance, 0);
        assertEq(mockNativeTokenManager.mintedAmount(), 0);
        assertEq(mockNativeTokenManager.burnedAmount(), totalAmount);
        assertEq(remoteOFTV2.balanceOf(alice), totalAmount);
        assertEq(remoteOFTV2.totalSupply(), totalAmount);

        // second send

        SendParam memory sendParamSecondTx = SendParam(
            eid_a,
            addressToBytes32(bob),
            totalAmount,
            totalAmount,
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0),
            "",
            ""
        );
        MessagingFee memory feeSecondTx = remoteOFTV2.quoteSend(sendParamSecondTx, false);

        vm.prank(alice);
        remoteOFTV2.send{ value: feeSecondTx.nativeFee }(sendParamSecondTx, feeSecondTx, alice);

        verifyPackets(eid_a, addressToBytes32(address(nativeOFTV2)));

        assertEq(alice.balance, initialAliceBalance - totalAmount - fee.nativeFee - feeSecondTx.nativeFee);
        assertEq(bob.balance, totalAmount);
        assertEq(address(nativeOFTV2).balance, 0);
        assertEq(address(remoteOFTV2).balance, 0);
        assertEq(mockNativeTokenManager.mintedAmount(), totalAmount);
        assertEq(mockNativeTokenManager.burnedAmount(), totalAmount);
        assertEq(remoteOFTV2.balanceOf(alice), 0);
        assertEq(remoteOFTV2.balanceOf(bob), 0);
        assertEq(remoteOFTV2.totalSupply(), 0);
    }

    function test_send_reverts_when_incorrect_message_value_passed() public {
        uint256 initialAliceBalance = 20 ether;
        deal(alice, initialAliceBalance);

        assertEq(mockNativeTokenManager.mintedAmount(), 0);
        assertEq(mockNativeTokenManager.burnedAmount(), 0);
        assertEq(remoteOFTV2.balanceOf(alice), 0);
        assertEq(address(nativeOFTV2).balance, 0);
        assertEq(remoteOFTV2.totalSupply(), 0);

        uint256 totalAmount = 8 ether;
        uint256 extraAmount = 2 ether;

        SendParam memory sendParam = SendParam(
            eid_b,
            addressToBytes32(alice),
            totalAmount,
            totalAmount,
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0),
            "",
            ""
        );
        MessagingFee memory fee = nativeOFTV2.quoteSend(sendParam, false);
        uint256 messageValue = fee.nativeFee + totalAmount + extraAmount;

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ArbNativeOFTAdapter.IncorrectMessageValue.selector, messageValue, totalAmount + fee.nativeFee));
        nativeOFTV2.send{ value: messageValue }(sendParam, fee, alice);
    }

    function test_send_reverts_when_value_gt_fee_and_sender_balance_gt_send_amount() public {
        deal(alice, 10 ether);

        assertEq(mockNativeTokenManager.mintedAmount(), 0);
        assertEq(mockNativeTokenManager.burnedAmount(), 0);
        assertEq(address(nativeOFTV2).balance, 0);

        uint256 sendAmount = 2 ether;
        uint256 messageValue = 3 ether;

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            eid_b,
            addressToBytes32(bob),
            sendAmount,
            sendAmount,
            options,
            "",
            ""
        );
        MessagingFee memory fee = nativeOFTV2.quoteSend(sendParam, false);

        vm.expectRevert(
            abi.encodeWithSelector(ArbNativeOFTAdapter.IncorrectMessageValue.selector, messageValue, sendAmount + fee.nativeFee)
        );
        nativeOFTV2.send{ value: messageValue }(sendParam, fee, alice);
    }

    function test_native_oft_adapter_debit() public virtual {
        uint256 amountToSendLD = 1 ether;
        uint256 minAmountToCreditLD = 1 ether;
        uint32 dstEid = eid_b;

        deal(address(nativeOFTV2), amountToSendLD);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IOFT.SlippageExceeded.selector, amountToSendLD, minAmountToCreditLD + 1)
        );
        nativeOFTV2.debit(amountToSendLD, minAmountToCreditLD + 1, dstEid);

        vm.prank(alice);
        (uint256 amountDebitedLD, uint256 amountToCreditLD) = nativeOFTV2.debit(
            amountToSendLD,
            minAmountToCreditLD,
            dstEid
        );

        assertEq(amountDebitedLD, amountToSendLD);
        assertEq(amountToCreditLD, amountToSendLD);
        assertEq(mockNativeTokenManager.mintedAmount(), 0);
        assertEq(mockNativeTokenManager.burnedAmount(), amountToSendLD);
        assertEq(address(nativeOFTV2).balance, 0);
        assertEq(alice.balance, 0);
    }

}