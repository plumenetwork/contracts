// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { pUSD } from "../src/token/pUSD.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract pUSD_LZTest is Test {

    // Constants for LayerZero addresses on Ethereum mainnet
    address constant LZ_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c; // ETH Mainnet EndpointV2
    address constant LZ_DELEGATE = 0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1; // ETH Mainnet SendUln302
    uint16 constant PLUME_EID = 30_318; // Plume's LayerZero Chain ID

    address private constant VAULT_TOKEN = 0xe644F07B1316f28a7F134998e021eA9f7135F351;
    address private constant ATOMIC_QUEUE = 0x9fEcc2dFA8B64c27B42757B0B9F725fe881Ddb2a;
    address private constant TELLER_ADDRESS = 0xE010B6fdcB0C1A8Bf00699d2002aD31B4bf20B86;
    address private constant LENS_ADDRESS = 0x39e4A070c3af7Ea1Cc51377D6790ED09D761d274;
    address private constant ACCOUNTANT_ADDRESS = 0x607e6E4dC179Bf754f88094C09d9ee9Af990482a;

    // Test contracts
    pUSD public implementation;
    pUSD public proxy;

    // Test accounts
    address public owner;
    address public user;

    // USDC on mainnet
    address constant USDC = 0x3938A812c54304fEffD266C7E2E70B48F9475aD6;

    function setUp() public {
        // Fork mainnet
        vm.createSelectFork(vm.rpcUrl("mainnet"));

        // Setup test accounts
        owner = makeAddr("owner");
        user = makeAddr("user");

        // Deploy implementation
        implementation = new pUSD(LZ_ENDPOINT, LZ_DELEGATE, owner);

        // Deploy proxy
        ERC1967Proxy proxy_ = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                pUSD.initialize,
                (
                    owner, // owner
                    IERC20(USDC), // asset
                    VAULT_TOKEN, // vault - replace with actual vault address
                    TELLER_ADDRESS, // teller - replace with actual teller address
                    ATOMIC_QUEUE, // atomicQueue - replace with actual queue address
                    LENS_ADDRESS, // lens - replace with actual lens address
                    ACCOUNTANT_ADDRESS, // accountant - replace with actual accountant address
                    LZ_ENDPOINT, // endpoint
                    PLUME_EID // eid (Plume = 30318)
                )
            )
        );
        proxy = pUSD(address(proxy_));
    }

    function testInitialization() public {
        assertEq(proxy.name(), "Plume USD");
        assertEq(proxy.symbol(), "pUSD");
        assertEq(proxy.owner(), owner);
        assertEq(address(proxy.asset()), USDC);
    }

    function testDeposit() public {
        uint256 amount = 1000e6; // 1000 USDC

        // Get some USDC
        deal(USDC, user, amount);

        // Approve spending
        vm.startPrank(user);
        IERC20(USDC).approve(address(proxy), amount);

        // Deposit
        proxy.deposit(amount, user);

        // Check balances
        assertEq(proxy.balanceOf(user), amount);
        assertEq(IERC20(USDC).balanceOf(user), 0);
        vm.stopPrank();
    }

    function testCrossChainTransfer() public {
        uint256 amount = 1000e6; // 1000 USDC
        uint32 dstChainId = 2; // Arbitrum = 2

        // Get some USDC and pUSD
        deal(USDC, user, amount);

        vm.startPrank(user);
        IERC20(USDC).approve(address(proxy), amount);
        proxy.deposit(amount, user);

        // Mock cross-chain transfer
        bytes memory options = ""; // Add necessary options if needed
        proxy.sendFrom(
            user, // from
            dstChainId, // destination chain id
            bytes32(uint256(uint160(user))), // to address as bytes32
            amount, // amount
            options // options
        );

        vm.stopPrank();
    }

}
