// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { SmartWallet } from "../src/SmartWallet.sol";
import { WalletUtils } from "../src/WalletUtils.sol";
import { AssetVault } from "../src/extensions/AssetVault.sol";
import { IAssetToken } from "../src/interfaces/IAssetToken.sol";
import { IAssetVault } from "../src/interfaces/IAssetVault.sol";
import { IYieldReceiver } from "../src/interfaces/IYieldReceiver.sol";

import { MockAssetToken } from "../src/mocks/MockAssetToken.sol";
import { MockERC20 } from "../src/mocks/MockERC20.sol";

import { MockUserWallet } from "../src/mocks/MockUserWallet.sol";
import { MockYieldReceiver } from "../src/mocks/MockYieldReceiver.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Test } from "forge-std/Test.sol";

contract SmartWalletTest is Test {

    SmartWallet smartWallet;
    MockAssetToken mockAssetToken;
    MockYieldReceiver mockYieldReceiver;
    MockUserWallet mockUserWallet;

    // small hack to be excluded from coverage report
    // function test_() public { }

    function setUp() public {
        smartWallet = new SmartWallet();
        mockAssetToken = new MockAssetToken();
        mockYieldReceiver = new MockYieldReceiver();
        mockUserWallet = new MockUserWallet();
    }

    function test_DeployAssetVault() public {
        smartWallet.deployAssetVault();
        assertFalse(address(smartWallet.getAssetVault()) == address(0), "AssetVault should be deployed");
    }

    function test_DeployAssetVaultTwice() public {
        smartWallet.deployAssetVault();
        vm.expectRevert(
            abi.encodeWithSelector(SmartWallet.AssetVaultAlreadyExists.selector, smartWallet.getAssetVault())
        );
        smartWallet.deployAssetVault();
    }

    function test_GetAssetVault() public {
        assertEq(address(smartWallet.getAssetVault()), address(0), "AssetVault should be zero address initially");
        smartWallet.deployAssetVault();
        assertFalse(
            address(smartWallet.getAssetVault()) == address(0), "AssetVault should not be zero address after deployment"
        );
    }

    function test_GetBalanceLocked() public {
        smartWallet.deployAssetVault();
        uint256 balanceLocked = smartWallet.getBalanceLocked(IAssetToken(address(mockAssetToken)));
        assertEq(balanceLocked, 0, "Initial balance locked should be zero");
    }

    function test_ClaimAndRedistributeYield() public {
        smartWallet.claimAndRedistributeYield(IAssetToken(address(mockAssetToken)));
        // Add assertions based on the expected behavior
    }

    function test_TransferYield() public {
        // Deploy mocks
        MockERC20 mockCurrencyToken = new MockERC20("Mock", "MCK"); // Use a proper ERC20 mock
        MockYieldReceiver mockReceiver = new MockYieldReceiver();

        // Setup
        smartWallet.deployAssetVault();
        address assetVault = address(smartWallet.getAssetVault());

        // Mint some tokens to the smart wallet for transfer
        mockCurrencyToken.mint(address(smartWallet), 1000);

        // Execute transfer
        vm.prank(assetVault);
        smartWallet.transferYield(
            IAssetToken(address(mockAssetToken)), address(mockReceiver), IERC20(address(mockCurrencyToken)), 100
        );
    }

    function test_TransferYieldUnauthorized() public {
        vm.expectRevert(abi.encodeWithSelector(SmartWallet.UnauthorizedAssetVault.selector, address(this)));
        smartWallet.transferYield(
            IAssetToken(address(mockAssetToken)), address(mockYieldReceiver), IERC20(address(1)), 100
        );
    }

    function test_ReceiveYield() public {
        // Mock the transferFrom function
        vm.mockCall(
            address(1),
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(this), address(smartWallet), 100),
            abi.encode(true)
        );

        smartWallet.receiveYield(IAssetToken(address(0)), IERC20(address(1)), 100);
        // Add assertions based on the expected behavior
    }

    function test_ReceiveYieldTransferFailed() public {
        // Mock the transferFrom function to return false
        vm.mockCall(
            address(1),
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(this), address(smartWallet), 100),
            abi.encode(false)
        );

        vm.expectRevert(
            abi.encodeWithSelector(SmartWallet.TransferFailed.selector, address(this), IERC20(address(1)), 100)
        );
        smartWallet.receiveYield(IAssetToken(address(0)), IERC20(address(1)), 100);
    }

    function test_Upgrade() public {
        vm.prank(address(smartWallet));
        smartWallet.upgrade(address(mockUserWallet));
    }

    function test_UpgradeUnauthorized() public {
        //vm.expectRevert();
        vm.startPrank(address(0xdead));
        vm.expectRevert(abi.encodeWithSelector(WalletUtils.UnauthorizedCall.selector, address(0xdead)));
        smartWallet.upgrade(address(mockUserWallet));
        vm.stopPrank();
    }

    function test_FallbackToUserWallet() public {
        vm.prank(address(smartWallet));
        smartWallet.upgrade(address(mockUserWallet));

        (bool success, bytes memory data) = address(smartWallet).call(abi.encodeWithSignature("customFunction()"));
        assertTrue(success, "Call to user wallet should succeed");
        assertTrue(abi.decode(data, (bool)), "Custom function should return true");
    }

    function test_ReceiveEther() public {
        (bool success,) = address(smartWallet).call{ value: 1 ether }("");
        assertTrue(success, "Receiving ether should succeed");
        assertEq(address(smartWallet).balance, 1 ether, "SmartWallet balance should be 1 ether");
    }

}
