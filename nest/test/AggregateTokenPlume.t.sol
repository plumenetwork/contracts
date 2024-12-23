// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { AggregateToken } from "../src/AggregateToken.sol";
import { IComponentToken } from "../src/interfaces/IComponentToken.sol";
import { AggregateTokenProxy } from "../src/proxy/AggregateTokenProxy.sol";
import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { MockInvalidToken } from "../src/mocks/MockInvalidToken.sol";
import { MockUSDC } from "../src/mocks/MockUSDC.sol";

contract AggregateTokenPlumeTest is Test {

    address constant AGGREGATE_TOKEN_ADDRESS = 0x99480166Ad5260440d4cf4b010Cf24BAc4d21b44;
    address constant USDC_ADDRESS = 0x401eCb1D350407f13ba348573E5630B83638E30D;
    address constant PUSD_ADDRESS = 0x2DEc3B6AdFCCC094C31a2DCc83a43b5042220Ea2;

    AggregateToken public token;
    //MockUSDC public usdc;
    //MockUSDC public newUsdc;
    IERC20 public usdc = IERC20(USDC_ADDRESS);
    IERC20 public newUsdc = IERC20(USDC_ADDRESS);
    IERC20 public pUSD = IERC20(PUSD_ADDRESS);
    address public owner;
    address public user1;
    address public user2;

    // Events
    event AssetTokenUpdated(IERC20 indexed oldAsset, IERC20 indexed newAsset);
    event ComponentTokenListed(IComponentToken indexed componentToken);
    event ComponentTokenUnlisted(IComponentToken indexed componentToken);
    event ComponentTokenBought(
        address indexed buyer, IComponentToken indexed componentToken, uint256 componentTokenAmount, uint256 assets
    );
    event ComponentTokenSold(
        address indexed seller, IComponentToken indexed componentToken, uint256 componentTokenAmount, uint256 assets
    );
    event Paused();
    event Unpaused();
    event ComponentTokenRemoved(IComponentToken indexed componentToken);

    event ComponentTokenBuyRequested(
        address indexed buyer, IComponentToken indexed componentToken, uint256 assets, uint256 requestId
    );

    event ComponentTokenSellRequested(
        address indexed seller, IComponentToken indexed componentToken, uint256 componentTokenAmount, uint256 requestId
    );

    function setUp() public {
        owner = makeAddr("owner");
        user1 = 0xE1F42aa9aec952f61c5D929dd0b33690faAEf976;
        user2 = makeAddr("user2");

        // Deploy tokens
        //usdc = new MockUSDC();
        //newUsdc = new MockUSDC();

        // Deploy through proxy
        /*
        AggregateToken impl = new AggregateToken();
        ERC1967Proxy proxy = new AggregateTokenProxy(
            address(impl),
            abi.encodeCall(
                AggregateToken.initialize,
                (
                    owner,
                    "Aggregate Token",
                    "AGG",
                    IComponentToken(address(pUSD)),
                    1e18, // 1:1 askPrice
                    1e18 // 1:1 bidPrice
                )
            )
        );
        */
        token = AggregateToken(address(AGGREGATE_TOKEN_ADDRESS));

        // Setup initial balances and approvals
        //usdc.mint(user1, 1000e6);
        //vm.prank(user1);
        usdc.approve(address(token), type(uint256).max);
        pUSD.approve(address(token), type(uint256).max);
    }

    function testDeposit() public {
        //usdc.approve(address(token), 1e6);
        pUSD.approve(address(token), 1e6);
        uint256 shares = token.deposit(1e6, user1, user1);
        assertEq(shares, 1e6);
        assertEq(token.balanceOf(user1), 1e6);
    }

    function testRedeem() public {
        // Setup: First deposit some tokens
        vm.startPrank(user1);
        usdc.approve(address(token), 1e18);
        token.deposit(1e18, user1, user1);

        // Test redeem
        uint256 assets = token.redeem(1e18, user1, user1);
        assertEq(assets, 1e18);
        assertEq(token.balanceOf(user1), 0);
        assertEq(usdc.balanceOf(user1), 1000e6); // Back to original balance
        vm.stopPrank();
    }

}
