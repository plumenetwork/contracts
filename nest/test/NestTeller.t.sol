// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { NestTeller } from "../src/vault/NestTeller.sol";
import { NestBoringVaultModuleTest } from "./NestBoringVaultModuleTest.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MockUSDC } from "../src/mocks/MockUSDC.sol";
import { MockVault } from "../src/mocks/MockVault.sol";
import { MockAccountantWithRateProviders } from "../src/mocks/MockAccountantWithRateProviders.sol";

import { console } from "forge-std/console.sol";

contract NestTellerTest is NestBoringVaultModuleTest {

    NestTeller public teller;
    address public endpoint;
    uint256 public constant MINIMUM_MINT_PERCENTAGE = 9900; // 99%

   function setUp() public override {
    super.setUp();
    endpoint = makeAddr("endpoint");

    // Debug logs
    console.log("Asset decimals:", asset.decimals());
    console.log("Vault decimals:", vault.decimals());
    console.log("Asset address:", address(asset));
    console.log("Vault address:", address(vault));
    console.log("Accountant address:", address(accountant));
    
    // Add validation checks before deployment
    require(address(vault) != address(0), "Vault address is zero");
    require(address(accountant) != address(0), "Accountant address is zero");
    require(address(asset) != address(0), "Asset address is zero");
    require(endpoint != address(0), "Endpoint address is zero");
    
    // Add more detailed logging

    
    console.log("Debug: About to deploy NestTeller");
    console.log("Debug: Owner:", owner);
    console.log("Debug: Vault:", address(vault));
    console.log("Debug: Accountant:", address(accountant));
    console.log("Debug: Endpoint:", endpoint);
    console.log("Debug: Asset:", address(asset));
    console.log("Debug: MinimumMintPercentage:", MINIMUM_MINT_PERCENTAGE);


    // Try to deploy teller with try-catch and more detailed error handling
    try new NestTeller(
        owner,
        address(vault),
        address(accountant),
        endpoint,
        address(asset),
        MINIMUM_MINT_PERCENTAGE
    ) returns (NestTeller _teller) {
        teller = _teller;
        console.log("Teller deployed successfully at:", address(teller));
        
        // Verify initialization
        require(teller.owner() == owner, "Owner not set correctly");
        require(address(teller.vaultContract()) == address(vault), "Vault not set correctly");
        require(address(teller.accountantContract()) == address(accountant), "Accountant not set correctly");
        require(teller.asset() == address(asset), "Asset not set correctly");
        
    } catch Error(string memory reason) {
        console.log("Deployment failed with reason:", reason);
        revert(reason);
    } catch Panic(uint errorCode) {
        string memory panicReason = getPanicReason(errorCode);
        console.log("Deployment failed with panic:", panicReason);
        revert(string(abi.encodePacked("Panic: ", panicReason)));
    } catch (bytes memory returnData) {
        console.log("Deployment failed with raw data:");
        console.logBytes(returnData);
        
        // Try to decode the revert reason if possible
        if (returnData.length > 4) {
            bytes4 selector = bytes4(returnData);
            console.log("Selector:", bytes4ToString(selector));
        }
        
        revert("Unknown error");
    }

    // Approve teller to spend vault's tokens
    vm.prank(address(vault));
    IERC20(address(asset)).approve(address(teller), type(uint256).max);
}

// Helper function to get panic reason
function getPanicReason(uint errorCode) internal pure returns (string memory) {
    if (errorCode == 0x01) return "Assertion failed";
    if (errorCode == 0x11) return "Arithmetic overflow/underflow";
    if (errorCode == 0x12) return "Division by zero";
    if (errorCode == 0x21) return "Invalid enum value";
    if (errorCode == 0x22) return "Storage write to inaccessible slot";
    if (errorCode == 0x31) return "Pop from empty array";
    if (errorCode == 0x32) return "Array access out of bounds";
    if (errorCode == 0x41) return "Zero initialization of uninitialized variable";
    if (errorCode == 0x51) return "Invalid memory access";
    return string(abi.encodePacked("Unknown panic code: ", uint2str(errorCode)));
}

// Helper function to convert uint to string
function uint2str(uint _i) internal pure returns (string memory) {
    if (_i == 0) return "0";
    uint j = _i;
    uint len;
    while (j != 0) {
        len++;
        j /= 10;
    }
    bytes memory bstr = new bytes(len);
    uint k = len;
    while (_i != 0) {
        k = k-1;
        uint8 temp = (48 + uint8(_i - _i / 10 * 10));
        bytes1 b1 = bytes1(temp);
        bstr[k] = b1;
        _i /= 10;
    }
    return string(bstr);
}

// Helper function to convert bytes4 to string
function bytes4ToString(bytes4 _bytes) internal pure returns (string memory) {
    bytes memory bytesArray = new bytes(8);
    uint256 value = uint256(uint32(_bytes));
    for (uint256 i; i < 4; i++) {
        uint8 temp = uint8(value / (2**(8*(3-i))));
        bytesArray[i*2] = bytes1(uint8((temp / 16) + (temp / 16 < 10 ? 48 : 87)));
        bytesArray[i*2+1] = bytes1(uint8((temp % 16) + (temp % 16 < 10 ? 48 : 87)));
    }
    return string(bytesArray);
}

    function testInitialization() public override {
        assertEq(teller.owner(), owner);
        assertEq(address(teller.vaultContract()), address(vault));
        assertEq(address(teller.accountantContract()), address(accountant));
        assertEq(teller.asset(), address(asset));
        assertEq(teller.minimumMintPercentage(), MINIMUM_MINT_PERCENTAGE);
    }

    function testDeposit(
        uint256 amount
    ) public {
        // Bound the amount to reasonable values
        amount = bound(amount, 1e6, 1_000_000e6);

        // Give user some tokens
        deal(address(asset), user, amount);

        // Approve teller
        vm.startPrank(user);
        IERC20(address(asset)).approve(address(teller), amount);

        // Deposit
        uint256 shares = teller.deposit(amount, user, user);

        // Verify
        assertGt(shares, 0, "Should have received shares");
        assertEq(IERC20(address(asset)).balanceOf(address(vault)), amount, "Vault should have received tokens");
        vm.stopPrank();
    }

}
