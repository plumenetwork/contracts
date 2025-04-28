// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { MockPUSD } from "../src/mocks/MockPUSD.sol";
import { MockPUSDProxy } from "../src/proxy/MockPUSDProxy.sol";

/**
 * @title DeployMockPUSD
 * @notice Deploys MockPUSD token with proxy for upgradeability
 */
contract DeployMockPUSD is Script {

    // Configuration constants
    address private constant ADMIN_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;
    uint256 private constant INITIAL_SUPPLY = 1_000_000_000 * 1e6; // 1 billion tokens with 6 decimals

    function run() external {
        vm.startBroadcast();

        // 1. Deploy implementation contract
        MockPUSD mockPUSDImplementation = new MockPUSD();
        console2.log("MockPUSD Implementation deployed to:", address(mockPUSDImplementation));

        // 2. Prepare initialization data
        bytes memory initData = abi.encodeCall(
            MockPUSD.initialize,
            (
                ADMIN_ADDRESS, // owner
                INITIAL_SUPPLY // initial supply
            )
        );

        // 3. Deploy proxy contract pointing to implementation
        ERC1967Proxy proxy = new MockPUSDProxy(address(mockPUSDImplementation), initData);
        console2.log("MockPUSD Proxy deployed to:", address(proxy));

        // Cast proxy address to MockPUSD interface for easier interaction
        MockPUSD mockPUSD = MockPUSD(address(proxy));

        // Log deployment information
        console2.log("\nDeployment Configuration:");
        console2.log("------------------------");
        console2.log("Implementation:", address(mockPUSDImplementation));
        console2.log("Proxy:", address(proxy));
        console2.log("Admin:", ADMIN_ADDRESS);
        console2.log("Initial Supply:", INITIAL_SUPPLY);
        console2.log("Name:", mockPUSD.name());
        console2.log("Symbol:", mockPUSD.symbol());
        console2.log("Decimals:", mockPUSD.decimals());

        vm.stopBroadcast();
    }

}
