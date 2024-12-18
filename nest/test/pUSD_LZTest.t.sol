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
import { SetConfigParam,IMessageLibManager } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SetConfigParam,IMessageLibManager } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";

import {IMessageLib} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLib.sol";
import { CREATEX } from "create3-factory/CREATEX.sol";
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
    ethMainnetFork = vm.createFork(
        vm.envString("ETH_MAINNET_RPC"),
        21426221
    );
    plumeMainnetFork = vm.createFork(
        vm.envString("PLUME_MAINNET_RPC"),
        85430
    );

    // Create users
    owner = makeAddr("owner");
    user = makeAddr("user");

    // Deploy on ETH mainnet
    vm.selectFork(ethMainnetFork);
    vm.startPrank(owner);

    // Deploy ETH implementation using CREATE3
    bytes32 ethImplSalt = keccak256("pUSD_ETH_IMPLEMENTATION_V1");
    bytes memory ethCreationCode = type(pUSD).creationCode;
    bytes memory ethConstructorArgs = abi.encode(
        ETH_LZ_ENDPOINT,
        ETH_LZ_DELEGATE,
        owner
    );

    ethImplementation = pUSD(
        CREATEX.deployCreate3(
            ethImplSalt,
            abi.encodePacked(ethCreationCode, ethConstructorArgs)
        )
    );
    vm.makePersistent(address(ethImplementation));
    vm.makePersistent(ETH_LZ_ENDPOINT);
    vm.makePersistent(ETH_USDC);

    // Deploy ETH proxy using CREATE3
    bytes32 ethProxySalt = keccak256("pUSD_ETH_PROXY_V1");
    bytes memory initData = abi.encodeCall(
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
    );

    ethProxy = pUSD(
        CREATEX.deployCreate3(
            ethProxySalt,
            abi.encodePacked(
                type(ERC1967Proxy).creationCode,
                abi.encode(address(ethImplementation), initData)
            )
        )
    );
    vm.makePersistent(address(ethProxy));

    // Check if library is registered
    bool isRegistered = ILayerZeroEndpointV2(ETH_LZ_ENDPOINT).isRegisteredLibrary(ETH_LZ_DELEGATE);
    console.log("Is library registered?", isRegistered);

    // Set the delegate for our proxy
    ILayerZeroEndpointV2(ETH_LZ_ENDPOINT).setDelegate(ETH_LZ_DELEGATE);

    vm.stopPrank();
    vm.startPrank(address(ethProxy));

    // Set up the config for ETH chain
    SetConfigParam[] memory params = new SetConfigParam[](1);
    params[0] = SetConfigParam({
        eid: PLUME_EID,
        configType: 1,
        config: abi.encode(
            uint16(10000),
            address(0x173272739Bd7Aa6e4e214714048a9fE699453059)
        )
    });

    try IMessageLibManager(ETH_LZ_ENDPOINT).setConfig(
        address(ethProxy),
        ETH_LZ_DELEGATE,
        params
    ) {
        console.log("Config set successfully");
    } catch Error(string memory reason) {
        console.log("Error setting config:", reason);
        console.log("Caller:", address(ethProxy));
        console.log("Library:", ETH_LZ_DELEGATE);
        console.log("EID:", PLUME_EID);
    } catch (bytes memory errData) {
        console.log("Failed to set config. Error data:", vm.toString(errData));
    }

    vm.stopPrank();
    vm.startPrank(owner);

    // Deploy on Plume chain
    vm.selectFork(plumeMainnetFork);

    // Deploy Plume implementation using CREATE3
    bytes32 plumeImplSalt = keccak256("pUSD_PLUME_IMPLEMENTATION_V1");
    bytes memory plumeCreationCode = type(pUSD).creationCode;
    bytes memory plumeConstructorArgs = abi.encode(
        PLUME_LZ_ENDPOINT,
        PLUME_LZ_DELEGATE,
        owner
    );

    plumeImplementation = pUSD(
        CREATEX.deployCreate3(
            plumeImplSalt,
            abi.encodePacked(plumeCreationCode, plumeConstructorArgs)
        )
    );
    vm.makePersistent(address(plumeImplementation));
    vm.makePersistent(PLUME_LZ_ENDPOINT);
    vm.makePersistent(PLUME_USDC);

    // Deploy Plume proxy using CREATE3
    bytes32 plumeProxySalt = keccak256("pUSD_PLUME_PROXY_V1");
    initData = abi.encodeCall(
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
    );

    plumeProxy = pUSD(
        CREATEX.deployCreate3(
            plumeProxySalt,
            abi.encodePacked(
                type(ERC1967Proxy).creationCode,
                abi.encode(address(plumeImplementation), initData)
            )
        )
    );
    vm.makePersistent(address(plumeProxy));

    // Set up peer for Plume chain using proper left padding
    bytes32 ethPeer = addressToBytes32LeftPad(address(ethProxy));
    plumeProxy.setPeer(ETH_EID, ethPeer);

    // Set up config for Plume chain
    vm.stopPrank();
    vm.startPrank(address(plumeProxy));
    
    params[0] = SetConfigParam({
        eid: ETH_EID,
        configType: 1,
        config: abi.encode(uint16(10000))  // Using same value as ETH config
    });

    try IMessageLibManager(PLUME_LZ_ENDPOINT).setConfig(
        address(plumeProxy),
        PLUME_LZ_DELEGATE,
        params
    ) {
        console.log("Plume config set successfully");
    } catch Error(string memory reason) {
        console.log("Error setting Plume config:", reason);
        console.log("Caller:", address(plumeProxy));
        console.log("Library:", PLUME_LZ_DELEGATE);
        console.log("EID:", ETH_EID);
    } catch (bytes memory errData) {
        console.log("Failed to set Plume config. Error data:", vm.toString(errData));
    }
    
    vm.stopPrank();
}

// Helper function for proper address to bytes32 conversion
function addressToBytes32LeftPad(address addr) internal pure returns (bytes32) {
    return bytes32(bytes20(addr)) >> 0x60;
}


/*


function setUp() public {
    // Create forks


//21426221
    //ethMainnetFork = vm.createFork(vm.envString("ETH_MAINNET_RPC"));

   ethMainnetFork = vm.createFork(
            vm.envString("ETH_MAINNET_RPC"),
            21426221 // your desired block number
        );


  //85430
    //plumeMainnetFork = vm.createFork(vm.envString("PLUME_MAINNET_RPC"));
   plumeMainnetFork = vm.createFork(
            vm.envString("PLUME_MAINNET_RPC"),
            85430 // your desired block number
        );

    // Create users
    owner = makeAddr("owner");
    user = makeAddr("user");

    // Deploy on ETH mainnet
    vm.selectFork(ethMainnetFork);
    
    vm.startPrank(owner);  // Start pranking as owner before deployments

    // Deploy ETH implementation
    ethImplementation = new pUSD(
        ETH_LZ_ENDPOINT,
        ETH_LZ_DELEGATE,
        owner
    );
    vm.makePersistent(address(ethImplementation));
    vm.makePersistent(ETH_LZ_ENDPOINT);
    vm.makePersistent(ETH_USDC);

    // Deploy ETH proxy
    bytes memory initData = abi.encodeCall(
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
    );
    
    // Deploy ETH proxy and make it persistent immediately
    ERC1967Proxy ethProxyContract = new ERC1967Proxy(
        address(ethImplementation),
        initData
    );
    vm.makePersistent(address(ethProxyContract));
    ethProxy = pUSD(address(ethProxyContract));
    vm.makePersistent(address(ethProxy));
    // Instead of checking owner(), check if the address has the DEFAULT_ADMIN_ROLE
    bytes32 DEFAULT_ADMIN_ROLE = 0x00;
    console.log("Has admin role:", ethProxy.hasRole(DEFAULT_ADMIN_ROLE, owner));

vm.stopPrank();


    // Deploy on Plume
    vm.selectFork(plumeMainnetFork);
    
    // Deploy Plume implementation
    plumeImplementation = new pUSD(
        PLUME_LZ_ENDPOINT,
        PLUME_LZ_DELEGATE,
        owner
    );
    vm.makePersistent(address(plumeImplementation));
    vm.makePersistent(PLUME_LZ_ENDPOINT);
    vm.makePersistent(PLUME_USDC);

    // Deploy Plume proxy
    initData = abi.encodeCall(
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
    );
    
    // Deploy Plume proxy and make it persistent immediately
    ERC1967Proxy plumeProxyContract = new ERC1967Proxy(
        address(plumeImplementation),
        initData
    );
    vm.makePersistent(address(plumeProxyContract));
    plumeProxy = pUSD(address(plumeProxyContract));
    vm.makePersistent(address(plumeProxy));

    // Cast proxies to interfaces
    ethVault = IBoringVaultAdapter(address(ethProxy));
    plumeVault = IBoringVaultAdapter(address(plumeProxy));
    ethOFT = OFTCore(address(ethProxy));
    plumeOFT = OFTCore(address(plumeProxy));

    // Set up ETH chain configuration
    vm.selectFork(ethMainnetFork);
    vm.startPrank(owner);


    // Debug ownership
console.log("Owner from contract:", ethProxy.owner());
console.log("Caller address:", msg.sender);
console.log("Owner address:", owner);


    //ethProxy.transferOwnership(owner);
    //vm.makePersistent(address(ethProxy));
    // Set up ownership and roles for ETH proxy
    //ethProxy.grantRole(ethProxy.DEFAULT_ADMIN_ROLE(), owner);
    //ethProxy.grantRole(ethProxy.ADMIN_ROLE(), owner);
    
    bytes32 plumePeer = bytes32(uint256(uint160(address(plumeProxy))));
    ethOFT.setPeer(PLUME_EID, plumePeer);

// First, check if the library is already registered
IMessageLibManager endpoint = IMessageLibManager(ETH_LZ_ENDPOINT);
bool isRegistered = endpoint.isRegisteredLibrary(ETH_LZ_DELEGATE);

// If not registered, we need to impersonate the endpoint owner to register it
if (!isRegistered) {
    address endpointOwner = Ownable(ETH_LZ_ENDPOINT).owner();
    vm.stopPrank();
    vm.startPrank(endpointOwner);
    
    // Register the library
    endpoint.registerLibrary(ETH_LZ_DELEGATE);
    
    vm.stopPrank();
   // vm.startPrank(owner);
}

// After setting up the proxy and before setting config
vm.startPrank(owner);

// First set the delegate for our proxy
ILayerZeroEndpointV2(ETH_LZ_ENDPOINT).setDelegate(ETH_LZ_DELEGATE);

// Now we need to make sure we're calling setConfig as the proxy or its delegate
address proxyAddress = address(ethProxy);
vm.stopPrank();
vm.startPrank(proxyAddress);  // Call as the proxy itself

// Now set up the config
SetConfigParam[] memory params = new SetConfigParam[](1);
params[0] = SetConfigParam({
    eid: PLUME_EID,
    configType: 1,
    config: abi.encodePacked(uint16(1))
});

// Set the config now that the library is registered
endpoint.setConfig(address(ethProxy), ETH_LZ_DELEGATE, params);


    vm.stopPrank();

    // Set up Plume chain configuration
    vm.selectFork(plumeMainnetFork);
    vm.startPrank(owner);
    //plumeProxy.transferOwnership(owner);
    //vm.makePersistent(address(plumeProxy));

    // Set up ownership and roles for Plume proxy
    //plumeProxy.grantRole(plumeProxy.DEFAULT_ADMIN_ROLE(), owner);
    //plumeProxy.grantRole(plumeProxy.ADMIN_ROLE(), owner);
    
    bytes32 ethPeer = bytes32(uint256(uint160(address(ethProxy))));
    plumeOFT.setPeer(ETH_EID, ethPeer);

    params[0] = SetConfigParam({
        eid: uint32(ETH_EID),
        configType: uint32(1),
        config: abi.encode(uint8(1), address(0), uint256(0), address(0), uint256(0))
    });
    
    ILayerZeroEndpointV2(PLUME_LZ_ENDPOINT).setConfig(
        address(plumeOFT),
        address(plumeOFT),
        params
    );
    vm.stopPrank();
}
*/
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
