// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { pUSD } from "../src/token/pUSD.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";



import { pUSD } from "../src/token/pUSD.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { MockVault } from "../src/mocks/MockVault.sol";
import { MockTeller } from "../src/mocks/MockTeller.sol";
import { MockAtomicQueue } from "../src/mocks/MockAtomicQueue.sol";
import { MockLens } from "../src/mocks/MockLens.sol";
import { MockAccountantWithRateProviders } from "../src/mocks/MockAccountantWithRateProviders.sol";
import { MockUSDC } from "../src/mocks/MockUSDC.sol";


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


/*
pUSD

BoringVault 
0xdddD73F5Df1F0DC31373357beAC77545dC5A6f3F

Accountant
0xbB2fAA1e1D6183EE3c4177476ce0d70CBd55A388

Teller
0x16424eDF021697E34b800e1D98857536B0f2287B

Manager
0x42A683CAc2215aFCe22e2822F883fF9CD57f08D5

**BoringVault contract addresses are always identical on Ethereum and Plume

—— Plume Mainnet Only ——

AtomicQueue 
0x7f69e1A09472EEb7a5dA7552bD59Ca022c341193

Lens 
0x3D2021776e385601857E7b7649de955525E21d23
*/





    string PLUME_MAINNET_RPC = vm.envString("PLUME_MAINNET_RPC");
    string ETH_MAINNET_RPC = vm.envString("ETH_MAINNET_RPC");

    uint256 plumeMainnetFork;
    uint256 ethMainnetFork;

    // Test contracts
    pUSD public ethImplementation;
    pUSD public plumeImplementation;
    pUSD public ethProxy;
    pUSD public plumeProxy;

    // Test accounts
    address public owner;
    address public user;


            // Create mock addresses for ETH mainnet deployment
    // Mock contracts for ETH mainnet
    MockVault public mockVault;
    MockTeller public mockTeller;
    MockAtomicQueue public mockQueue;
    MockLens public mockLens;
    MockAccountantWithRateProviders public mockAccountant;
    MockUSDC public mockUSDC;

   function setUp() public {
        // Create forks
        ethMainnetFork = vm.createFork(vm.envString("ETH_MAINNET_RPC"));
        plumeMainnetFork = vm.createFork(vm.envString("PLUME_MAINNET_RPC"));

    vm.selectFork(plumeMainnetFork);
     uint256 chainId;
    assembly {
        chainId := chainid()
    }
    console.log("Plume mainnet forked, chainId:", chainId);
    require(chainId == 98865, "Not connected to Plume mainnet: chainId");


    // Create users
    owner = makeAddr("owner");
    user = makeAddr("user");
    
    // Make contracts persistent
    vm.makePersistent(ETH_pUSD);
    vm.makePersistent(PLUME_pUSD);
    vm.makePersistent(ETH_USDC);
    vm.makePersistent(PLUME_USDC);

    // Use existing deployed contracts instead of deploying new ones
    ethProxy = pUSD(ETH_pUSD);
    plumeProxy = pUSD(PLUME_pUSD);

    // Verify contracts exist
    require(address(ETH_pUSD).code.length > 0, "ETH pUSD not found");
    require(address(PLUME_pUSD).code.length > 0, "Plume pUSD not found");


/*
    // Create users
    owner = makeAddr("owner");
    user = makeAddr("user");
    
    // Make contracts persistent
    vm.makePersistent(ETH_USDC);
    vm.makePersistent(PLUME_USDC);
    vm.makePersistent(VAULT_TOKEN);
    vm.makePersistent(ATOMIC_QUEUE);
    vm.makePersistent(TELLER_ADDRESS);
    vm.makePersistent(LENS_ADDRESS);
    vm.makePersistent(ACCOUNTANT_ADDRESS);

    // Verify contracts exist on Plume
    require(address(VAULT_TOKEN).code.length > 0, "Vault not found on Plume");
    require(address(ATOMIC_QUEUE).code.length > 0, "Queue not found on Plume");
    require(address(TELLER_ADDRESS).code.length > 0, "Teller not found on Plume");
    require(address(LENS_ADDRESS).code.length > 0, "Lens not found on Plume");
    require(address(ACCOUNTANT_ADDRESS).code.length > 0, "Accountant not found on Plume");

        // Deploy on ETH mainnet
        vm.selectFork(ethMainnetFork);
        ethImplementation = new pUSD(ETH_LZ_ENDPOINT, ETH_LZ_DELEGATE, owner);

        ERC1967Proxy ethProxy_ = new ERC1967Proxy(
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
        ethProxy = pUSD(address(ethProxy_));

        // Deploy on Plume mainnet
        vm.selectFork(plumeMainnetFork);
        plumeImplementation = new pUSD(PLUME_LZ_ENDPOINT, PLUME_LZ_DELEGATE, owner);

        ERC1967Proxy plumeProxy_ = new ERC1967Proxy(
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
        plumeProxy = pUSD(address(plumeProxy_));


        */
    }


    function testInitialization() public {
        vm.selectFork(ethMainnetFork);
        assertEq(ethProxy.name(), "Plume USD");
        assertEq(ethProxy.symbol(), "pUSD");
        assertEq(address(ethProxy.owner()), owner);
    }
/*
    function testCrossChainTransfer() public {
        vm.selectFork(ethMainnetFork);
        uint256 amount = 1e9; // 1000 USDC (6 decimals)

        // Give user some USDC
        deal(ETH_USDC, user, amount);

        vm.startPrank(user);
        IERC20(ETH_USDC).approve(address(ethProxy), amount);
        ethProxy.deposit(amount, user);

        // Verify initial balance
        assertEq(ethProxy.balanceOf(user), amount);

        // Perform cross-chain transfer
        bytes memory options = ""; // Add necessary LZ options if needed
        ethProxy.sendFrom{value: 1 ether}( // Need to send some ETH for LZ fees
            user,
            30318, // Plume EID
            bytes32(uint256(uint160(user))),
            amount,
            payable(user),
            options
        );
        vm.stopPrank();

        // Verify balance decreased on ETH mainnet
        assertEq(ethProxy.balanceOf(user), 0);

        // Switch to Plume mainnet to verify receipt
        vm.selectFork(plumeMainnetFork);
        assertEq(plumeProxy.balanceOf(user), amount);
    }
*/


function testCrossChainTransfer() public {
    vm.selectFork(ethMainnetFork);
    uint256 amount = 1e9; // 1000 pUSD

    // Give user some USDC for deposit
    deal(ETH_USDC, user, amount);

    vm.startPrank(user);
    IERC20(ETH_USDC).approve(address(ethProxy), amount);
    ethProxy.deposit(amount, user);

    // Verify initial balance
    assertEq(ethProxy.balanceOf(user), amount);

    // Perform cross-chain transfer
    bytes memory options = "";
    ethProxy.sendFrom{value: 1 ether}(
        user,
        PLUME_EID,
        bytes32(uint256(uint160(user))),
        amount,
        payable(user),
        options
    );
    vm.stopPrank();

    // Verify balance decreased on ETH mainnet
    assertEq(ethProxy.balanceOf(user), 0);

    // Switch to Plume mainnet to verify receipt
    vm.selectFork(plumeMainnetFork);
    assertEq(plumeProxy.balanceOf(user), amount);
}
}
