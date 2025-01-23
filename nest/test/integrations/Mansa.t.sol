// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AggregateToken } from "../../src/AggregateToken.sol";
import { ComponentToken } from "../../src/ComponentToken.sol";

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { console2 } from "forge-std/console2.sol";

import { IComponentToken } from "../../src/interfaces/IComponentToken.sol";

contract MansaTest is Test {

    AggregateToken public aggregateToken;
    ComponentToken public componentToken;

    address public constant MANAGER = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;

    address public constant MANSA_TOKEN = 0xa4ba0D2fbE9E1635348746bc3D30eD00c3E91E55;
    address public constant AGGREGATE_TOKEN = 0x81537d879ACc8a290a1846635a0cAA908f8ca3a6;

    address private constant NEST_ADMIN_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;
    address private constant BORING_VAULT_ADDRESS = 0xe644F07B1316f28a7F134998e021eA9f7135F351;

    UUPSUpgradeable private constant AGGREGATE_TOKEN_PROXY =
        UUPSUpgradeable(payable(0x81537d879ACc8a290a1846635a0cAA908f8ca3a6));

    // Add the component token addresses
    address private constant ASSET_TOKEN = 0x2DEc3B6AdFCCC094C31a2DCc83a43b5042220Ea2;

    // LiquidContinuousMultiTokenVault - Credbull
    address private constant COMPONENT_TOKEN = 0x4B1fC984F324D2A0fDD5cD83925124b61175f5C6;

    function setUp() public {
        // Fork mainnet
        vm.createSelectFork(vm.envString("PLUME_RPC_URL"));

        // Get contract instances
        //aggregateToken = AggregateToken(AGGREGATE_TOKEN);

        vm.startBroadcast(NEST_ADMIN_ADDRESS);
        // Deploy new implementation
        AggregateToken newAggregateTokenImpl = new AggregateToken();

        // Upgrade to new implementation
        AGGREGATE_TOKEN_PROXY.upgradeToAndCall(address(newAggregateTokenImpl), "");

        // Get the upgraded contract instance
        aggregateToken = AggregateToken(address(AGGREGATE_TOKEN_PROXY));

        componentToken = ComponentToken(MANSA_TOKEN);
        //aggregateToken.addComponentToken(IComponentToken(MANSA_TOKEN));
        //console2.log("Added MANSA_TOKEN to component list");

        vm.stopBroadcast();
    }

    function testBuyComponentToken() public {
        uint256 amountToBuy = 1 * 1e6; // 1 USDT (assuming 6 decimals)

        // Get the asset address from the component token
        address assetAddress = componentToken.asset();
        console.log("assetAddress", assetAddress);
        // Deal some asset tokens to the aggregate token
        deal(assetAddress, address(aggregateToken), amountToBuy);

        vm.startPrank(MANAGER);

        aggregateToken.approveComponentToken(componentToken, amountToBuy);
        aggregateToken.approveAssetToken(IERC20(assetAddress), address(componentToken), amountToBuy);

        IERC20(assetAddress).approve(address(MANSA_TOKEN), amountToBuy);

        // 3. Finally execute the buy
        aggregateToken.buyComponentToken(ComponentToken(MANSA_TOKEN), amountToBuy);
        vm.stopPrank();

        // Verify the purchase
        //assertEq(componentToken.balanceOf(address(aggregateToken)), amountToBuy);

        // Verify request state is cleared
        //assertEq(componentToken.pendingDepositRequest(0, address(aggregateToken)), 0);
        //assertEq(componentToken.claimableDepositRequest(0, address(aggregateToken)), 0);
    }

}
