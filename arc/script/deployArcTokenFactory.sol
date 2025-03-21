// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../src/ArcToken.sol";
import "../src/ArcTokenFactory.sol";
import "../src/proxy/ArcTokenProxy.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Script } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

/**
 * @title ArcTokenFactory Deployment Script
 * @notice Deploys a new ArcTokenFactory with proper upgradeability
 */
contract DeployArcTokenFactory is Script, Test {

    // Address of the admin - Update this to your desired admin address
    address private constant ADMIN_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;

    function test() public { }

    /**
     * @notice Deploys the ArcToken implementation and a properly upgradeable ArcTokenFactory
     */
    function run() external {
        console2.log("Starting ArcTokenFactory deployment...");
        console2.log("Admin Address:", ADMIN_ADDRESS);

        vm.startBroadcast(ADMIN_ADDRESS);

        // STEP 1: Deploy the factory implementation (new version doesn't need token implementation upfront)
        ArcTokenFactory factoryImplementation = new ArcTokenFactory();
        console2.log("ArcTokenFactory implementation deployed to:", address(factoryImplementation));

        // STEP 2: Create initialization data for the factory (no parameters in the new version)
        bytes memory initData = abi.encodeWithSelector(ArcTokenFactory.initialize.selector);

        // STEP 3: Deploy the proxy
        // NOTE: We use inline assembly to avoid ERC1967 detection issues
        address factoryProxy;
        bytes memory creationCode = type(ERC1967Proxy).creationCode;
        bytes memory bytecode = abi.encodePacked(creationCode, abi.encode(address(factoryImplementation), initData));

        assembly {
            factoryProxy := create(0, add(bytecode, 0x20), mload(bytecode))
        }

        // STEP 4: Log success
        console2.log("ArcTokenFactory proxy deployed to:", factoryProxy);

        // Get the factory instance
        ArcTokenFactory factory = ArcTokenFactory(factoryProxy);

        // No verification needed since we're using the new factory model that creates
        // implementations on demand rather than storing a central implementation

        // STEP 5: Create a test token to verify factory works
        string memory testTokenName = "Test Token";
        string memory testTokenSymbol = "TEST";
        string memory testTokenUri = "https://example.com/token/metadata";
        uint256 initialSupply = 1_000_000 * 1e18;
        address yieldToken = address(0); // Just for testing
        uint256 tokenIssuePrice = 1e18;
        uint256 totalTokenOffering = 10_000_000 * 1e18;

        try factory.createToken(
            testTokenName,
            testTokenSymbol,
            initialSupply,
            yieldToken,
            tokenIssuePrice,
            totalTokenOffering,
            testTokenUri,
            ADMIN_ADDRESS // Specify admin as the token recipient
        ) returns (address tokenAddress) {
            console2.log("Test token successfully created at:", tokenAddress);

            // Verify token implementation is tracked
            try factory.getTokenImplementation(tokenAddress) returns (address tokenImpl) {
                console2.log("Token implementation for test token:", tokenImpl);
                console2.log("Verification successful: Token implementation correctly tracked");
            } catch {
                console2.log("Verification error: Could not get token implementation");
            }
        } catch Error(string memory reason) {
            console2.log("Test token creation failed:", reason);
        } catch {
            console2.log("Test token creation failed with unknown error");
        }

        // STEP 6: Print usage instructions
        console2.log("\n---------- DEPLOYMENT SUMMARY ----------");
        console2.log("ArcTokenFactory Implementation:", address(factoryImplementation));
        console2.log("ArcTokenFactory Proxy:", factoryProxy);
        console2.log("Admin Address:", ADMIN_ADDRESS);

        console2.log("\n---------- USAGE INSTRUCTIONS ----------");
        console2.log("To create a new token:");
        console2.log("factory.createToken(");
        console2.log("  \"TokenName\",           // token name");
        console2.log("  \"SYMBOL\",              // token symbol");
        console2.log("  initialSupply,           // initial token supply");
        console2.log("  yieldTokenAddress,       // yield token address (e.g., USDC)");
        console2.log("  tokenIssuePrice,         // price at which tokens are issued (scaled by 1e18)");
        console2.log("  totalTokenOffering,      // total number of tokens available for sale");
        console2.log("  \"https://example.com/token/metadata\",  // token URI for metadata");
        console2.log(
            "  initialTokenHolder       // address that will receive the initial token supply (0x0 for msg.sender)"
        );
        console2.log(")");

        console2.log("\nTo get token implementation:");
        console2.log("factory.getTokenImplementation(tokenAddress)");

        console2.log("\nTo whitelist a new implementation:");
        console2.log("factory.whitelistImplementation(newImplementationAddress)");

        console2.log("\nTo upgrade the factory in the future:");
        console2.log("1. Deploy a new implementation: `new ArcTokenFactory()`");
        console2.log("2. Call upgradeToAndCall: `factory.upgradeToAndCall(newImplementationAddress, \"\")`");

        vm.stopBroadcast();
    }

}
