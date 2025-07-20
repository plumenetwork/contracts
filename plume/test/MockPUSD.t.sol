// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { MockPUSD } from "../src/mocks/MockPUSD.sol";
import { MockPUSDProxy } from "../src/proxy/MockPUSDProxy.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Test } from "forge-std/Test.sol";

contract MockPUSDTest is Test {

    MockPUSD public implementation;
    MockPUSD public token;
    address public owner;
    address public user1;
    address public user2;

    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 10 ** 6; // 1 million tokens with 6 decimals

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        
        implementation = new MockPUSD();

        // Prepare initialization data
        bytes memory initData = abi.encodeCall(MockPUSD.initialize, (owner, INITIAL_SUPPLY));

        // Deploy proxy
        ERC1967Proxy proxy = new MockPUSDProxy(address(implementation), initData);

        // Cast proxy to MockPUSD
        token = MockPUSD(address(proxy));

        // Give some ETH to test users
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
    }

    function test_Initialization() public {
        assertEq(token.name(), "Plume USD Test");
        assertEq(token.symbol(), "pUSDTest");
        assertEq(token.decimals(), 6);
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY);
    }

    function test_Mint() public {
        uint256 mintAmount = 100 * 10 ** 6;
        token.mint(user1, mintAmount);

        assertEq(token.balanceOf(user1), mintAmount);
        assertEq(token.totalSupply(), INITIAL_SUPPLY + mintAmount);
    }

    function test_BurnFromOwner() public {
        uint256 burnAmount = 100 * 10 ** 6;
        token.burn(owner, burnAmount);

        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - burnAmount);
        assertEq(token.totalSupply(), INITIAL_SUPPLY - burnAmount);
    }

    function test_BurnOwn() public {
        uint256 transferAmount = 500 * 10 ** 6;
        uint256 burnAmount = 100 * 10 ** 6;

        token.transfer(user1, transferAmount);

        vm.startPrank(user1);
        token.burnOwn(burnAmount);
        vm.stopPrank();

        assertEq(token.balanceOf(user1), transferAmount - burnAmount);
        assertEq(token.totalSupply(), INITIAL_SUPPLY - burnAmount);
    }

    function test_Transfer() public {
        uint256 transferAmount = 100 * 10 ** 6;
        token.transfer(user1, transferAmount);

        assertEq(token.balanceOf(user1), transferAmount);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - transferAmount);
    }

    function test_TransferFrom() public {
        uint256 transferAmount = 100 * 10 ** 6;

        token.approve(user1, transferAmount);

        vm.prank(user1);
        token.transferFrom(owner, user2, transferAmount);

        assertEq(token.balanceOf(user2), transferAmount);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - transferAmount);
        assertEq(token.allowance(owner, user1), 0);
    }

    function test_Upgrade() public {
        // Deploy new implementation
        MockPUSD newImplementation = new MockPUSD();

        // Upgrade the proxy
        token.upgradeToAndCall(address(newImplementation), "");

        // Verify the implementation has been upgraded but state is preserved
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY);
    }

    function test_RevertWhen_MintUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert();
        token.mint(user1, 100 * 10 ** 6);
    }

    function test_RevertWhen_BurnUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert();
        token.burn(owner, 100 * 10 ** 6);
    }

    function test_RevertWhen_UpgradeUnauthorized() public {
        MockPUSD newImplementation = new MockPUSD();

        vm.prank(user1);
        vm.expectRevert();
        token.upgradeToAndCall(address(newImplementation), "");
    }

    function test_RevertWhen_TransferInsufficientBalance() public {
        vm.prank(user1);
        vm.expectRevert();
        token.transfer(user2, 100 * 10 ** 6); // user1 has no tokens
    }

}
