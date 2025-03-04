// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {ArcToken} from "../src/token/ArcToken.sol";
import {ArcTokenFactory} from "../src/token/ArcTokenFactory.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract ArcTokenFactoryTest is Test {
    ArcTokenFactory public factory;
    ArcToken public implementation;
    ERC20Mock public yieldToken;
    
    address public admin;
    address public deployer;
    address public user;
    
    event TokenCreated(
        address indexed tokenAddress,
        address indexed owner,
        string name,
        string symbol,
        string assetName
    );
    event ImplementationWhitelisted(address indexed implementation);
    event ImplementationRemoved(address indexed implementation);

    function setUp() public {
        admin = address(this);
        deployer = makeAddr("deployer");
        user = makeAddr("user");

        // Deploy mock yield token
        yieldToken = new ERC20Mock();

        // Deploy implementation
        implementation = new ArcToken();

        // Deploy factory
        factory = new ArcTokenFactory();
        factory.initialize(address(implementation));
    }

    // ============ Initialization Tests ============

    function test_Initialization() public {
        assertTrue(factory.isImplementationWhitelisted(address(implementation)));
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
        vm.expectEmit(true, true, true, true);
        emit ImplementationRemoved(address(implementation));
        
        factory.removeWhitelistedImplementation(address(implementation));
        assertFalse(factory.isImplementationWhitelisted(address(implementation)));
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
        uint256 assetValuation = 1000000e18;
        uint256 initialSupply = 1000e18;
        
        // Create token and get its address
        address tokenAddress = factory.createToken(
            name,
            symbol,
            assetName,
            assetValuation,
            initialSupply,
            address(yieldToken)
        );
        
        ArcToken token = ArcToken(tokenAddress);
        
        // Verify token initialization
        assertEq(token.name(), name);
        assertEq(token.symbol(), symbol);
        assertEq(token.totalSupply(), initialSupply);
        assertTrue(token.isWhitelisted(address(this)));
        
        // Whitelist the factory for transfers
        token.addToWhitelist(address(factory));
    }

    function test_CreateMultipleTokens() public {
        // Create first token
        address token1 = factory.createToken(
            "Token 1",
            "ONE",
            "Asset 1",
            1000000e18,
            1000e18,
            address(yieldToken)
        );
        
        // Whitelist factory for first token
        ArcToken(token1).addToWhitelist(address(factory));

        // Create second token
        address token2 = factory.createToken(
            "Token 2",
            "TWO",
            "Asset 2",
            2000000e18,
            2000e18,
            address(yieldToken)
        );
        
        // Whitelist factory for second token
        ArcToken(token2).addToWhitelist(address(factory));

        assertTrue(token1 != token2);
        assertEq(ArcToken(token1).symbol(), "ONE");
        assertEq(ArcToken(token2).symbol(), "TWO");
        
        // Verify whitelisting
        assertTrue(ArcToken(token1).isWhitelisted(address(this)));
        assertTrue(ArcToken(token2).isWhitelisted(address(this)));
    }

    // ============ Error Cases Tests ============

    function test_RevertWhen_CreateTokenWithoutWhitelistedImplementation() public {
        factory.removeWhitelistedImplementation(address(implementation));
        
        vm.expectRevert("ImplementationNotWhitelisted()");
        factory.createToken(
            "Test Token",
            "TEST",
            "Test Asset",
            1000000e18,
            1000e18,
            address(yieldToken)
        );
    }

    function test_RevertWhen_CreateTokenWithZeroSupply() public {
        vm.expectRevert(abi.encodeWithSignature("InitialSupplyMustBePositive()"));
        factory.createToken(
            "Test Token",
            "TEST",
            "Test Asset",
            1000000e18,
            0,
            address(yieldToken)
        );
    }

    function test_RevertWhen_CreateTokenWithInvalidYieldToken() public {
        vm.expectRevert(abi.encodeWithSignature("InvalidYieldTokenAddress()"));
        factory.createToken(
            "Test Token",
            "TEST",
            "Test Asset",
            1000000e18,
            1000e18,
            address(0)
        );
    }

    function test_RevertWhen_InitializeTwice() public {
        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        factory.initialize(address(implementation));
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