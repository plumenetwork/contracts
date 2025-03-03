// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../src/token/ArcToken.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title SFeTi70 Deployment Script
 * @notice Deploys and configures an ArcToken specifically for the SFeTi70 Ferro Titanium Offtake Agreement
 */
contract SFeTi70Deployer {

    // Token configuration constants
    string public constant TOKEN_NAME = "SFeTi70";
    string public constant TOKEN_SYMBOL = "SFeTi70";
    string public constant ASSET_NAME = "Ferro Titanium Offtake Agreement";

    // Financial metrics (all monetary values scaled by 1e18)
    uint256 public constant TOTAL_TOKEN_OFFERING = 100; // Total supply
    uint256 public constant TOKEN_ISSUE_PRICE = 4200 * 1e18; // $4,200.00
    uint256 public constant ACCRUAL_RATE_PER_SECOND = 6_342_013_888_889; // ~0.054795% daily
    uint256 public constant INITIAL_ASSET_VALUATION = 420_000 * 1e18; // $420,000.00

    /**
     * @notice Deploys and initializes the SFeTi70 token
     * @param proxyAdmin Address of the proxy admin
     * @param yieldToken Address of the yield token (e.g., USDC)
     * @return proxy Address of the deployed proxy contract
     */
    function deploy(address proxyAdmin, address yieldToken) external returns (address proxy) {
        // Deploy implementation
        ArcToken implementation = new ArcToken();

        // Create proxy
        TransparentUpgradeableProxy tokenProxy =
            new TransparentUpgradeableProxy(address(implementation), proxyAdmin, "");

        // Get ArcToken interface of proxy
        ArcToken token = ArcToken(address(tokenProxy));

        // Initialize token with SFeTi70 configuration
        token.initialize(
            TOKEN_NAME,
            TOKEN_SYMBOL,
            ASSET_NAME,
            INITIAL_ASSET_VALUATION,
            TOTAL_TOKEN_OFFERING, // Initial supply equals total offering
            yieldToken,
            TOKEN_ISSUE_PRICE,
            ACCRUAL_RATE_PER_SECOND,
            TOTAL_TOKEN_OFFERING
        );

        // Set base URI for metadata
        token.setBaseURI("https://api.ferrox.io/tokens/sfeti70/");

        return address(tokenProxy);
    }

}
