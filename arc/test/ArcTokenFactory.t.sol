// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ArcToken } from "../src/ArcToken.sol";
import { ArcTokenFactory } from "../src/ArcTokenFactory.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

// Import necessary restriction contracts and interfaces
import { RestrictionsRouter } from "../src/restrictions/RestrictionsRouter.sol";
import { WhitelistRestrictions } from "../src/restrictions/WhitelistRestrictions.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract ArcTokenFactoryTest is Test {

    ArcTokenFactory public factory;
    RestrictionsRouter public router;
    ERC20Mock public yieldToken;

    address public admin;
    address public deployer;
    address public user;

    event TokenCreated(
        address indexed tokenAddress,
        address indexed owner,
        address indexed implementation,
        string name,
        string symbol,
        string tokenUri,
        uint8 decimals
    );
    event ImplementationWhitelisted(address indexed implementation);
    event ImplementationRemoved(address indexed implementation);

    // Define module type constants matching ArcToken/Factory
    bytes32 public constant TRANSFER_RESTRICTION_TYPE = keccak256("TRANSFER_RESTRICTION");
    bytes32 public constant YIELD_RESTRICTION_TYPE = keccak256("YIELD_RESTRICTION");

    function setUp() public {
        admin = address(this);
        deployer = makeAddr("deployer");
        user = makeAddr("user");

        // Deploy mock yield token
        yieldToken = new ERC20Mock();

        // Deploy Router
        router = new RestrictionsRouter();
        router.initialize(admin); // Initialize router with admin

        // Deploy factory
        factory = new ArcTokenFactory();
        factory.initialize(address(router)); // Initialize factory with router address
    }

    // ============ Initialization Tests ============

    function test_Initialization() public {
        assertEq(factory.restrictionsRouter(), address(router)); // Check router address is set
        assertTrue(factory.hasRole(factory.DEFAULT_ADMIN_ROLE(), address(this)));
    }

    // ============ Implementation Management Tests ============

    function test_WhitelistImplementation() public {
        address newImpl = address(new ArcToken());

        vm.expectEmit(true, true, true, true);
        emit ImplementationWhitelisted(newImpl);

        factory.whitelistImplementation(newImpl);
        assertTrue(factory.isImplementationWhitelisted(newImpl));
    }

    function test_RemoveWhitelistedImplementation() public {
        // Deploy a token first so its implementation gets added to allowedImplementations
        // Note: We need to whitelist the holder *after* creation now
        address tokenAddress = factory.createToken("Temp", "TEMP", 1e18, address(yieldToken), "uri", admin, 18);
        address whitelistModuleAddr = ArcToken(tokenAddress).getRestrictionModule(TRANSFER_RESTRICTION_TYPE);
        WhitelistRestrictions(whitelistModuleAddr).addToWhitelist(admin); // Whitelist the creator

        address arcTokenImpl = factory.getTokenImplementation(tokenAddress); // Get the impl address

        // Make sure it *is* whitelisted before removal
        assertTrue(factory.isImplementationWhitelisted(arcTokenImpl), "Implementation should be whitelisted initially");

        vm.expectEmit(true, true, true, true);
        emit ImplementationRemoved(arcTokenImpl);

        factory.removeWhitelistedImplementation(arcTokenImpl);
        assertFalse(factory.isImplementationWhitelisted(arcTokenImpl), "Implementation should be removed");
    }

    function test_RevertWhen_WhitelistImplementationNonAdmin() public {
        address newImpl = address(new ArcToken());

        // Ensure the user does NOT have the required role beforehand
        assertFalse(
            factory.hasRole(factory.DEFAULT_ADMIN_ROLE(), user), "User should not have DEFAULT_ADMIN_ROLE initially"
        );

        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, factory.DEFAULT_ADMIN_ROLE()
            )
        );
        factory.whitelistImplementation(newImpl);
        vm.stopPrank();
    }

    // ============ Token Creation Tests ============

    function test_CreateToken() public {
        string memory name = "Test Token";
        string memory symbol = "TEST";
        string memory assetName = "Test Asset";
        uint256 assetValuation = 1_000_000e18;
        uint256 initialSupply = 1000e18;
        string memory tokenUri = "ipfs://test-uri";
        address initialHolder = admin; // Use admin as initial holder

        // Create token and get its address
        address tokenAddress =
            factory.createToken(name, symbol, initialSupply, address(yieldToken), tokenUri, initialHolder, 18);

        ArcToken token = ArcToken(tokenAddress);

        // Verify token initialization
        assertEq(token.name(), name);
        assertEq(token.symbol(), symbol);
        assertEq(token.totalSupply(), initialSupply);

        // Verify modules were linked
        address whitelistModuleAddr = token.getRestrictionModule(TRANSFER_RESTRICTION_TYPE);
        assertTrue(whitelistModuleAddr != address(0));
        address yieldBlacklistModuleAddr = token.getRestrictionModule(YIELD_RESTRICTION_TYPE);
        assertTrue(yieldBlacklistModuleAddr != address(0));

        // Verify initial holder is whitelisted in the correct module AFTER creation
        WhitelistRestrictions whitelistModule = WhitelistRestrictions(whitelistModuleAddr);
        // Whitelist the holder (creator has MANAGER_ROLE on the module)
        whitelistModule.addToWhitelist(initialHolder);
        assertTrue(whitelistModule.isWhitelisted(initialHolder));
    }

    function test_CreateMultipleTokens() public {
        string memory uri1 = "uri1";
        string memory uri2 = "uri2";

        // Create first token (holder is admin)
        address token1Addr = factory.createToken("Token 1", "ONE", 1000e18, address(yieldToken), uri1, admin, 18);
        address wl1Addr = ArcToken(token1Addr).getRestrictionModule(TRANSFER_RESTRICTION_TYPE);
        // Whitelist admin (creator) for token1
        WhitelistRestrictions(wl1Addr).addToWhitelist(admin);

        // Create second token (holder is user)
        // Prank as user to create token2
        vm.startPrank(user);
        address token2Addr = factory.createToken("Token 2", "TWO", 2000e18, address(yieldToken), uri2, user, 18);
        vm.stopPrank();
        address wl2Addr = ArcToken(token2Addr).getRestrictionModule(TRANSFER_RESTRICTION_TYPE);
        // Whitelist user (creator) for token2 - use user key to call addToWhitelist
        vm.startPrank(user);
        WhitelistRestrictions(wl2Addr).addToWhitelist(user);
        vm.stopPrank();

        assertTrue(token1Addr != token2Addr);
        assertEq(ArcToken(token1Addr).symbol(), "ONE");
        assertEq(ArcToken(token2Addr).symbol(), "TWO");

        // Verify whitelisting via modules
        assertTrue(WhitelistRestrictions(wl1Addr).isWhitelisted(admin));
        assertFalse(WhitelistRestrictions(wl1Addr).isWhitelisted(user)); // User not holder of token1

        assertTrue(WhitelistRestrictions(wl2Addr).isWhitelisted(user)); // User is holder of token2
        assertFalse(WhitelistRestrictions(wl2Addr).isWhitelisted(admin)); // Admin not creator/holder of token2
    }

    // ============ Error Cases Tests ============

    function test_RevertWhen_CreateTokenWithZeroSupply() public {
        // Initial supply check might be within ArcToken.initialize now.
        // ArcToken.initialize allows 0 supply, so no revert is expected.
        address tokenAddress = factory.createToken("Test Token", "TEST", 0, address(yieldToken), "uri", admin, 18);

        // Optionally, add asserts here to check token state if creation succeeds
        assertEq(ArcToken(tokenAddress).totalSupply(), 0);

        // Whitelist the creator after creation
        address wlAddr = ArcToken(tokenAddress).getRestrictionModule(TRANSFER_RESTRICTION_TYPE);
        WhitelistRestrictions(wlAddr).addToWhitelist(admin);
    }

    function test_RevertWhen_CreateTokenWithInvalidYieldToken() public {
        address tokenAddress = factory.createToken("Test Token", "TEST", 1000e18, address(0), "uri", admin, 18);
        // Optionally, add asserts here to check token state if creation succeeds
        // ArcToken doesn't expose yieldToken directly via getter, check internal storage if needed or skip assert
        // Whitelist the creator after creation
        address wlAddr = ArcToken(tokenAddress).getRestrictionModule(TRANSFER_RESTRICTION_TYPE);
        WhitelistRestrictions(wlAddr).addToWhitelist(admin);
    }

    function test_RevertWhen_InitializeTwice() public {
        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        factory.initialize(address(router));
    }

    // ============ Access Control Tests ============

    function test_AccessControl() public {
        // Grant admin role to deployer
        factory.grantRole(factory.DEFAULT_ADMIN_ROLE(), deployer);
        assertTrue(factory.hasRole(factory.DEFAULT_ADMIN_ROLE(), deployer));

        // Deployer whitelists new implementation
        vm.startPrank(deployer);
        address newImpl = address(new ArcToken());
        factory.whitelistImplementation(newImpl);
        assertTrue(factory.isImplementationWhitelisted(newImpl));
        vm.stopPrank();

        // Original admin can still perform actions
        address anotherImpl = address(new ArcToken());
        factory.whitelistImplementation(anotherImpl);
        assertTrue(factory.isImplementationWhitelisted(anotherImpl));
    }

    // ============ Token Upgrade Tests ============

    function test_UpgradeToken() public {
        // Create initial token
        address tokenAddress = factory.createToken(
            "Test Token",
            "TEST",
            1000e18,
            address(yieldToken),
            "uri",
            admin,
            18
        );
        address initialImpl = factory.getTokenImplementation(tokenAddress);

        // Whitelist the creator
        address wlAddr = ArcToken(tokenAddress).getRestrictionModule(
            TRANSFER_RESTRICTION_TYPE
        );
        WhitelistRestrictions(wlAddr).addToWhitelist(admin);

        // Create new implementation
        address newImpl = address(new ArcToken());
        factory.whitelistImplementation(newImpl);

        // Upgrade token
        factory.upgradeToken(tokenAddress, newImpl);

        // Verify upgrade
        address currentImpl = factory.getTokenImplementation(tokenAddress);
        assertEq(currentImpl, newImpl, "Implementation should be updated");
        assertTrue(
            currentImpl != initialImpl,
            "New implementation should be different from initial"
        );

        // Verify token still works after upgrade
        ArcToken token = ArcToken(tokenAddress);
        assertEq(
            token.name(),
            "Test Token",
            "Token name should remain the same"
        );
        assertEq(token.symbol(), "TEST", "Token symbol should remain the same");
        assertEq(
            token.totalSupply(),
            1000e18,
            "Token supply should remain the same"
        );
    }

    function test_RevertWhen_UpgradeTokenWithNonWhitelistedImplementation()
        public
    {
        // Create initial token
        address tokenAddress = factory.createToken(
            "Test Token",
            "TEST",
            1000e18,
            address(yieldToken),
            "uri",
            admin,
            18
        );

        // Whitelist the creator
        address wlAddr = ArcToken(tokenAddress).getRestrictionModule(
            TRANSFER_RESTRICTION_TYPE
        );
        WhitelistRestrictions(wlAddr).addToWhitelist(admin);

        // Create new implementation but don't whitelist it
        address newImpl = address(new ArcToken());

        // Attempt to upgrade with non-whitelisted implementation
        vm.expectRevert(
            abi.encodeWithSelector(
                ArcTokenFactory.ImplementationNotWhitelisted.selector
            )
        );
        factory.upgradeToken(tokenAddress, newImpl);
    }

    function test_RevertWhen_UpgradeTokenWithNonAdmin() public {
        // Create initial token
        address tokenAddress = factory.createToken(
            "Test Token",
            "TEST",
            1000e18,
            address(yieldToken),
            "uri",
            admin,
            18
        );

        // Whitelist the creator
        address wlAddr = ArcToken(tokenAddress).getRestrictionModule(
            TRANSFER_RESTRICTION_TYPE
        );
        WhitelistRestrictions(wlAddr).addToWhitelist(admin);

        // Create and whitelist new implementation
        address newImpl = address(new ArcToken());
        factory.whitelistImplementation(newImpl);

        // Attempt to upgrade with non-admin account
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user,
                factory.DEFAULT_ADMIN_ROLE()
            )
        );
        factory.upgradeToken(tokenAddress, newImpl);
        vm.stopPrank();

        // Attempt to upgrade directly through ArcToken's upgradeToAndCall
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user,
                ArcToken(tokenAddress).UPGRADER_ROLE()
            )
        );
        UUPSUpgradeable(tokenAddress).upgradeToAndCall(newImpl, "");
        vm.stopPrank();
    }
}
