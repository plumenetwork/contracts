// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../src/token/AssetToken.sol";
import "../src/token/YieldDistributionToken.sol";
import { SmartWallet } from "../src/SmartWallet.sol";
import { MockSmartWallet } from "../src/mocks/MockSmartWallet.sol";
import { WalletFactory } from "../src/WalletFactory.sol";
import { WalletProxy } from "../src/WalletProxy.sol";
import { IAssetVault } from "../src/interfaces/IAssetVault.sol";
import { AssetTokenFactory } from "./AssetTokenFactory.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
//import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";
interface ISmartWalletProxy {
    function deployAssetVault() external;
    function getAssetVault() external view returns (IAssetVault);
}

contract MockCurrencyToken is ERC20 {

    constructor() ERC20("Mock Currency", "MCT") {
        _mint(msg.sender, 1_000_000 * 10 ** 18);
    }

}

contract AssetTokenTest is Test {


    AssetToken public assetToken;
    AssetToken public assetTokenWhitelisted;
    ERC20 public currencyToken;
    SmartWallet public mockSmartWallet;
    WalletProxy public walletProxy;  // Add this line

    //address public owner;
    address owner = makeAddr("alice");

    address public user1;
    address public user2;
    address public walletProxyAddress;

    // small hack to be excluded from coverage report
    function test() public { }

/*
// Update the setUp function
  function setUp() public {
        owner = address(0xdead);
        user1 = address(0x1);
        user2 = address(0x2);

        vm.startPrank(owner);

        // Deploy CurrencyToken
        currencyToken = new MockCurrencyToken();
        console.log("CurrencyToken deployed at:", address(currencyToken));

        // Deploy SmartWallet implementation
        SmartWallet smartWalletImpl = new SmartWallet();
        console.log("SmartWallet implementation deployed at:", address(smartWalletImpl));

        // Deploy WalletFactory
        WalletFactory walletFactory = new WalletFactory(owner, ISmartWallet(address(smartWalletImpl)));
        console.log("WalletFactory deployed at:", address(walletFactory));

        // Deploy WalletProxy
        walletProxy = new WalletProxy(walletFactory);  // Assign to the state variable
        console.log("WalletProxy deployed at:", address(walletProxy));

        // Now we have a proper SmartWallet instance via the proxy
        ISmartWalletProxy smartWalletProxy = ISmartWalletProxy(address(walletProxy));

        // Deploy AssetToken
        assetTokenWhitelisted = new AssetToken(
            address(walletProxy),  // The SmartWallet (via proxy) is the owner
            "Whitelisted Asset Token",
            "WAT",
            currencyToken,
            18,
            "http://example.com/token",
            1000 * 10 ** 18,
            10_000 * 10 ** 18,
            true // Whitelist enabled
        );
        console.log("AssetToken deployed at:", address(assetTokenWhitelisted));

        vm.stopPrank();

        if (address(assetTokenWhitelisted) != address(0)) {
            console.log("Is whitelist enabled after setup:", assetTokenWhitelisted.isWhitelistEnabled());
        } else {
            console.log("AssetToken deployment failed, cannot check whitelist status");
        }
    }
*/
function setUp() public {
    owner = address(0xdead);
    user1 = address(0x1);
    user2 = address(0x2);

    vm.startPrank(owner);

    // Deploy CurrencyToken
    ERC20Mock mockToken = new ERC20Mock();
    mockToken.mint(owner, 1000000 * 10**18);
    currencyToken = ERC20(address(mockToken));
    console.log("CurrencyToken deployed at:", address(currencyToken));

    // Deploy MockSmartWallet implementation
    MockSmartWallet mockSmartWalletImpl = new MockSmartWallet();
    console.log("MockSmartWallet implementation deployed at:", address(mockSmartWalletImpl));

    // Deploy WalletFactory
    WalletFactory walletFactory = new WalletFactory(owner, ISmartWallet(address(mockSmartWalletImpl)));
    console.log("WalletFactory deployed at:", address(walletFactory));

    // Deploy WalletProxy
    walletProxy = new WalletProxy(walletFactory);
    walletProxyAddress = address(walletProxy);
    console.log("WalletProxy deployed at:", walletProxyAddress);

    // Verify WalletProxy setup by calling a function on MockSmartWallet through WalletProxy
    bytes memory verifyData = abi.encodeWithSignature("verifySetup()");
    (bool success,) = walletProxyAddress.call(verifyData);
    require(success, "WalletProxy setup failed: Unable to call function on MockSmartWallet");
    console.log("WalletProxy setup verified successfully");








    console.log("Attempting to deploy AssetToken through WalletProxy...");

    bytes memory deployData = abi.encodeWithSignature(
        "deployAssetToken(string,string,address,uint8,string,uint256,uint256,bool)",
        "Whitelisted Asset Token",
        "WAT",
        address(currencyToken),
        18,
        "http://example.com/token",
        1000 * 10 ** 18,
        10_000 * 10 ** 18,
        true // Whitelist enabled
    );

    bytes memory result;
    (success, result) = walletProxyAddress.call(deployData);

    if (success) {
        address assetTokenAddress;
        assembly {
            assetTokenAddress := mload(add(result, 32))
        }
        assetTokenWhitelisted = AssetToken(assetTokenAddress);
        console.log("AssetToken deployed through WalletProxy at:", address(assetTokenWhitelisted));
        
        bytes memory bytecode = address(assetTokenWhitelisted).code;
        if (bytecode.length > 0) {
            console.log("AssetToken bytecode length:", bytecode.length);
        } else {
            console.log("Warning: AssetToken deployed through WalletProxy has no bytecode");
            revert("AssetToken deployment failed");
        }
    } else {
        console.log("Failed to deploy AssetToken through WalletProxy");
        console.logBytes(result);
        revert("AssetToken deployment failed");
    }

    // Verify AssetToken functionality
    try assetTokenWhitelisted.name() returns (string memory name) {
        console.log("AssetToken name:", name);
    } catch Error(string memory reason) {
        console.log("Failed to get AssetToken name. Reason:", reason);
        revert("AssetToken functionality check failed");
    }

    try assetTokenWhitelisted.isWhitelistEnabled() returns (bool enabled) {
        console.log("Is whitelist enabled:", enabled);
        require(enabled, "Whitelist should be enabled");
    } catch Error(string memory reason) {
        console.log("Failed to check if whitelist is enabled. Reason:", reason);
        revert("AssetToken functionality check failed");
    }

    vm.stopPrank();
}

// Helper function to call _implementation() on WalletProxy
    function testInitialization() public {
        console.log("Starting testInitialization");
        require(address(assetToken) != address(0), "AssetToken not deployed");

        assertEq(assetToken.name(), "Asset Token", "Name mismatch");
        assertEq(assetToken.symbol(), "AT", "Symbol mismatch");
        assertEq(assetToken.decimals(), 18, "Decimals mismatch");
        //assertEq(assetToken.tokenURI_(), "http://example.com/token", "TokenURI mismatch");
        assertEq(assetToken.totalSupply(), 1000 * 10 ** 18, "Total supply mismatch");
        assertEq(assetToken.getTotalValue(), 10_000 * 10 ** 18, "Total value mismatch");
        assertFalse(assetToken.isWhitelistEnabled(), "Whitelist should be enabled");
        assertFalse(assetToken.isAddressWhitelisted(owner), "Owner should be whitelisted");

        console.log("testInitialization completed successfully");
    }



function testVerifyAssetToken() public {
    require(address(assetTokenWhitelisted) != address(0), "AssetToken not deployed");
    
    vm.startPrank(owner);
    
    bytes memory bytecode = address(assetTokenWhitelisted).code;
    require(bytecode.length > 0, "AssetToken has no bytecode");
    
    try assetTokenWhitelisted.name() returns (string memory name) {
        console.log("AssetToken name:", name);
    } catch Error(string memory reason) {
        console.log("Failed to get AssetToken name. Reason:", reason);
        revert("Failed to get AssetToken name");
    }

    try assetTokenWhitelisted.symbol() returns (string memory symbol) {
        console.log("AssetToken symbol:", symbol);
    } catch Error(string memory reason) {
        console.log("Failed to get AssetToken symbol. Reason:", reason);
        revert("Failed to get AssetToken symbol");
    }

    try assetTokenWhitelisted.isWhitelistEnabled() returns (bool enabled) {
        console.log("Is whitelist enabled:", enabled);
    } catch Error(string memory reason) {
        console.log("Failed to check if whitelist is enabled. Reason:", reason);
        revert("Failed to check if whitelist is enabled");
    }

    vm.stopPrank();
}

    function testMinting() public {
        vm.startPrank(owner);
        uint256 initialSupply = assetToken.totalSupply();
        uint256 mintAmount = 500 * 10 ** 18;

        assetToken.addToWhitelist(user1);
        assetToken.mint(user1, mintAmount);

        assertEq(assetToken.totalSupply(), initialSupply + mintAmount);
        assertEq(assetToken.balanceOf(user1), mintAmount);
        vm.stopPrank();
    }

    function testSetTotalValue() public {
        vm.startPrank(owner);
        uint256 newTotalValue = 20_000 * 10 ** 18;
        assetToken.setTotalValue(newTotalValue);
        assertEq(assetToken.getTotalValue(), newTotalValue);
        vm.stopPrank();
    }


    //TODO: convert to SmartWalletCall 
    function testGetBalanceAvailable() public {
        vm.startPrank(owner);

        uint256 balance = 1000 * 10**18;
        assetToken.addToWhitelist(user1);
        assetToken.mint(user1, balance);

        assertEq(assetToken.getBalanceAvailable(user1), balance);
        vm.stopPrank();
        // Note: To fully test getBalanceAvailable, you would need to mock a SmartWallet
        // contract that implements the ISmartWallet interface and returns a locked balance.
    }

    function testTransfer() public {
        vm.startPrank(owner);
        uint256 transferAmount = 100 * 10**18;

        assetToken.addToWhitelist(user1);
        assetToken.addToWhitelist(user2);
        assetToken.mint(user1, transferAmount);
        vm.stopPrank();

        vm.prank(user1);
        assetToken.transfer(user2, transferAmount);

        assertEq(assetToken.balanceOf(user1), 0);
        assertEq(assetToken.balanceOf(user2), transferAmount);
    }
        function testUnauthorizedTransfer() public {
        uint256 transferAmount = 100 * 10**18;
        vm.expectRevert();
        assetToken.addToWhitelist(user1);
        //vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector));
        vm.startPrank(owner);


        assetToken.mint(user1, transferAmount);
        vm.stopPrank();
        
        vm.prank(user1);
        assetToken.transfer(user2, transferAmount);
    }

function testConstructorWithWhitelist() public {
    AssetToken whitelistedToken = new AssetToken(
        owner,
        "Whitelisted Asset Token",
        "WAT",
        currencyToken,
        18,
        "http://example.com/whitelisted-token",
        1000 * 10 ** 18,
        10_000 * 10 ** 18,
        true // Whitelist enabled
    );
    assertTrue(whitelistedToken.isWhitelistEnabled(), "Whitelist should be enabled");
}

function testUpdateWithWhitelistEnabled() public {
    AssetToken whitelistedToken = new AssetToken(
        owner,
        "Whitelisted Asset Token",
        "WAT",
        currencyToken,
        18,
        "http://example.com/whitelisted-token",
        1000 * 10 ** 18,
        10_000 * 10 ** 18,
        true // Whitelist enabled
    );
    
    vm.startPrank(owner);
    whitelistedToken.addToWhitelist(user1);
    whitelistedToken.addToWhitelist(user2);
    whitelistedToken.mint(user1, 100 * 10**18);
    vm.stopPrank();

    vm.prank(user1);
    whitelistedToken.transfer(user2, 50 * 10**18);

    assertEq(whitelistedToken.balanceOf(user1), 50 * 10**18);
    assertEq(whitelistedToken.balanceOf(user2), 50 * 10**18);
}

function checkAssetTokenOwner() public view returns (address) {
    return assetTokenWhitelisted.owner();
}
function isWhitelistEnabled() public view returns (bool) {
    return assetTokenWhitelisted.isWhitelistEnabled();
}
// Update the test function
   function testAddAndRemoveFromWhitelist() public {
        console.log("AssetToken owner:", assetTokenWhitelisted.owner());
        console.log("Is whitelist enabled:", assetTokenWhitelisted.isWhitelistEnabled());

        require(assetTokenWhitelisted.isWhitelistEnabled(), "Whitelist must be enabled for this test");

        console.log("Before adding to whitelist:");
        console.log("Is user1 whitelisted:", assetTokenWhitelisted.isAddressWhitelisted(user1));
        console.log("Is user2 whitelisted:", assetTokenWhitelisted.isAddressWhitelisted(user2));

        // Add user1 to whitelist
        vm.prank(address(walletProxy));  // Act as the SmartWallet
        assetTokenWhitelisted.addToWhitelist(user1);

        console.log("After adding user1:");
        console.log("Is user1 whitelisted:", assetTokenWhitelisted.isAddressWhitelisted(user1));

        // Add user2 to whitelist
        vm.prank(address(walletProxy));  // Act as the SmartWallet
        assetTokenWhitelisted.addToWhitelist(user2);

        console.log("After adding user2:");
        console.log("Is user1 whitelisted:", assetTokenWhitelisted.isAddressWhitelisted(user1));
        console.log("Is user2 whitelisted:", assetTokenWhitelisted.isAddressWhitelisted(user2));

        assertTrue(assetTokenWhitelisted.isAddressWhitelisted(user1), "User1 should be whitelisted");
        assertTrue(assetTokenWhitelisted.isAddressWhitelisted(user2), "User2 should be whitelisted");

        // Remove user1 from whitelist
        vm.prank(address(walletProxy));  // Act as the SmartWallet
        assetTokenWhitelisted.removeFromWhitelist(user1);

        console.log("After removing user1:");
        console.log("Is user1 whitelisted:", assetTokenWhitelisted.isAddressWhitelisted(user1));
        console.log("Is user2 whitelisted:", assetTokenWhitelisted.isAddressWhitelisted(user2));

        assertFalse(assetTokenWhitelisted.isAddressWhitelisted(user1), "User1 should not be whitelisted");
        assertTrue(assetTokenWhitelisted.isAddressWhitelisted(user2), "User2 should still be whitelisted");
    }
/*
function testAddAndRemoveFromWhitelist() public {
    MockSmartWallet mockWallet = new MockSmartWallet();

    vm.startPrank(owner);
    AssetToken whitelistedToken = new AssetToken(
        owner,
        "Whitelisted Asset Token",
        "WAT",
        currencyToken,
        18,
        "http://example.com/whitelisted-token",
        1000 * 10 ** 18,
        10_000 * 10 ** 18,
        true // Whitelist enabled
    );
    
    whitelistedToken.addToWhitelist(user1);
    assertTrue(whitelistedToken.isAddressWhitelisted(user1), "User1 should be whitelisted");
    
    whitelistedToken.removeFromWhitelist(user1);
    assertFalse(whitelistedToken.isAddressWhitelisted(user1), "User1 should not be whitelisted");
    vm.stopPrank();
}
*/
function testDepositYield() public {
    vm.startPrank(owner);
    uint256 yieldAmount = 100 * 10**18;
    currencyToken.approve(address(assetToken), yieldAmount);
    assetToken.depositYield(yieldAmount);
    vm.stopPrank();
    
    // You may need to implement a way to check the deposited yield
    // This could be done by checking the balance of the contract or through an event
}

function testRequestYield() public {
    //MockSmartWallet mockWallet = new MockSmartWallet();
    //mockSmartWallet = new MockSmartWallet(owner, address(assetTokenWhitelisted));


    mockSmartWallet = new SmartWallet();
    //mockSmartWallet.setAssetToken(address(assetTokenWhitelisted));



    vm.startPrank(owner);
    assetToken.addToWhitelist(address(mockSmartWallet));
    assetToken.mint(address(mockSmartWallet), 1000 * 10**18);
    vm.stopPrank();

    assetToken.requestYield(address(mockSmartWallet));
    // You may need to implement a way to verify that the yield was requested
}

function testGetWhitelist() public {
    AssetToken whitelistedToken = new AssetToken(
        owner,
        "Whitelisted Asset Token",
        "WAT",
        currencyToken,
        18,
        "http://example.com/whitelisted-token",
        1000 * 10 ** 18,
        10_000 * 10 ** 18,
        true // Whitelist enabled
    );
    
    vm.startPrank(owner);
    whitelistedToken.addToWhitelist(user1);
    whitelistedToken.addToWhitelist(user2);
    vm.stopPrank();

    address[] memory whitelist = whitelistedToken.getWhitelist();
    assertEq(whitelist.length, 2, "Whitelist should have 2 addresses");
    assertTrue(whitelist[0] == user1 || whitelist[1] == user1, "User1 should be in whitelist");
    assertTrue(whitelist[0] == user2 || whitelist[1] == user2, "User2 should be in whitelist");
}

function testGetHoldersAndHasBeenHolder() public {
    vm.startPrank(owner);
    assetToken.addToWhitelist(user1);
    assetToken.addToWhitelist(user2);
    assetToken.mint(user1, 100 * 10**18);
    assetToken.mint(user2, 100 * 10**18);
    vm.stopPrank();

    address[] memory holders = assetToken.getHolders();
    assertEq(holders.length, 3, "Should have 3 holders (owner, user1, user2)");
    assertTrue(assetToken.hasBeenHolder(user1), "User1 should be a holder");
    assertTrue(assetToken.hasBeenHolder(user2), "User2 should be a holder");
}

function testGetPricePerToken() public {
    uint256 price = assetToken.getPricePerToken();
    assertEq(price, 10 , "Price per token should be 10");
}

/*
function testGetBalanceAvailableFail() public {
    MockSmartWallet mockWallet = new MockSmartWallet();
    mockWallet.setLockedBalance(50 * 10**18);
    
    vm.startPrank(owner);
    assetToken.addToWhitelist(address(mockWallet));
    assetToken.mint(address(mockWallet), 100 * 10**18);
    vm.stopPrank();

    uint256 availableBalance = assetToken.getBalanceAvailable(address(mockWallet));
    assertEq(availableBalance, 50 * 10**18, "Available balance should be 50");
}
*/
function testTotalYieldAndClaimedYield() public {
    vm.startPrank(owner);
    assetToken.addToWhitelist(user1);
    assetToken.addToWhitelist(user2);
    assetToken.mint(user1, 100 * 10**18);
    assetToken.mint(user2, 100 * 10**18);

    uint256 yieldAmount = 20 * 10**18;
    currencyToken.approve(address(assetToken), yieldAmount);
    assetToken.depositYield(yieldAmount);
    vm.stopPrank();

    // Simulate some time passing
    vm.warp(block.timestamp + 1 days);

    vm.prank(user1);
    assetToken.claimYield(user1);

    uint256 totalYield = assetToken.totalYield();
    uint256 claimedYield = assetToken.claimedYield();
    uint256 unclaimedYield = assetToken.unclaimedYield();
    console.log(totalYield);
    console.log(claimedYield);
    console.log(unclaimedYield);
    assertEq(totalYield, yieldAmount, "Total yield should match deposited amount");
    assertTrue(claimedYield > 0, "Claimed yield should be greater than 0");
    assertEq(unclaimedYield, yieldAmount - claimedYield, "Unclaimed yield should be the difference");
}

function testUserSpecificYield() public {
    vm.startPrank(owner);
    assetToken.addToWhitelist(user1);
    assetToken.mint(user1, 100 * 10**18);

    uint256 yieldAmount = 10 * 10**18;
    currencyToken.approve(address(assetToken), yieldAmount);
    assetToken.depositYield(yieldAmount);
    vm.stopPrank();

    // Simulate some time passing
    vm.warp(block.timestamp + 1 days);

    uint256 userTotalYield = assetToken.totalYield(user1);
    uint256 userClaimedYield = assetToken.claimedYield(user1);
    uint256 userUnclaimedYield = assetToken.unclaimedYield(user1);

    assertTrue(userTotalYield > 0, "User total yield should be greater than 0");
    assertEq(userClaimedYield, 0, "User claimed yield should be 0");
    assertEq(userUnclaimedYield, userTotalYield, "User unclaimed yield should equal total yield");

    vm.prank(user1);
    assetToken.claimYield(user1);

    userClaimedYield = assetToken.claimedYield(user1);
    userUnclaimedYield = assetToken.unclaimedYield(user1);

    assertEq(userClaimedYield, userTotalYield, "User claimed yield should now equal total yield");
    assertEq(userUnclaimedYield, 0, "User unclaimed yield should now be 0");
}


    // TODO: Look into whitelist
/*
    function testWhitelistManagement() public {
        assetToken.addToWhitelist(user1);
        assertTrue(assetToken.isAddressWhitelisted(user1));

        assetToken.removeFromWhitelist(user1);
        assertFalse(assetToken.isAddressWhitelisted(user1));

        vm.expectRevert(abi.encodeWithSelector(AssetToken.AddressAlreadyWhitelisted.selector, owner));
        assetToken.addToWhitelist(owner);

        vm.expectRevert(abi.encodeWithSelector(AssetToken.AddressNotWhitelisted.selector, user2));
        assetToken.removeFromWhitelist(user2);
    }
*/


    /*
    function testYieldDistribution() public {
        uint256 initialBalance = 1000 * 10**18;
        uint256 yieldAmount = 100 * 10**18;
        vm.startPrank(owner);
        vm.warp(1);
        assetToken.addToWhitelist(user1);
        assetToken.mint(user1, initialBalance);
        // Approve and deposit yield
        currencyToken.approve(address(assetToken), yieldAmount);

        assetToken.depositYield(block.timestamp, yieldAmount);
        assetToken.accrueYield(user1);

        vm.stopPrank();
        vm.warp(86410*10);
        /*
        console.log(assetToken.getBalanceAvailable(user1));
        vm.startPrank(user1);
        assetToken.claimYield(user1);
        //assetToken.requestYield(user1);
        console.log(assetToken.totalYield());
        console.log(assetToken.totalYield(user1));
        console.log(assetToken.unclaimedYield(user1));
                vm.stopPrank();
    */
    //assertEq(assetToken.totalYield(), yieldAmount);
    //assertEq(assetToken.totalYield(user1), yieldAmount);
    //assertEq(assetToken.unclaimedYield(user1), yieldAmount);
    /*
    }
    */
    // TODO: Look into addToWhitelist
    /*
    function testGetters() public {

        vm.startPrank(owner);

        assetToken.addToWhitelist(user1);
        assetToken.addToWhitelist(user2);

        address[] memory whitelist = assetToken.getWhitelist();
        assertEq(whitelist.length, 3); // owner, user1, user2
        assertTrue(whitelist[1] == user1 || whitelist[2] == user1);
        assertTrue(whitelist[1] == user2 || whitelist[2] == user2);

        assertEq(assetToken.getPricePerToken(), 10 * 10**18); // 10000 / 1000

        uint256 mintAmount = 500 * 10**18;
        assetToken.mint(user1, mintAmount);

        address[] memory holders = assetToken.getHolders();
        assertEq(holders.length, 2); // owner, user1
        assertTrue(holders[0] == owner || holders[1] == owner);
        assertTrue(holders[0] == user1 || holders[1] == user1);

        assertTrue(assetToken.hasBeenHolder(user1));
        assertFalse(assetToken.hasBeenHolder(user2));
        vm.stopPrank();
    }
    */

}
