pragma solidity ^0.8.22;

import { Packet } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { MessagingFee, MessagingReceipt } from "@layerzerolabs/oft-evm/contracts/OFTCore.sol";
import { OAppSender } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";
import { SendParam, OFTReceipt, IOFT } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { IUpgradeExecutor } from "@offchainlabs/upgrade-executor/src/IUpgradeExecutor.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { ITransparentUpgradeableProxy, TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { GasToken } from "./mocks/GasToken.sol";
import { OrbitERC20OFTAdapterUpgradeable } from "../../contracts/ethereum/OrbitERC20OFTAdapterUpgradeable.sol";
import { IBridge } from "../../contracts/ethereum/bridge/IBridge.sol";
import { ERC20Bridge } from "./bridge/ERC20Bridge.sol";
import { IOwnable } from "../../contracts/ethereum/bridge/IOwnable.sol";
import { ISequencerInbox } from "./bridge/ISequencerInbox.sol";
import { SimpleProxy } from "./mocks/SimpleProxy.sol";
import { BridgeStub } from "./mocks/BridgeStub.sol";
import { RollupStub } from "./mocks/RollupStub.sol";
import { UpgradeExecutorMock } from "./mocks/UpgradeExecutorMock.sol";
import { OrbitNativeOFTAdapterUpgradeable } from "../../contracts/plume/OrbitNativeOFTAdapterUpgradeable.sol";
import { IDelayedMessageProvider } from "./bridge/IDelayedMessageProvider.sol";
import { MockNativeTokenManager } from "./mocks/MockNativeTokenManager.sol";

import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

import "forge-std/console.sol";

contract EthToPlumeFlowTest is TestHelperOz5 {
    using OptionsBuilder for bytes;

    address rollupOwner = makeAddr("rollupOwner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint32 ETH_Eid = 1;
    uint32 PLUME_Eid = 2;

    // ETH
    OrbitERC20OFTAdapterUpgradeable    ethAdapter;
    GasToken                gasToken;
    IUpgradeExecutor        ethUpgradeExecutor;

    // PLUME
    OrbitNativeOFTAdapterUpgradeable   plumeAdapter;
    MockNativeTokenManager  mockNativeTokenManager = MockNativeTokenManager(address(0x73));

    uint256 gasTokenSupply = 100 ether;

    /// @notice Calls setUp from TestHelper and initializes contract instances for testing.
    function setUp() public virtual override {
        super.setUp();

        // Setup function to initialize 2 Mock Endpoints with Mock MessageLib.
        setUpEndpoints(2, LibraryType.UltraLightNode);

        MockNativeTokenManager _mockNativeTokenManager = new MockNativeTokenManager();
        vm.etch(address(mockNativeTokenManager), address(_mockNativeTokenManager).code);

        // ETH
        address endpointETH = endpoints[ETH_Eid];
        
        vm.startPrank(rollupOwner);
        gasToken = new GasToken("GasToken", "GTK");

        address[] memory executors = new address[](1);
        executors[0] = rollupOwner;

        ProxyAdmin proxyAdmin = new ProxyAdmin(rollupOwner);
        ethUpgradeExecutor = new UpgradeExecutorMock();
        TransparentUpgradeableProxy transparentProxy = new TransparentUpgradeableProxy(
            address(ethUpgradeExecutor),
            address(proxyAdmin),
            abi.encodeWithSelector(UpgradeExecutorMock.initialize.selector, rollupOwner, executors)
        );
        ethUpgradeExecutor = IUpgradeExecutor(address(transparentProxy));

        bool isRollupOwnerExecutor = IAccessControl(address(ethUpgradeExecutor)).hasRole(keccak256("EXECUTOR_ROLE"), rollupOwner);
        if (!isRollupOwnerExecutor) {
            revert("!isRollupOwnerExecutor");
        }

        RollupStub rollup = new RollupStub(address(ethUpgradeExecutor));

        ERC20Bridge ethBridge = new ERC20Bridge();
        SimpleProxy ethBridgeProxy = new SimpleProxy(address(ethBridge));
        ethBridge = ERC20Bridge(address(ethBridgeProxy));
        ethBridge.initialize(rollup, address(gasToken));

        // Deploy logic
        OrbitERC20OFTAdapterUpgradeable ethLogic = new OrbitERC20OFTAdapterUpgradeable(address(gasToken), endpointETH, ethBridge);

        // Deploy proxy
        TransparentUpgradeableProxy ethProxy = new TransparentUpgradeableProxy(
            address(ethLogic),
            address(proxyAdmin),
            abi.encodeWithSelector(OrbitERC20OFTAdapterUpgradeable.initialize.selector, rollupOwner)
        );

        // Use the proxy address as the adapter instance
        ethAdapter = OrbitERC20OFTAdapterUpgradeable(address(ethProxy));

        // PLUME
        address endpointPLUME = endpoints[PLUME_Eid];

        // Deploy the logic contract (constructor will call _disableInitializers())
        OrbitNativeOFTAdapterUpgradeable plumeLogic = new OrbitNativeOFTAdapterUpgradeable(18, endpointPLUME);

        // Deploy the proxy, initializing through the constructor
        TransparentUpgradeableProxy plumeProxy = new TransparentUpgradeableProxy(
            address(plumeLogic),
            address(proxyAdmin),
            abi.encodeWithSelector(OrbitNativeOFTAdapterUpgradeable.initialize.selector, rollupOwner)
        );

        // Cast the proxy address to the adapter interface
        plumeAdapter = OrbitNativeOFTAdapterUpgradeable(address(plumeProxy));
        address plumeAdapterAddress = address(plumeAdapter);

        // ETH
        gasToken.mint(address(ethBridge), gasTokenSupply);
        ethUpgradeExecutor.executeCall(address(ethBridge), abi.encodeWithSelector(ethBridge.setOutbox.selector, address(ethAdapter), true));

        ethAdapter.setPeer(PLUME_Eid, bytes32(uint(uint160(plumeAdapterAddress))));
        plumeAdapter.setPeer(ETH_Eid, bytes32(uint(uint160(address(ethAdapter)))));
        vm.stopPrank();

        assertEq(gasToken.balanceOf(rollupOwner), 0);
        assertEq(address(plumeAdapter).balance, 0, "PLUME adapter balance has to be 0 because it uses mint burn");
    }

    function test_send_eth_to_plume_different_account() public {
        uint256 tokensToSend = 1 ether;
        uint256 initialNativeBalance = 1 ether;

        vm.deal(alice, initialNativeBalance);

        vm.prank(rollupOwner);
        gasToken.mint(alice, tokensToSend);

        assertEq(gasToken.balanceOf(alice), tokensToSend);
        assertEq(alice.balance, initialNativeBalance);

        vm.startPrank(alice);
        gasToken.approve(address(ethAdapter), tokensToSend);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            PLUME_Eid,
            addressToBytes32(bob),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );
        MessagingFee memory fee = ethAdapter.quoteSend(sendParam, false);

        ethAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);

        vm.stopPrank();

        verifyPackets(PLUME_Eid, addressToBytes32(address(plumeAdapter)));

        assertEq(gasToken.balanceOf(alice), 0);
        assertEq(alice.balance, initialNativeBalance - fee.nativeFee);
        assertEq(bob.balance, tokensToSend);
    }

    function test_send_eth_to_plume_same_account() public {
        uint256 tokensToSend = 1 ether;
        uint256 initialNativeBalance = 1 ether;

        vm.deal(rollupOwner, initialNativeBalance);

        vm.prank(rollupOwner);
        gasToken.mint(rollupOwner, tokensToSend);

        assertEq(gasToken.balanceOf(rollupOwner), tokensToSend);
        assertEq(rollupOwner.balance, initialNativeBalance);

        vm.startPrank(rollupOwner);
        gasToken.approve(address(ethAdapter), tokensToSend);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            PLUME_Eid,
            addressToBytes32(rollupOwner),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );
        MessagingFee memory fee = ethAdapter.quoteSend(sendParam, false);

        ethAdapter.send{ value: fee.nativeFee }(sendParam, fee, rollupOwner);

        vm.stopPrank();

        verifyPackets(PLUME_Eid, addressToBytes32(address(plumeAdapter)));

        assertEq(gasToken.balanceOf(rollupOwner), 0);
        assertEq(rollupOwner.balance, initialNativeBalance - fee.nativeFee + tokensToSend);
    }

    function test_send_plume_to_eth() public {
        uint256 tokensToSend = 1 ether;
        uint256 initialNativeBalance = 2 ether;

        deal(alice, initialNativeBalance);

        assertEq(gasToken.balanceOf(alice), 0);
        assertEq(gasToken.balanceOf(bob), 0);
        assertEq(alice.balance, initialNativeBalance);
        assertEq(bob.balance, 0);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            ETH_Eid,
            addressToBytes32(bob),
            tokensToSend,
            tokensToSend,
            options,
            "",
            ""
        );
        MessagingFee memory fee = plumeAdapter.quoteSend(sendParam, false);

        vm.prank(alice);
        plumeAdapter.send{ value: tokensToSend + fee.nativeFee }(sendParam, fee, alice);

        verifyPackets(ETH_Eid, addressToBytes32(address(ethAdapter)));

        assertEq(gasToken.balanceOf(alice), 0);
        assertEq(gasToken.balanceOf(bob), tokensToSend);
        assertEq(address(plumeAdapter).balance, 0);
        assertEq(mockNativeTokenManager.mintedAmount(), 0);
        assertEq(mockNativeTokenManager.burnedAmount(), tokensToSend);
        assertEq(alice.balance, initialNativeBalance - tokensToSend - fee.nativeFee);
        assertEq(bob.balance, 0);
    }
}