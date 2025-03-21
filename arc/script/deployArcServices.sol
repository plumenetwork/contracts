// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../src/ArcToken.sol";
import "../src/ArcTokenFactory.sol";
import "../src/ArcTokenPurchase.sol";
import "../src/proxy/ArcTokenProxy.sol";
import { Script } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

/**
 * @title Arc Services Deployment Script
 * @notice Deploys and configures the Arc token factory and purchase contracts
 */
contract DeployArcServices is Script, Test {

    // Address of the admin - Update this to your address
    address private constant ADMIN_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;

    // IMPORTANT: Update this with your deployed MockUSDC address
    address private constant PURCHASE_TOKEN_ADDRESS = 0x41b199a4138BFA31b32f58Adb167F6981d5A99Dd;

    // IMPORTANT: Update this with your deployed MockUSDC address
    address private constant ARC_TOKEN_ADDRESS = 0x09814A253358051C3C3c52d01CFa54E302bD8d7f;

    function test() public { }

    /**
     * @notice Deploys and initializes ArcToken, ArcTokenFactory, and ArcTokenPurchase
     */
    function run() external {
        console2.log("Using purchase token address:", PURCHASE_TOKEN_ADDRESS);

        vm.startBroadcast(ADMIN_ADDRESS);

        // Step 1: Deploy the ArcToken implementation - this will be used by the factory
        ArcToken tokenImplementation = ArcToken(ARC_TOKEN_ADDRESS);
        console2.log("ArcToken implementation deployed to:", address(tokenImplementation));

        // Step 2: Deploy the ArcTokenFactory
        ArcTokenFactory factoryImpl = new ArcTokenFactory();
        console2.log("ArcTokenFactory implementation deployed to:", address(factoryImpl));

        // Create initialization data for factory - using encodeWithSelector instead of encodeCall
        bytes memory factoryInitData = abi.encodeWithSelector(ArcTokenFactory.initialize.selector);

        // Deploy the proxy for factory using ArcTokenProxy
        ArcTokenProxy factoryProxy = new ArcTokenProxy(address(factoryImpl), factoryInitData);

        ArcTokenFactory factory = ArcTokenFactory(address(factoryProxy));
        console2.log("ArcTokenFactory proxy deployed to:", address(factoryProxy));

        // Step 3: Deploy ArcTokenPurchase with proxy
        ArcTokenPurchase purchaseImpl = new ArcTokenPurchase();
        console2.log("ArcTokenPurchase implementation deployed to:", address(purchaseImpl));

        // Create initialization data for the purchase contract - using encodeWithSelector instead of encodeCall
        bytes memory purchaseInitData = abi.encodeWithSelector(ArcTokenPurchase.initialize.selector, ADMIN_ADDRESS);

        // Deploy the proxy for purchase contract using ArcTokenProxy
        ArcTokenProxy purchaseProxy = new ArcTokenProxy(address(purchaseImpl), purchaseInitData);

        ArcTokenPurchase purchase = ArcTokenPurchase(address(purchaseProxy));
        console2.log("ArcTokenPurchase proxy deployed to:", address(purchaseProxy));

        // Step 4: Configure the purchase contract with the purchase token
        purchase.setPurchaseToken(PURCHASE_TOKEN_ADDRESS);
        console2.log("ArcTokenPurchase configured with purchase token:", PURCHASE_TOKEN_ADDRESS);

        // Log deployment summary
        console2.log("\n---------- DEPLOYMENT SUMMARY ----------");
        console2.log("ArcToken Implementation:", address(tokenImplementation));
        console2.log("ArcTokenFactory Implementation:", address(factoryImpl));
        console2.log("ArcTokenFactory Proxy:", address(factoryProxy));
        console2.log("ArcTokenPurchase Implementation:", address(purchaseImpl));
        console2.log("ArcTokenPurchase Proxy:", address(purchaseProxy));
        console2.log("Purchase Token:", PURCHASE_TOKEN_ADDRESS);
        console2.log("Admin:", ADMIN_ADDRESS);

        // Log usage instructions
        console2.log("\n---------- USAGE INSTRUCTIONS ----------");
        console2.log("1. To create a new token, call the factory's createToken function:");
        console2.log(
            "   factory.createToken(name, symbol, assetName, initialSupply, yieldToken, tokenIssuePrice, totalTokenOffering)"
        );
        console2.log("");
        console2.log("2. To enable token sales, call the purchase contract's enableToken function:");
        console2.log("   purchase.enableToken(tokenAddress, numberOfTokensForSale, tokenPrice)");
        console2.log("");
        console2.log("3. To configure a token's storefront, call setStorefrontConfig:");
        console2.log("   purchase.setStorefrontConfig(tokenAddress, domain, title, description, ...)");

        vm.stopBroadcast();
    }

}
