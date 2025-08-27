pragma solidity ^0.8.22;

import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import { ArbNativeOFTAdapterUpgradeable } from "../contracts/plume/ArbNativeOFTAdapterUpgradeable.sol";
import { MockArbNativeOFTAdapterUpgradeable } from "./mocks/MockArbNativeOFTAdapterUpgradeable.sol";
import { MockOFT } from "./mocks/MockOFT.sol";
import { MockNativeTokenManager } from "./mocks/MockNativeTokenManager.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { MessagingFee, MessagingReceipt } from "@layerzerolabs/oft-evm/contracts/OFTCore.sol";
import { SendParam, OFTReceipt, IOFT } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";


contract ArbNativeOFTAdapterUpgradeableTest is TestHelperOz5 {
    using OptionsBuilder for bytes;

    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address public proxyAdmin = makeAddr("proxyAdmin");

    uint32 eid_a = 1;
    uint32 eid_b = 2;

    MockArbNativeOFTAdapterUpgradeable adapter;
    MockOFT remoteOFT;
    MockNativeTokenManager mockNativeTokenManager = MockNativeTokenManager(address(0x73));

    function _deployContractAndProxy(
        bytes memory _oappBytecode,
        bytes memory _constructorArgs,
        bytes memory _initializeArgs
    ) internal returns (address addr) {
        bytes memory bytecode = bytes.concat(abi.encodePacked(_oappBytecode), _constructorArgs);
        assembly {
            addr := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }

        return address(new TransparentUpgradeableProxy(addr, proxyAdmin, _initializeArgs));
    }

    function setUp() public virtual override {
        super.setUp();

        setUpEndpoints(2, LibraryType.UltraLightNode);

        MockNativeTokenManager logic = new MockNativeTokenManager();
        vm.etch(address(mockNativeTokenManager), address(logic).code);

        vm.deal(owner, 1000 ether);

        bytes memory constructorArgs = abi.encode(uint8(18), address(endpoints[eid_a]));

        bytes memory initializeArgs = abi.encodeWithSelector(
            MockArbNativeOFTAdapterUpgradeable.initialize.selector,
            owner
        );

        address proxyAddr = _deployContractAndProxy(
            type(MockArbNativeOFTAdapterUpgradeable).creationCode,
            constructorArgs,
            initializeArgs
        );

        adapter = MockArbNativeOFTAdapterUpgradeable(proxyAddr);
        remoteOFT = new MockOFT("MyToken", "MTK", endpoints[eid_b], owner);

        vm.startPrank(owner);
        adapter.setPeer(eid_b, addressToBytes32(address(remoteOFT)));
        remoteOFT.setPeer(eid_a, addressToBytes32(address(adapter)));
        vm.stopPrank();
    }

    function test_initialize_works() view public {
        assertEq(adapter.owner(), owner);
        assertEq(adapter.token(), address(0));
        assertEq(adapter.approvalRequired(), false);
    }

    function test_send_with_enough_native() public {
        uint256 initialAliceBalance = 20 ether;
        vm.deal(alice, initialAliceBalance);

        assertEq(mockNativeTokenManager.mintedAmount(), 0);
        assertEq(mockNativeTokenManager.burnedAmount(), 0);
        assertEq(remoteOFT.balanceOf(alice), 0);
        assertEq(address(adapter).balance, 0);

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

        MessagingFee memory fee = adapter.quoteSend(sendParam, false);
        uint256 messageValue = fee.nativeFee + totalAmountMinusDust;

        adapter.send{ value: messageValue }(sendParam, fee, alice);
        verifyPackets(eid_b, addressToBytes32(address(remoteOFT)));

        vm.stopPrank();

        assertEq(alice.balance, initialAliceBalance - totalAmountMinusDust - fee.nativeFee);
        assertEq(address(adapter).balance, 0);
        assertEq(mockNativeTokenManager.mintedAmount(), 0);
        assertEq(mockNativeTokenManager.burnedAmount(), totalAmountMinusDust);
        assertEq(remoteOFT.balanceOf(alice), totalAmountMinusDust);
        assertEq(remoteOFT.totalSupply(), totalAmountMinusDust);
    }


    function test_send_from_main_to_other_chain_using_upgradeable_adapter() public {
        uint256 initialAliceBalance = 20 ether;
        uint256 initialBobBalance = 0 ether;
        deal(alice, initialAliceBalance);
        deal(bob, initialBobBalance);

        assertEq(mockNativeTokenManager.mintedAmount(), 0);
        assertEq(mockNativeTokenManager.burnedAmount(), 0);
        assertEq(remoteOFT.balanceOf(alice), 0);
        assertEq(address(adapter).balance, 0);

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
        MessagingFee memory fee = adapter.quoteSend(sendParam, false);
        uint256 messageValue = fee.nativeFee + totalAmount;

        vm.prank(alice);
        adapter.send{ value: messageValue }(sendParam, fee, alice);

        verifyPackets(eid_b, addressToBytes32(address(remoteOFT)));

        assertEq(alice.balance, initialAliceBalance - totalAmount - fee.nativeFee);
        assertEq(address(adapter).balance, 0);
        assertEq(mockNativeTokenManager.mintedAmount(), 0);
        assertEq(mockNativeTokenManager.burnedAmount(), totalAmount);
        assertEq(remoteOFT.balanceOf(alice), totalAmount);
        assertEq(remoteOFT.totalSupply(), totalAmount);

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
        MessagingFee memory feeSecondTx = remoteOFT.quoteSend(sendParamSecondTx, false);

        vm.prank(alice);
        remoteOFT.send{ value: feeSecondTx.nativeFee }(sendParamSecondTx, feeSecondTx, alice);

        verifyPackets(eid_a, addressToBytes32(address(adapter)));

        assertEq(alice.balance, initialAliceBalance - totalAmount - fee.nativeFee - feeSecondTx.nativeFee);
        assertEq(bob.balance, totalAmount);
        assertEq(address(adapter).balance, 0);
        assertEq(address(remoteOFT).balance, 0);
        assertEq(mockNativeTokenManager.mintedAmount(), totalAmount);
        assertEq(mockNativeTokenManager.burnedAmount(), totalAmount);
        assertEq(remoteOFT.balanceOf(alice), 0);
        assertEq(remoteOFT.balanceOf(bob), 0);
        assertEq(remoteOFT.totalSupply(), 0);
    }

    function test_send_reverts_when_incorrect_message_value_passed() public {
        uint256 initialAliceBalance = 20 ether;
        deal(alice, initialAliceBalance);

        assertEq(mockNativeTokenManager.mintedAmount(), 0);
        assertEq(mockNativeTokenManager.burnedAmount(), 0);
        assertEq(remoteOFT.balanceOf(alice), 0);
        assertEq(address(adapter).balance, 0);
        assertEq(remoteOFT.totalSupply(), 0);

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
        MessagingFee memory fee = adapter.quoteSend(sendParam, false);
        uint256 messageValue = fee.nativeFee + totalAmount + extraAmount;

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                ArbNativeOFTAdapterUpgradeable.IncorrectMessageValue.selector,
                messageValue,
                totalAmount + fee.nativeFee
            )
        );
        adapter.send{ value: messageValue }(sendParam, fee, alice);
    }

    function test_send_reverts_when_value_gt_fee_and_sender_balance_gt_send_amount() public {
        deal(alice, 10 ether);

        assertEq(mockNativeTokenManager.mintedAmount(), 0);
        assertEq(mockNativeTokenManager.burnedAmount(), 0);
        assertEq(address(adapter).balance, 0);

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
        MessagingFee memory fee = adapter.quoteSend(sendParam, false);

        vm.expectRevert(
            abi.encodeWithSelector(
                ArbNativeOFTAdapterUpgradeable.IncorrectMessageValue.selector,
                messageValue,
                sendAmount + fee.nativeFee
            )
        );
        vm.prank(alice);
        adapter.send{ value: messageValue }(sendParam, fee, alice);
    }

    function test_native_oft_adapter_debit() public {
        uint256 amountToSendLD = 1 ether;
        uint256 minAmountToCreditLD = 1 ether;
        uint32 dstEid = eid_b;

        deal(address(adapter), amountToSendLD);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IOFT.SlippageExceeded.selector, amountToSendLD, minAmountToCreditLD + 1)
        );
        adapter.debit(alice, amountToSendLD, minAmountToCreditLD + 1, dstEid);

        vm.prank(alice);
        (uint256 amountDebitedLD, uint256 amountToCreditLD) = adapter.debit(
            alice,
            amountToSendLD,
            minAmountToCreditLD,
            dstEid
        );

        assertEq(amountDebitedLD, amountToSendLD);
        assertEq(amountToCreditLD, amountToSendLD);
        assertEq(mockNativeTokenManager.mintedAmount(), 0);
        assertEq(mockNativeTokenManager.burnedAmount(), amountToSendLD);
        assertEq(address(adapter).balance, 0);
        assertEq(alice.balance, 0);
    }
}