// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { pUSD } from "../src/token/pUSD.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { MockAccountantWithRateProviders } from "../src/mocks/MockAccountantWithRateProviders.sol";
import { MockAtomicQueue } from "../src/mocks/MockAtomicQueue.sol";
import { MockLens } from "../src/mocks/MockLens.sol";
import { MockTeller } from "../src/mocks/MockTeller.sol";

import { IBoringVault } from "../src/interfaces/IBoringVault.sol";
import { IBoringVaultAdapter } from "../src/interfaces/IBoringVaultAdapter.sol";
import { BoringVaultAdapter } from "../src/token/BoringVaultAdapter.sol";

import { MockUSDC } from "../src/mocks/MockUSDC.sol";
import { MockVault } from "../src/mocks/MockVault.sol";
import { pUSD } from "../src/token/pUSD.sol";

import { OFTCore } from "@layerzerolabs/oft-evm/contracts/OFTCore.sol";
import { SendParam, MessagingFee } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { ILayerZeroEndpointV2 } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { SetConfigParam } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";


interface BoringVault {

    function enter(address from, IERC20 asset, uint256 assetAmount, address to, uint256 shareAmount) external;

}

contract pUSD_LZTest is Test {

    // Constants for LayerZero on ETH mainnet
    address constant ETH_LZ_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    address constant ETH_LZ_DELEGATE = 0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1;

    // Constants for LayerZero on Plume mainnet
    address constant PLUME_LZ_ENDPOINT = 0x6F475642a6e85809B1c36Fa62763669b1b48DD5B;
    address constant PLUME_LZ_DELEGATE = 0xC39161c743D0307EB9BCc9FEF03eeb9Dc4802de7;

    // Constants for LayerZero EID's
    uint16 constant PLUME_EID = 30_318;
    uint16 constant ETH_EID = 1;

    // USDC addresses
    address constant ETH_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant PLUME_USDC = 0x3938A812c54304fEffD266C7E2E70B48F9475aD6;

    //pUSD addresses
    address constant ETH_pUSD = 0xdddD73F5Df1F0DC31373357beAC77545dC5A6f3F;
    address constant PLUME_pUSD = 0x360822f796975cEccD8095c10720c57567b4199f;

    // Boring Vault contracts on plume mainnet
    address private constant VAULT_TOKEN = 0xdddD73F5Df1F0DC31373357beAC77545dC5A6f3F;
    address private constant ATOMIC_QUEUE = 0x7f69e1A09472EEb7a5dA7552bD59Ca022c341193;
    address private constant TELLER_ADDRESS = 0x16424eDF021697E34b800e1D98857536B0f2287B;
    address private constant LENS_ADDRESS = 0x3D2021776e385601857E7b7649de955525E21d23;
    address private constant ACCOUNTANT_ADDRESS = 0xbB2fAA1e1D6183EE3c4177476ce0d70CBd55A388;

    string PLUME_MAINNET_RPC = vm.envString("PLUME_MAINNET_RPC");
    string ETH_MAINNET_RPC = vm.envString("ETH_MAINNET_RPC");

    uint256 ethMainnetFork;
    uint256 plumeMainnetFork;

    address owner;
    address user;

    pUSD ethImplementation;
    pUSD plumeImplementation;
    pUSD ethProxy;
    pUSD plumeProxy;

    // Interfaces for vault and OFT functionality
    IBoringVaultAdapter ethVault;
    IBoringVaultAdapter plumeVault;
    OFTCore ethOFT;
    OFTCore plumeOFT;

function setUp() public {
    // Create forks
    ethMainnetFork = vm.createFork(vm.envString("ETH_MAINNET_RPC"));
    plumeMainnetFork = vm.createFork(vm.envString("PLUME_MAINNET_RPC"));

    // Create users
    owner = makeAddr("owner");
    user = makeAddr("user");

    // Deploy on ETH mainnet
    vm.selectFork(ethMainnetFork);
    ethImplementation = new pUSD(
        ETH_LZ_ENDPOINT,
        ETH_LZ_DELEGATE,
        owner
    );
    vm.makePersistent(address(ethImplementation));

    // Deploy and initialize ETH proxy
    ERC1967Proxy ethProxyContract = new ERC1967Proxy(
        address(ethImplementation),
        abi.encodeCall(
            pUSD.initialize,
            (
                owner,
                IERC20(ETH_USDC),
                VAULT_TOKEN,
                TELLER_ADDRESS,
                ATOMIC_QUEUE,
                LENS_ADDRESS,
                ACCOUNTANT_ADDRESS,
                ETH_LZ_ENDPOINT,
                ETH_EID
            )
        )
    );
    ethProxy = pUSD(address(ethProxyContract));

    // Make ETH contracts and endpoints persistent on ETH fork
    vm.makePersistent(address(ethProxy));
    vm.makePersistent(address(ethProxyContract));
    vm.makePersistent(ETH_LZ_ENDPOINT);

    // Deploy on Plume
    vm.selectFork(plumeMainnetFork);
    plumeImplementation = new pUSD(
        PLUME_LZ_ENDPOINT,
        PLUME_LZ_DELEGATE,
        owner
    );
    vm.makePersistent(address(plumeImplementation));

    // Deploy and initialize Plume proxy
    ERC1967Proxy plumeProxyContract = new ERC1967Proxy(
        address(plumeImplementation),
        abi.encodeCall(
            pUSD.initialize,
            (
                owner,
                IERC20(PLUME_USDC),
                VAULT_TOKEN,
                TELLER_ADDRESS,
                ATOMIC_QUEUE,
                LENS_ADDRESS,
                ACCOUNTANT_ADDRESS,
                PLUME_LZ_ENDPOINT,
                PLUME_EID
            )
        )
    );
    plumeProxy = pUSD(address(plumeProxyContract));

    // Make Plume contracts and endpoints persistent on Plume fork
    vm.makePersistent(address(plumeProxy));
    vm.makePersistent(address(plumeProxyContract));
    vm.makePersistent(PLUME_LZ_ENDPOINT);

    // Make contracts persistent on opposite forks
    vm.selectFork(ethMainnetFork);
    vm.makePersistent(address(plumeProxy));
    vm.makePersistent(PLUME_LZ_ENDPOINT);
    
    vm.selectFork(plumeMainnetFork);
    vm.makePersistent(address(ethProxy));
    vm.makePersistent(ETH_LZ_ENDPOINT);

    // Cast proxies to both interfaces
    ethVault = IBoringVaultAdapter(address(ethProxy));
    plumeVault = IBoringVaultAdapter(address(plumeProxy));
    ethOFT = OFTCore(address(ethProxy));
    plumeOFT = OFTCore(address(plumeProxy));

    vm.selectFork(ethMainnetFork);
    vm.startPrank(owner);
    
    // On ETH chain, set Plume as peer
    bytes32 plumePeer = bytes32(uint256(uint160(address(plumeProxy))));
    ethOFT.setPeer(PLUME_EID, plumePeer);

    // Configure DVN for ETH -> Plume path
    SetConfigParam[] memory params = new SetConfigParam[](1);
    params[0] = SetConfigParam({
        lib: address(ethOFT),
        config: abi.encode(
            uint8(1),           // number of confirmations required
            address(0),         // optional oracle address (0x0 for default)
            uint256(0),         // optional oracle fee (0 for default)
            address(0),         // optional relayer address (0x0 for default)
            uint256(0)          // optional relayer fee (0 for default)
        )
    });
    ILayerZeroEndpointV2(ETH_LZ_ENDPOINT).setConfig(params);
    vm.stopPrank();

    // Set up peers and DVN configurations on Plume chain
    vm.selectFork(plumeMainnetFork);
    vm.startPrank(owner);
    
    // On Plume chain, set ETH as peer
    bytes32 ethPeer = bytes32(uint256(uint160(address(ethProxy))));
    plumeOFT.setPeer(ETH_EID, ethPeer);

    // Configure DVN for Plume -> ETH path
    params = new SetConfigParam[](1);
    params[0] = SetConfigParam({
        lib: address(plumeOFT),
        config: abi.encode(
            uint8(1),           // number of confirmations required
            address(0),         // optional oracle address (0x0 for default)
            uint256(0),         // optional oracle fee (0 for default)
            address(0),         // optional relayer address (0x0 for default)
            uint256(0)          // optional relayer fee (0 for default)
        )
    });
    ILayerZeroEndpointV2(PLUME_LZ_ENDPOINT).setConfig(params);
    vm.stopPrank();
}

    // Helper function to convert address to bytes32
    function addressToBytes32(
        address _addr
    ) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }

    function testInitialization() public {
        vm.selectFork(ethMainnetFork);
        assertEq(ethProxy.name(), "Plume USD");
        assertEq(ethProxy.symbol(), "pUSD");
        assertEq(address(ethProxy.owner()), owner);
    }

    function testCrossChainTransfer() public {
        // Start on Ethereum mainnet
        vm.selectFork(ethMainnetFork);
        uint256 amount = 1e6; // 1 USDC (6 decimals)

        // Give user some USDC on Ethereum
        deal(ETH_USDC, user, amount);

        vm.startPrank(user);

        // Approve adapter to spend USDC
        IERC20(ETH_USDC).approve(address(ethVault), amount);

        // Get expected shares using vault interface
        uint256 minimumMint = ethVault.previewDeposit(amount);

        // First deposit USDC into adapter using vault interface
        ethVault.deposit(
            amount,
            user, // receiver
            user, // controller
            minimumMint
        );

        // Then initiate cross-chain transfer using OFT interface
        vm.deal(user, 1 ether); // For LZ fees

        // Create SendParam for OFT
        SendParam memory params = SendParam({
            dstEid: PLUME_EID,
            to: bytes32(uint256(uint160(user))),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: bytes(""),
            composeMsg: bytes(""),
            oftCmd: bytes("")
        });

        // Get messaging fee
        MessagingFee memory fee = ethOFT.quoteSend(params, false);

        // Send tokens cross-chain
        ethOFT.send{ value: fee.nativeFee }(
            params,
            fee,
            payable(user) // refundAddress
        );
        vm.stopPrank();

        // Verify USDC was taken from user on Ethereum
        assertEq(IERC20(ETH_USDC).balanceOf(user), 0);

        // Switch to Plume mainnet to verify receipt
        vm.selectFork(plumeMainnetFork);

        // Verify user received shares in the Plume vault
        assertEq(IBoringVault(VAULT_TOKEN).balanceOf(user), minimumMint);

        // Verify adapter's record of user's assets
        assertEq(plumeVault.assetsOf(user), amount);
    }

}
