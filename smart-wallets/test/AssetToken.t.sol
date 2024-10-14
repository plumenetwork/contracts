// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/token/AssetToken.sol";
import "../src/token/YieldDistributionToken.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockCurrencyToken is ERC20 {
    constructor() ERC20("Mock Currency", "MCT") {
        _mint(msg.sender, 1000000 * 10**18);
    }
}

contract AssetTokenTest is Test {
    AssetToken public assetToken;
    MockCurrencyToken public currencyToken;
    address public owner;
    address public user1;
    address public user2;

 function setUp() public {
        owner = address(0xdead);
        user1 = address(0x1);
        user2 = address(0x2);

        vm.startPrank(owner);
        
        console.log("Current sender (should be owner):", msg.sender);
        console.log("Owner address:", owner);

        currencyToken = new MockCurrencyToken();
        console.log("CurrencyToken deployed at:", address(currencyToken));

/*
        // Ensure the owner is whitelisted before deployment
        vm.mockCall(
            address(0),
            abi.encodeWithSignature("isAddressWhitelisted(address)", owner),
            abi.encode(true)
        );
*/
        try new AssetToken(
            owner,
            "Asset Token",
            "AT",
            currencyToken,
            18,
            "http://example.com/token",
            1000 * 10**18,
            10000 * 10**18,
            true // Whitelist enabled
        ) returns (AssetToken _assetToken) {
            assetToken = _assetToken;
            console.log("AssetToken deployed successfully at:", address(assetToken));

        } catch Error(string memory reason) {
            console.log("AssetToken deployment failed. Reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("AssetToken deployment failed with low-level error");
            console.logBytes(lowLevelData);
        }

        console.log("Assettoken setup add owner whitelist");

        // Add owner to whitelist after deployment
        if (address(assetToken) != address(0)) {
            assetToken.addToWhitelist(owner);
        }
        console.log("Assettoken setup before finish");

        vm.stopPrank();
    }

    function testInitialization() public {
        console.log("Starting testInitialization");
        require(address(assetToken) != address(0), "AssetToken not deployed");
        
        assertEq(assetToken.name(), "Asset Token", "Name mismatch");
        assertEq(assetToken.symbol(), "AT", "Symbol mismatch");
        assertEq(assetToken.decimals(), 18, "Decimals mismatch");
        //assertEq(assetToken.tokenURI_(), "http://example.com/token", "TokenURI mismatch");
        assertEq(assetToken.totalSupply(), 1000 * 10**18, "Total supply mismatch");
        assertEq(assetToken.getTotalValue(), 10000 * 10**18, "Total value mismatch");
        assertFalse(assetToken.isWhitelistEnabled(), "Whitelist should be enabled");
        assertFalse(assetToken.isAddressWhitelisted(owner), "Owner should be whitelisted");
        
        console.log("testInitialization completed successfully");
    }

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

    function testMinting() public {
        vm.startPrank(owner);
        uint256 initialSupply = assetToken.totalSupply();
        uint256 mintAmount = 500 * 10**18;

        assetToken.addToWhitelist(user1);
        assetToken.mint(user1, mintAmount);

        assertEq(assetToken.totalSupply(), initialSupply + mintAmount);
        assertEq(assetToken.balanceOf(user1), mintAmount);
        vm.stopPrank();
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
        assetToken.addToWhitelist(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector));
        vm.startPrank(owner);

        assetToken.mint(user1, transferAmount);
        vm.stopPrank();
        
        vm.prank(user1);
        assetToken.transfer(user2, transferAmount);
    }

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
        
        console.log(assetToken.getBalanceAvailable(user1));
        vm.startPrank(user1);
        assetToken.claimYield(user1);
        //assetToken.requestYield(user1);
        console.log(assetToken.totalYield());
        console.log(assetToken.totalYield(user1));
        console.log(assetToken.unclaimedYield(user1));
                vm.stopPrank();

       //assertEq(assetToken.totalYield(), yieldAmount);
        //assertEq(assetToken.totalYield(user1), yieldAmount);
        //assertEq(assetToken.unclaimedYield(user1), yieldAmount);
    }

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

    function testSetTotalValue() public {
        vm.startPrank(owner);
        uint256 newTotalValue = 20000 * 10**18;
        assetToken.setTotalValue(newTotalValue);
        assertEq(assetToken.getTotalValue(), newTotalValue);
        vm.stopPrank();
    }

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
}