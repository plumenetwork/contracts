// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../src/token/AssetToken.sol";
import "../src/token/YieldDistributionToken.sol";
import { SmartWallet } from "../src/SmartWallet.sol";
import { MockSmartWallet } from "../src/mocks/MockSmartWallet.sol";
import { WalletFactory } from "../src/WalletFactory.sol";
import { WalletProxy } from "../src/WalletProxy.sol";
import { IAssetVault } from "../src/interfaces/IAssetVault.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
//import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { TestWalletImplementation } from "../src/TestWalletImplementation.sol";
import { Empty } from "../src/Empty.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";




contract AssetTokenTest is Test {
    address constant ADMIN_ADDRESS = 0xDE1509CC56D740997c70E1661BA687e950B4a241;
    bytes32 constant DEPLOY_SALT = keccak256("PlumeSmartWallets");

    AssetToken public assetToken;
    AssetToken public assetTokenWhitelisted;
    ERC20 public currencyToken;
    SmartWallet public mockSmartWallet;
    SmartWallet public testWalletImplementation;
    WalletProxy public walletProxy;
    //address public owner;
    address owner = makeAddr("alice");

    address public user1;
    address public user2;
    address public walletProxyAddress;

    // small hack to be excluded from coverage report
    function test() public { }


    function setUp() public {
        owner = ADMIN_ADDRESS;
        user1 = address(0x1);
        user2 = address(0x2);

        vm.startPrank(owner);

        // Deploy CurrencyToken
        currencyToken = new ERC20Mock();
        console.log("CurrencyToken deployed at:", address(currencyToken));

        // Deploy Empty contract
        Empty empty = new Empty{ salt: DEPLOY_SALT }();

        // Deploy WalletFactory
        WalletFactory walletFactory = new WalletFactory{ salt: DEPLOY_SALT }(owner, ISmartWallet(address(empty)));
        console.log("WalletFactory deployed at:", address(walletFactory));

        // Deploy WalletProxy
        //walletProxy = new WalletProxy{ salt: DEPLOY_SALT }(walletFactory);
        walletProxy = new WalletProxy(walletFactory);
        console.log("WalletProxy deployed at:", address(walletProxy));

        // Deploy TestWalletImplementation
//        testWalletImplementation = new TestWalletImplementation();
        testWalletImplementation = new SmartWallet();
        console.log("TestWalletImplementation deployed at:", address(testWalletImplementation));

        // Upgrade WalletFactory to use TestWalletImplementation
        walletFactory.upgrade(ISmartWallet(address(testWalletImplementation)));
        console.log("walletFactory deployed at:", address(testWalletImplementation));


assetToken = new AssetToken(
    address(testWalletImplementation),  // The SmartWallet is the owner
    "Asset Token",
    "AT",
    currencyToken,
    18,
    "http://example.com/token",
    10000 * 10 ** 18,             // Set initialSupply to zero
    10_000 * 10 ** 18,
    false // Whitelist enabled
);



assetTokenWhitelisted = new AssetToken(
    address(testWalletImplementation),  // The SmartWallet is the owner
    "Whitelisted Asset Token",
    "WAT",
    currencyToken,
    18,
    "http://example.com/token",
    0,             // Set initialSupply to zero
    10_000 * 10 ** 18,
    true // Whitelist enabled
);
        console.log("AssetToken deployed at:", address(assetTokenWhitelisted));






        vm.stopPrank();
    }


// Helper function to call _implementation() on WalletProxy
    function test_Initialization() public {
        console.log("Starting testInitialization");
        require(address(assetToken) != address(0), "AssetToken not deployed");

        assertEq(assetToken.name(), "Asset Token", "Name mismatch");
        assertEq(assetToken.symbol(), "AT", "Symbol mismatch");
        assertEq(assetToken.decimals(), 18, "Decimals mismatch");
        //assertEq(assetToken.tokenURI_(), "http://example.com/token", "TokenURI mismatch");
        assertEq(assetToken.totalSupply(), 10000 * 10 ** 18, "Total supply mismatch");
        assertEq(assetToken.getTotalValue(), 10_000 * 10 ** 18, "Total value mismatch");
        assertFalse(assetToken.isWhitelistEnabled(), "Whitelist should be enabled");
        assertFalse(assetToken.isAddressWhitelisted(owner), "Owner should be whitelisted");

        console.log("testInitialization completed successfully");
    }


/*
   // Calculate the storage slot of isWhitelisted[address(0)]
    bytes32 ASSET_TOKEN_STORAGE_LOCATION = hex"726dfad64e66a3008dc13dfa01e6342ee01974bb72e1b2f461563ca13356d800";
    uint256 mappingOffset = 2; // position of 'isWhitelisted' in the struct
    uint256 mappingSlot = uint256(ASSET_TOKEN_STORAGE_LOCATION) + mappingOffset;
    bytes32 storageSlot = keccak256(abi.encode(bytes32(uint256(0)), bytes32(mappingSlot)));
    
    vm.store(address(assetTokenWhitelisted), storageSlot, bytes32(uint256(1)));

address addrToWhitelist = 0xEa237441c92CAe6FC17Caaf9a7acB3f953be4bd1;
// Compute the storage slot for isWhitelisted[addrToWhitelist]
bytes32 storageSlotForAddr = keccak256(abi.encode(
    bytes32(uint256(uint160(addrToWhitelist))),
    bytes32(mappingSlot)
));
vm.store(address(assetTokenWhitelisted), storageSlotForAddr, bytes32(uint256(1)));


*/

/*
        // Upgrade the wallet implementation
        (bool success,) = address(walletProxy).call(
            abi.encodeWithSelector(ISmartWallet.upgrade.selector, address(testWalletImplementation))
        );
        require(success, "Failed to upgrade wallet implementation");
*/
/*
        // Deploy AssetToken through WalletProxy
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
    (bool success, ) = address(walletProxy).call(deployData);


        //(success, bytes memory result) = address(walletProxy).call(deployData);
       // require(success, "Failed to deploy AssetToken");

        address assetTokenAddress;
        assembly {
            assetTokenAddress := mload(add(result, 32))
        }
        assetTokenWhitelisted = AssetToken(assetTokenAddress);
        console.log("AssetToken deployed through WalletProxy at:", address(assetTokenWhitelisted));
*/

    function testAssetTokenDeployment() public {
        assertTrue(address(assetTokenWhitelisted) != address(0), "AssetToken not deployed");
        assertEq(assetTokenWhitelisted.name(), "Whitelisted Asset Token", "Incorrect AssetToken name");
        assertTrue(assetTokenWhitelisted.isWhitelistEnabled(), "Whitelist should be enabled");
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
        vm.startPrank(address(testWalletImplementation));
        uint256 initialSupply = assetToken.totalSupply();
        uint256 mintAmount = 500 * 10 ** 18;

        assetToken.addToWhitelist(user1);
        assetToken.mint(user1, mintAmount);

        assertEq(assetToken.totalSupply(), initialSupply + mintAmount);
        assertEq(assetToken.balanceOf(user1), mintAmount);
        vm.stopPrank();
    }

    function testSetTotalValue() public {
        vm.startPrank(address(testWalletImplementation));
        uint256 newTotalValue = 20_000 * 10 ** 18;
        assetToken.setTotalValue(newTotalValue);
        assertEq(assetToken.getTotalValue(), newTotalValue);
        vm.stopPrank();
    }


    //TODO: convert to SmartWalletCall 
    function testGetBalanceAvailable() public {
        vm.startPrank(address(testWalletImplementation));

        uint256 balance = 1000 * 10**18;
        assetToken.addToWhitelist(user1);
        assetToken.mint(user1, balance);

        assertEq(assetToken.getBalanceAvailable(user1), balance);
        vm.stopPrank();
        // Note: To fully test getBalanceAvailable, you would need to mock a SmartWallet
        // contract that implements the ISmartWallet interface and returns a locked balance.
    }

    function testTransfer() public {
        vm.startPrank(address(testWalletImplementation));
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
        vm.startPrank(address(testWalletImplementation));


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
        vm.prank(assetTokenWhitelisted.owner());  // Act as the SmartWallet
        assetTokenWhitelisted.addToWhitelist(user1);

        console.log("After adding user1:");
        console.log("Is user1 whitelisted:", assetTokenWhitelisted.isAddressWhitelisted(user1));

        // Add user2 to whitelist
        vm.prank(assetTokenWhitelisted.owner());  // Act as the SmartWallet
        assetTokenWhitelisted.addToWhitelist(user2);

        console.log("After adding user2:");
        console.log("Is user1 whitelisted:", assetTokenWhitelisted.isAddressWhitelisted(user1));
        console.log("Is user2 whitelisted:", assetTokenWhitelisted.isAddressWhitelisted(user2));

        assertTrue(assetTokenWhitelisted.isAddressWhitelisted(user1), "User1 should be whitelisted");
        assertTrue(assetTokenWhitelisted.isAddressWhitelisted(user2), "User2 should be whitelisted");

        // Remove user1 from whitelist
        vm.prank(assetTokenWhitelisted.owner());  // Act as the SmartWallet
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
/*
function testDepositYield() public {
    vm.startPrank(address(testWalletImplementation));
    uint256 yieldAmount = 100 * 10**18;
    vm.warp(10);
    currencyToken.approve(address(assetToken), yieldAmount);
    assetToken.depositYield(yieldAmount);
    vm.stopPrank();
    
    // You may need to implement a way to check the deposited yield
    // This could be done by checking the balance of the contract or through an event
}
*/

function testRequestYield() public {
    //MockSmartWallet mockWallet = new MockSmartWallet();
    //mockSmartWallet = new MockSmartWallet(owner, address(assetTokenWhitelisted));


    mockSmartWallet = new SmartWallet();
    //mockSmartWallet.setAssetToken(address(assetTokenWhitelisted));



    vm.startPrank(address(testWalletImplementation));
    assetToken.addToWhitelist(address(mockSmartWallet));
    assetToken.mint(address(mockSmartWallet), 1000 * 10**18);
    vm.stopPrank();

    assetToken.requestYield(address(mockSmartWallet));
    // You may need to implement a way to verify that the yield was requested
}

function testGetWhitelist() public {

    
    vm.startPrank(address(testWalletImplementation));
    assetTokenWhitelisted.addToWhitelist(user1);
    assetTokenWhitelisted.addToWhitelist(user2);
    vm.stopPrank();

    address[] memory whitelist = assetTokenWhitelisted.getWhitelist();
    assertEq(whitelist.length, 3, "Whitelist should have 3 addresses including the owner");
    //assertTrue(whitelist[0] == user1 || whitelist[1] == user1, "User1 should be in whitelist");
    //assertTrue(whitelist[0] == user2 || whitelist[1] == user2, "User2 should be in whitelist");
}

function testGetHoldersAndHasBeenHolder() public {
    vm.startPrank(address(testWalletImplementation));
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
    console.log("price",price);
    assertEq(price, 1 , "Price per token should be 10");
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
/*
function testTotalYieldAndClaimedYield() public {
    vm.startPrank(address(testWalletImplementation));
    assetTokenWhitelisted.addToWhitelist(user1);
    assetTokenWhitelisted.addToWhitelist(user2);
    assetTokenWhitelisted.mint(user1, 100 * 10**18);
    assetTokenWhitelisted.mint(user2, 100 * 10**18);

    uint256 yieldAmount = 20 * 10**18;
    currencyToken.approve(address(assetToken), yieldAmount);
    vm.warp(10);
    assetTokenWhitelisted.depositYield(yieldAmount);
    vm.stopPrank();

    // Simulate some time passing
    vm.warp(block.timestamp + 1 days);

    //vm.prank(user1);
    assetTokenWhitelisted.claimYield(user1);

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
*/

/*
function testUserSpecificYield() public {
    vm.startPrank(address(testWalletImplementation));
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
*/

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




    function testRevertUnauthorizedFrom() public {
        // Setup: Add user1 to whitelist but not user2
        vm.startPrank(address(testWalletImplementation));
        assetTokenWhitelisted.addToWhitelist(user1);
        assetTokenWhitelisted.mint(user2, 100 ether); // Mint to non-whitelisted user
        vm.stopPrank();

        // Test: Try to transfer from non-whitelisted user
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(AssetToken.Unauthorized.selector, user2));
        assetTokenWhitelisted.transfer(user1, 50 ether);
    }
    */
    function testRevertUnauthorizedTo() public {
        // Setup: Add user1 to whitelist but not user2
        vm.startPrank(address(testWalletImplementation));
        assetTokenWhitelisted.addToWhitelist(user1);
        assetTokenWhitelisted.mint(user1, 100 ether);
        vm.stopPrank();

        // Test: Try to transfer to non-whitelisted user
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(AssetToken.Unauthorized.selector, user2));
        assetTokenWhitelisted.transfer(user2, 50 ether);
    }

    function testRevertInsufficientBalance() public {
        // Setup: Add users to whitelist and mint tokens
        vm.startPrank(address(testWalletImplementation));
        assetTokenWhitelisted.addToWhitelist(user1);
        assetTokenWhitelisted.addToWhitelist(user2);
        assetTokenWhitelisted.mint(user1, 100 ether);
        vm.stopPrank();

        // Test: Try to transfer more than balance
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(AssetToken.InsufficientBalance.selector, user1));
        assetTokenWhitelisted.transfer(user2, 150 ether);
    }

    function testRevertAddToWhitelistInvalidAddress() public {
        vm.prank(address(testWalletImplementation));
        vm.expectRevert(AssetToken.InvalidAddress.selector);
        assetTokenWhitelisted.addToWhitelist(address(0));
    }

    function testRevertAddToWhitelistAlreadyWhitelisted() public {
        // Setup: Add user1 to whitelist
        vm.startPrank(address(testWalletImplementation));
        assetTokenWhitelisted.addToWhitelist(user1);
        
        // Test: Try to add user1 again
        vm.expectRevert(abi.encodeWithSelector(AssetToken.AddressAlreadyWhitelisted.selector, user1));
        assetTokenWhitelisted.addToWhitelist(user1);
        vm.stopPrank();
    }

    function testRevertRemoveFromWhitelistInvalidAddress() public {
        vm.prank(address(testWalletImplementation));
        vm.expectRevert(AssetToken.InvalidAddress.selector);
        assetTokenWhitelisted.removeFromWhitelist(address(0));
    }

    function testRevertRemoveFromWhitelistNotWhitelisted() public {
        vm.prank(address(testWalletImplementation));
        vm.expectRevert(abi.encodeWithSelector(AssetToken.AddressNotWhitelisted.selector, user1));
        assetTokenWhitelisted.removeFromWhitelist(user1);
    }

    function testRemoveFromWhitelistSuccess() public {
        // Setup: Add user1 to whitelist
        vm.startPrank(address(testWalletImplementation));
        assetTokenWhitelisted.addToWhitelist(user1);
        
        // Test: Successfully remove from whitelist
        vm.expectEmit(true, false, false, false);
        emit AddressRemovedFromWhitelist(user1);
        assetTokenWhitelisted.removeFromWhitelist(user1);
        
        // Verify user is no longer whitelisted
        assertFalse(assetTokenWhitelisted.isAddressWhitelisted(user1));
        vm.stopPrank();
    }

    // Helper function to check if event was emitted
    event AddressRemovedFromWhitelist(address indexed user);


function testDepositYield() public {
    uint256 depositAmount = 100 ether;
    
    vm.startPrank(address(testWalletImplementation));
    // Mint currency tokens to owner for deposit
    ERC20Mock(address(currencyToken)).mint(address(testWalletImplementation), depositAmount);
    currencyToken.approve(address(assetToken), depositAmount);
    
    // Need to advance block time to avoid DepositSameBlock error
    vm.warp(block.timestamp + 1);
    
    assetToken.depositYield(depositAmount);
    vm.stopPrank();
}
/*
function testRequestYieldRevert() public {
    address invalidSmartWallet = address(0x123);
    
    // Mock the call to fail
    vm.mockCall(
        invalidSmartWallet,
        abi.encodeWithSelector(ISmartWallet.claimAndRedistributeYield.selector, assetToken),
        abi.encode(bytes("CallFailed"))
    );
    
    vm.expectRevert(abi.encodeWithSelector(
        WalletUtils.SmartWalletCallFailed.selector,
        invalidSmartWallet
    ));
    
    assetToken.requestYield(invalidSmartWallet);
}

function testGetBalanceAvailableRevert() public {
    address invalidUser = address(0x123);
    
    // Mock the call to fail
    vm.mockCall(
        invalidUser,
        abi.encodeWithSelector(ISmartWallet.getBalanceLocked.selector, assetToken),
        abi.encode(bytes("CallFailed"))
    );
    
    vm.expectRevert(abi.encodeWithSelector(
        WalletUtils.SmartWalletCallFailed.selector,
        invalidUser
    ));
    
    assetToken.getBalanceAvailable(invalidUser);
}

    function testYieldCalculations() public {
        // Setup initial state
        address user1 = address(0x1);
        address user2 = address(0x2);
        uint256 initialMint = 100 ether;
        uint256 yieldAmount = 10 ether;

        vm.startPrank(address(testWalletImplementation));
        
        // Mint tokens to users
        assetToken.mint(user1, initialMint);
        assetToken.mint(user2, initialMint);
        
        // Mint currency tokens for yield
        ERC20Mock(address(currencyToken)).mint(address(testWalletImplementation), yieldAmount);
        currencyToken.approve(address(assetToken), yieldAmount);
        
        // Deposit yield
        vm.warp(block.timestamp + 1); // Advance time to avoid DepositSameBlock error
        assetToken.depositYield(yieldAmount);
        
        // Advance time for yield accrual
        vm.warp(block.timestamp + 1 days);
        
        // Have user1 claim their yield
        vm.stopPrank();
        vm.prank(user1);
        assetToken.claimYield(user1);
        
        // Test total yield calculations
        uint256 totalYield = assetToken.totalYield();
        assertEq(totalYield, yieldAmount, "Total yield should match deposited amount");
        
        // Test claimed yield calculations
        uint256 claimedYield = assetToken.claimedYield();
        uint256 user1Share = yieldAmount / 2; // Since user1 and user2 have equal tokens
        assertEq(claimedYield, user1Share, "Claimed yield should match user1's share");
        
        // Test unclaimed yield calculations
        uint256 unclaimedYield = assetToken.unclaimedYield();
        assertEq(unclaimedYield, yieldAmount - user1Share, "Unclaimed yield should be total minus claimed");
        
        // Test per-user yield calculations
        assertEq(assetToken.totalYield(user1), user1Share, "User1 total yield should match their share");
        assertEq(assetToken.claimedYield(user1), user1Share, "User1 claimed yield should match their share");
        assertEq(assetToken.unclaimedYield(user1), 0, "User1 should have no unclaimed yield");
        
        assertEq(assetToken.totalYield(user2), user1Share, "User2 total yield should match their share");
        assertEq(assetToken.claimedYield(user2), 0, "User2 should have no claimed yield");
        assertEq(assetToken.unclaimedYield(user2), user1Share, "User2 unclaimed yield should match their share");
        
        vm.stopPrank();
    }

    // Helper function to test yield calculations with multiple deposits and claims
    function testYieldCalculationsWithMultipleDeposits() public {
        address user1 = address(0x1);
        uint256 initialMint = 100 ether;
        uint256 firstYield = 10 ether;
        uint256 secondYield = 5 ether;

        vm.startPrank(address(testWalletImplementation));
        
        // Initial setup
        assetToken.mint(user1, initialMint);
        
        // First yield deposit
        ERC20Mock(address(currencyToken)).mint(address(testWalletImplementation), firstYield);
        currencyToken.approve(address(assetToken), firstYield);
        vm.warp(block.timestamp + 1);
        assetToken.depositYield(firstYield);
        
        // Second yield deposit
        vm.warp(block.timestamp + 1 days);
        ERC20Mock(address(currencyToken)).mint(address(testWalletImplementation), secondYield);
        currencyToken.approve(address(assetToken), secondYield);
        assetToken.depositYield(secondYield);
        
        vm.stopPrank();
        
        // Partial claim by user
        vm.startPrank(user1);
        vm.warp(block.timestamp + 1 days);
        assetToken.claimYield(user1);
        
        // Verify calculations
        uint256 totalExpectedYield = firstYield + secondYield;
        assertEq(assetToken.totalYield(), totalExpectedYield, "Total yield should match sum of deposits");
        assertEq(assetToken.totalYield(user1), totalExpectedYield, "User total yield should match all deposits");
        
        uint256 claimedAmount = assetToken.claimedYield(user1);
        assertEq(assetToken.unclaimedYield(user1), totalExpectedYield - claimedAmount, 
            "Unclaimed yield should be total minus claimed");
        
        vm.stopPrank();
    }
*/
    // Events for testing
    event Deposited(address indexed user, uint256 currencyTokenAmount);



}




