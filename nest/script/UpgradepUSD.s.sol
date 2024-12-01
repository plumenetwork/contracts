// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import { Script } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { pUSDProxy } from "../src/proxy/pUSDProxy.sol";
import { pUSD } from "../src/token/pUSD.sol";

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract UpgradePUSD is Script, Test {

    // Constants
    address private constant ADMIN_ADDRESS = 0xb015762405De8fD24d29A6e0799c12e0Ea81c1Ff;
    address private constant PUSD_PROXY = 0x2DEc3B6AdFCCC094C31a2DCc83a43b5042220Ea2;
    address private constant USDC_ADDRESS = 0x401eCb1D350407f13ba348573E5630B83638E30D;
    address private constant USDT_ADDRESS = 0x2413b8C79Ce60045882559f63d308aE3DFE0903d;

    address private constant VAULT_TOKEN = 0xe644F07B1316f28a7F134998e021eA9f7135F351;
    address private constant ATOMIC_QUEUE = 0x9fEcc2dFA8B64c27B42757B0B9F725fe881Ddb2a;
    address private constant TELLER_ADDRESS = 0xE010B6fdcB0C1A8Bf00699d2002aD31B4bf20B86;

    // Current state tracking
    pUSD public currentImplementation;
    string public currentName;
    string public currentSymbol;
    uint8 public currentDecimals;
    address public currentVault;
    uint256 public currentTotalSupply;
    bool public isConnected;

    function setUp() public {
        // Try to read implementation slot from proxy, this only works with RPC
        try vm.load(PUSD_PROXY, ERC1967Utils.IMPLEMENTATION_SLOT) returns (bytes32 implementation) {
            if (implementation != bytes32(0)) {
                address currentImplementationAddr = address(uint160(uint256(implementation)));
                console2.log("Found implementation at:", currentImplementationAddr);
                isConnected = true;

                currentImplementation = pUSD(PUSD_PROXY);
                currentName = currentImplementation.name();
                currentSymbol = currentImplementation.symbol();
                currentDecimals = currentImplementation.decimals();
                currentTotalSupply = currentImplementation.totalSupply();

                console2.log("Current Implementation State:");
                console2.log("Name:", currentName);
                console2.log("Symbol:", currentSymbol);
                console2.log("Decimals:", currentDecimals);
                console2.log("Vault:", currentVault);
                console2.log("Total Supply:", currentTotalSupply);
            } else {
                vm.assume(true);
                isConnected = false;
            }
        } catch {
            console2.log("No implementation found - skipping");
            vm.assume(true);
            isConnected = false;
        }
    }

    function testSimulateUpgrade() public {
        // Deploy new implementation in test environment
        if (!isConnected) {
            vm.assume(true);
        } else {
            vm.startPrank(ADMIN_ADDRESS);

            pUSD newImplementation = new pUSD();
            UUPSUpgradeable(payable(PUSD_PROXY)).upgradeToAndCall(address(newImplementation), "");

            pUSD upgradedToken = pUSD(PUSD_PROXY);

            vm.stopPrank();
            console2.log("Upgrade simulation successful");
        }
    }

    function run() external {
        if (!isConnected) {
            vm.assume(true);
        } else {
            vm.startBroadcast(ADMIN_ADDRESS);

            // Deploy new implementation
            pUSD newImplementation = new pUSD();
            console2.log("New Implementation Address:", address(newImplementation));

            // Get current version
            pUSD currentProxy = pUSD(PUSD_PROXY);
            uint256 currentVersion = currentProxy.version();
            console2.log("Current Version:", currentVersion);

            // First upgrade the implementation
            UUPSUpgradeable(payable(PUSD_PROXY)).upgradeToAndCall(
                address(newImplementation),
                "" // No initialization data for the upgrade
            );

            // Then call reinitialize separately
            pUSD(PUSD_PROXY).reinitialize(
                ADMIN_ADDRESS, IERC20(USDC_ADDRESS), IERC20(USDT_ADDRESS), VAULT_TOKEN, TELLER_ADDRESS, ATOMIC_QUEUE
            );

            // Verify the upgrade
            uint256 newVersion = pUSD(PUSD_PROXY).version();

            pUSD upgradedToken = pUSD(PUSD_PROXY);

            //require(newVersion == currentVersion + 1, "Version not incremented");
            console2.log("Updated Implementation State:");
            console2.log("Name:", upgradedToken.name());
            console2.log("Symbol:", upgradedToken.symbol());
            console2.log("Decimals:", upgradedToken.decimals());
            console2.log("Vault:", currentVault);
            console2.log("Total Supply:", upgradedToken.totalSupply());

            console2.log("New Version:", newVersion);

            vm.stopBroadcast();
        }
    }

}
