// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {AggregateToken} from "../src/AggregateToken.sol";
import {ComponentToken} from "../src/ComponentToken.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract DinariTest is Test {
    AggregateToken public aggregateToken;
    ComponentToken public componentToken;


    address public constant MANAGER = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;
    address public constant DINARI_TOKEN = 0xD539A98AA76f6C2285C2C779384d3d77f926f794;
    address public constant AGGREGATE_TOKEN = 0x81537d879ACc8a290a1846635a0cAA908f8ca3a6;

    function setUp() public {
        // Fork mainnet
        vm.createSelectFork(vm.envString("PLUME_RPC_URL"));
        
        // Get contract instances
        aggregateToken = AggregateToken(AGGREGATE_TOKEN);
        componentToken = ComponentToken(DINARI_TOKEN);
    }

    function testBuyComponentToken() public {
        uint256 amountToBuy = 1000 * 1e6; // 1000 USDT (assuming 6 decimals)
        
        // Get the asset address from the component token
        address assetAddress = componentToken.asset();
        
        // Deal some asset tokens to the aggregate token
        deal(assetAddress, address(aggregateToken), amountToBuy);

        // Buy component token as manager
        vm.startPrank(MANAGER);
        aggregateToken.approveComponentToken(componentToken, amountToBuy);

        aggregateToken.requestBuyComponentToken(ComponentToken(DINARI_TOKEN), amountToBuy);
    }
}