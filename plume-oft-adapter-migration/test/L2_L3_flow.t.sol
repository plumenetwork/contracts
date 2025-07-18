pragma solidity ^0.8.22;

import { Packet } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import { MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { MessagingReceipt, OAppSender } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppSender.sol";
import { IOFT, SendParam, OFTReceipt } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import { IUpgradeExecutor } from "@offchainlabs/upgrade-executor/src/IUpgradeExecutor.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { ITransparentUpgradeableProxy, TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { IAccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol";

import { GasToken } from "../src/L2/GasToken.sol";
import { OrbitERC20OFTAdapter } from "../src/L2/OrbitERC20OFTAdapter.sol";
import { IBridge } from "../src/L2/bridge/IBridge.sol";
import { ERC20Bridge } from "../src/L2/bridge/ERC20Bridge.sol";
import { IOwnable } from "../src/L2/bridge/IOwnable.sol";
import { ISequencerInbox } from "../src/L2/bridge/ISequencerInbox.sol";
import { SimpleProxy } from "../src/L2/mocks/SimpleProxy.sol";
import { BridgeStub } from "../src/L2/mocks/BridgeStub.sol";
import { RollupStub } from "../src/L2/mocks/RollupStub.sol";
import { UpgradeExecutorMock } from "../src/L2/mocks/UpgradeExecutorMock.sol";
import { OrbitNativeOFTAdapter } from "../src/L3/OrbitNativeOFTAdapter.sol";
import { IDelayedMessageProvider } from "../src/L2/bridge/IDelayedMessageProvider.sol";
import { TestHelper } from "./helpers/TestHelper.sol";
import { MockNativeTokenManager } from "./mocks/MockNativeTokenManager.sol";

import "forge-std/console.sol";

contract L2ToL3FlowTest is TestHelper {
    using OptionsBuilder for bytes;

    address rollupOwner = makeAddr("rollupOwner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint32 L2_Eid = 1;
    uint32 L3_Eid = 2;

    // L2
    OrbitERC20OFTAdapter    l2Adapter;
    GasToken                gasToken;
    IUpgradeExecutor        l2UpgradeExecutor;

    // L3
    OrbitNativeOFTAdapter   l3Adapter;
    MockNativeTokenManager  mockNativeTokenManager = MockNativeTokenManager(address(0x73));

    uint256 gasTokenSupply = 100 ether;

    /// @notice Calls setUp from TestHelper and initializes contract instances for testing.
    function setUp() public virtual override {
        super.setUp();

        // Setup function to initialize 2 Mock Endpoints with Mock MessageLib.
        setUpEndpoints(2, LibraryType.UltraLightNode);

        MockNativeTokenManager _mockNativeTokenManager = new MockNativeTokenManager();
        vm.etch(address(mockNativeTokenManager), address(_mockNativeTokenManager).code);

        // L2
        address endpointL2 = endpoints[L2_Eid];
        
        vm.startPrank(rollupOwner);
        gasToken = new GasToken("GasToken", "GTK");

        address[] memory executors = new address[](1);
        executors[0] = rollupOwner;

        ProxyAdmin proxyAdmin = new ProxyAdmin();
        l2UpgradeExecutor = new UpgradeExecutorMock();
        TransparentUpgradeableProxy transparentProxy = new TransparentUpgradeableProxy(
            address(l2UpgradeExecutor),
            address(proxyAdmin),
            abi.encodeWithSelector(UpgradeExecutorMock.initialize.selector, rollupOwner, executors)
        );
        l2UpgradeExecutor = IUpgradeExecutor(address(transparentProxy));

        bool isRollupOwnerExecutor = IAccessControlUpgradeable(address(l2UpgradeExecutor)).hasRole(keccak256("EXECUTOR_ROLE"), rollupOwner);
        if (!isRollupOwnerExecutor) {
            revert("!isRollupOwnerExecutor");
        }

        RollupStub rollup = new RollupStub(address(l2UpgradeExecutor));

        ERC20Bridge l2Bridge = new ERC20Bridge();
        SimpleProxy l2BridgeProxy = new SimpleProxy(address(l2Bridge));
        l2Bridge = ERC20Bridge(address(l2BridgeProxy));
        l2Bridge.initialize(rollup, address(gasToken));

        l2Adapter = new OrbitERC20OFTAdapter(address(gasToken), endpointL2, rollupOwner, l2Bridge);

        // L3
        address endpointL3 = endpoints[L3_Eid];
        l3Adapter = new OrbitNativeOFTAdapter(18, endpointL3, rollupOwner);
        address l3AdapterAddress = address(l3Adapter);

        // L2
        gasToken.mint(address(l2Bridge), gasTokenSupply);
        l2UpgradeExecutor.executeCall(address(l2Bridge), abi.encodeWithSelector(l2Bridge.setOutbox.selector, address(l2Adapter), true));

        l2Adapter.setPeer(L3_Eid, bytes32(uint(uint160(l3AdapterAddress))));
        l3Adapter.setPeer(L2_Eid, bytes32(uint(uint160(address(l2Adapter)))));
        vm.stopPrank();

        assertEq(gasToken.balanceOf(rollupOwner), 0);
        assertEq(address(l3Adapter).balance, 0, "L3 adapter balance has to be 0 because it uses mint burn");
    }

    function test_send_l2_to_l3_different_account() public {
        uint256 tokensToSend = 1 ether;
        uint256 initialNativeBalance = 1 ether;

        vm.deal(alice, initialNativeBalance);

        vm.prank(rollupOwner);
        gasToken.mint(alice, tokensToSend);

        assertEq(gasToken.balanceOf(alice), tokensToSend);
        assertEq(alice.balance, initialNativeBalance);

        vm.startPrank(alice);
        gasToken.approve(address(l2Adapter), tokensToSend);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            L3_Eid,
            addressToBytes32(bob),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );
        MessagingFee memory fee = l2Adapter.quoteSend(sendParam, false);

        l2Adapter.send{ value: fee.nativeFee }(sendParam, fee, alice);

        vm.stopPrank();

        verifyPackets(L3_Eid, addressToBytes32(address(l3Adapter)));

        assertEq(gasToken.balanceOf(alice), 0);
        assertEq(alice.balance, initialNativeBalance - fee.nativeFee);
        assertEq(bob.balance, tokensToSend);
    }

    function test_send_l2_to_l3_same_account() public {
        uint256 tokensToSend = 1 ether;
        uint256 initialNativeBalance = 1 ether;

        vm.deal(rollupOwner, initialNativeBalance);

        vm.prank(rollupOwner);
        gasToken.mint(rollupOwner, tokensToSend);

        assertEq(gasToken.balanceOf(rollupOwner), tokensToSend);
        assertEq(rollupOwner.balance, initialNativeBalance);

        vm.startPrank(rollupOwner);
        gasToken.approve(address(l2Adapter), tokensToSend);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            L3_Eid,
            addressToBytes32(rollupOwner),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );
        MessagingFee memory fee = l2Adapter.quoteSend(sendParam, false);

        l2Adapter.send{ value: fee.nativeFee }(sendParam, fee, rollupOwner);

        vm.stopPrank();

        verifyPackets(L3_Eid, addressToBytes32(address(l3Adapter)));

        assertEq(gasToken.balanceOf(rollupOwner), 0);
        assertEq(rollupOwner.balance, initialNativeBalance - fee.nativeFee + tokensToSend);
    }

    function test_send_l3_to_l2() public {
        uint256 tokensToSend = 1 ether;
        uint256 initialNativeBalance = 2 ether;

        deal(alice, initialNativeBalance);

        assertEq(gasToken.balanceOf(alice), 0);
        assertEq(gasToken.balanceOf(bob), 0);
        assertEq(alice.balance, initialNativeBalance);
        assertEq(bob.balance, 0);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            L2_Eid,
            addressToBytes32(bob),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );
        MessagingFee memory fee = l3Adapter.quoteSend(sendParam, false);

        vm.prank(alice);
        l3Adapter.send{ value: tokensToSend + fee.nativeFee }(sendParam, fee, alice);

        verifyPackets(L2_Eid, addressToBytes32(address(l2Adapter)));

        assertEq(gasToken.balanceOf(alice), 0);
        assertEq(gasToken.balanceOf(bob), tokensToSend);
        assertEq(address(l3Adapter).balance, 0);
        assertEq(mockNativeTokenManager.mintedAmount(), 0);
        assertEq(mockNativeTokenManager.burnedAmount(), tokensToSend);
        assertEq(alice.balance, initialNativeBalance - tokensToSend - fee.nativeFee);
        assertEq(bob.balance, 0);
    }
}