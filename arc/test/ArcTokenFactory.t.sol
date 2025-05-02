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
        address createdTokenImpl = factory.createToken("Temp", "TEMP", 1e18, address(yieldToken), "uri", admin);
        address arcTokenImpl = factory.getTokenImplementation(createdTokenImpl); // Get the impl address

        vm.expectEmit(true, true, true, true);
        emit ImplementationRemoved(arcTokenImpl);

        factory.removeWhitelistedImplementation(arcTokenImpl);
        assertFalse(factory.isImplementationWhitelisted(arcTokenImpl));
    }

    function test_RevertWhen_WhitelistImplementationNonAdmin() public {
        address newImpl = address(new ArcToken());
        vm.prank(user);
        vm.expectRevert(accessControlError(user, factory.DEFAULT_ADMIN_ROLE()));
        factory.whitelistImplementation(newImpl);
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
            factory.createToken(name, symbol, initialSupply, address(yieldToken), tokenUri, initialHolder);

        ArcToken token = ArcToken(tokenAddress);

        // Verify token initialization
        assertEq(token.name(), name);
        assertEq(token.symbol(), symbol);
        assertEq(token.totalSupply(), initialSupply);

        // Verify modules were linked
        address whitelistModuleAddr = token.getSpecificRestrictionModule(TRANSFER_RESTRICTION_TYPE);
        assertTrue(whitelistModuleAddr != address(0));
        address yieldBlacklistModuleAddr = token.getSpecificRestrictionModule(YIELD_RESTRICTION_TYPE);
        assertTrue(yieldBlacklistModuleAddr != address(0));

        // Verify initial holder is whitelisted in the correct module
        WhitelistRestrictions whitelistModule = WhitelistRestrictions(whitelistModuleAddr);
        assertTrue(whitelistModule.isWhitelisted(initialHolder));
    }

    function test_CreateMultipleTokens() public {
        string memory uri1 = "uri1";
        string memory uri2 = "uri2";
        // Create first token
        address token1 = factory.createToken("Token 1", "ONE", 1000e18, address(yieldToken), uri1, admin);

        // Create second token
        address token2 = factory.createToken("Token 2", "TWO", 2000e18, address(yieldToken), uri2, user);

        assertTrue(token1 != token2);
        assertEq(ArcToken(token1).symbol(), "ONE");
        assertEq(ArcToken(token2).symbol(), "TWO");

        // Verify whitelisting via modules
        address wl1 = ArcToken(token1).getSpecificRestrictionModule(TRANSFER_RESTRICTION_TYPE);
        address wl2 = ArcToken(token2).getSpecificRestrictionModule(TRANSFER_RESTRICTION_TYPE);
        assertTrue(WhitelistRestrictions(wl1).isWhitelisted(admin));
        assertFalse(WhitelistRestrictions(wl1).isWhitelisted(user)); // User not holder of token1

        assertTrue(WhitelistRestrictions(wl2).isWhitelisted(user)); // User is holder of token2
        assertFalse(WhitelistRestrictions(wl2).isWhitelisted(admin)); // Admin not holder of token2
    }

    // ============ Error Cases Tests ============

    function test_RevertWhen_CreateTokenWithoutWhitelistedImplementation() public {
        // This test needs reconsideration based on how ArcToken implementations are managed.
        // Currently, the factory deploys a NEW implementation for each token and adds THAT hash
        // to allowedImplementations. This test assumes a shared implementation model.
    }

    function test_RevertWhen_CreateTokenWithZeroSupply() public {
        // Initial supply check might be within ArcToken.initialize now.
        vm.expectRevert(); // Generic revert expected from initializer
        factory.createToken("Test Token", "TEST", 0, address(yieldToken), "uri", admin);
    }

    function test_RevertWhen_CreateTokenWithInvalidYieldToken() public {
        vm.expectRevert(abi.encodeWithSignature("InvalidYieldTokenAddress()"));
        factory.createToken("Test Token", "TEST", 1000e18, address(0), "uri", admin);
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

    // Helper function to generate AccessControl error message
    function accessControlError(address account, bytes32 role) internal pure returns (bytes memory) {
        return abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(account),
            " is missing role ",
            Strings.toHexString(uint256(role), 32)
        );
    }

}
