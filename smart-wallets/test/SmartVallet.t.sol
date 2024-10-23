// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { SmartWallet } from "../src/SmartWallet.sol";
import { WalletUtils } from "../src/WalletUtils.sol";
import { AssetVault } from "../src/extensions/AssetVault.sol";
import { IAssetToken } from "../src/interfaces/IAssetToken.sol";
import { IAssetVault } from "../src/interfaces/IAssetVault.sol";
import { IYieldReceiver } from "../src/interfaces/IYieldReceiver.sol";

import { MockAssetToken } from "../src/mocks/MockAssetToken.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { Test } from "forge-std/Test.sol";
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
    
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
/*
// Mock contracts for testing
contract MockAssetToken is IAssetToken {

    IERC20 public currencyToken;
    mapping(address => uint256) private balances;
    mapping(address => mapping(address => uint256)) private allowances;
    uint256 private totalSupply_;

    constructor() {
        currencyToken = IERC20(address(1)); // Mock currency token address
    }

    function claimYield(address) external override returns (IERC20, uint256) {
        return (currencyToken, 100);
    }

    function accrueYield(address) external override { }

    function depositYield(uint256) external override { }

    function getBalanceAvailable(address) external view override returns (uint256) {
        return 1000;
    }

    function getCurrencyToken() external view override returns (IERC20) {
        return currencyToken;
    }

    function requestYield(address) external override { }

    function totalSupply() external view override returns (uint256) {
        return totalSupply_;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return balances[account];
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        balances[msg.sender] -= amount;
        balances[to] += amount;
        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowances[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        require(allowances[from][msg.sender] >= amount, "Insufficient allowance");
        allowances[from][msg.sender] -= amount;
        balances[from] -= amount;
        balances[to] += amount;
        return true;
    }

    // Mock functions to set balance and total supply for testing
    function setBalance(address account, uint256 amount) external {
        balances[account] = amount;
    }

    function setTotalSupply(uint256 amount) external {
        totalSupply_ = amount;
    }

}
*/
contract MockYieldReceiver is IYieldReceiver {
    function receiveYield(
        IAssetToken assetToken,
        IERC20 currencyToken,
        uint256 amount
    ) external override {
        // Implementation can be empty for testing
    }
}

contract MockUserWallet {

    function customFunction() external pure returns (bool) {
        return true;
    }

}

contract SmartWalletTest is Test {

    SmartWallet smartWallet;
    MockAssetToken mockAssetToken;
    MockYieldReceiver mockYieldReceiver;
    MockUserWallet mockUserWallet;

    // small hack to be excluded from coverage report
    function test() public { }

    function setUp() public {
        smartWallet = new SmartWallet();
        mockAssetToken = new MockAssetToken();
        mockYieldReceiver = new MockYieldReceiver();
        mockUserWallet = new MockUserWallet();
    }

    function testDeployAssetVault() public {
        smartWallet.deployAssetVault();
        assertFalse(address(smartWallet.getAssetVault()) == address(0), "AssetVault should be deployed");
    }

    function testDeployAssetVaultTwice() public {
        smartWallet.deployAssetVault();
        vm.expectRevert(
            abi.encodeWithSelector(SmartWallet.AssetVaultAlreadyExists.selector, smartWallet.getAssetVault())
        );
        smartWallet.deployAssetVault();
    }

    function testGetAssetVault() public {
        assertEq(address(smartWallet.getAssetVault()), address(0), "AssetVault should be zero address initially");
        smartWallet.deployAssetVault();
        assertFalse(
            address(smartWallet.getAssetVault()) == address(0), "AssetVault should not be zero address after deployment"
        );
    }

    function testGetBalanceLocked() public {
        smartWallet.deployAssetVault();
        uint256 balanceLocked = smartWallet.getBalanceLocked(IAssetToken(address(mockAssetToken)));
        assertEq(balanceLocked, 0, "Initial balance locked should be zero");
    }

    function testClaimAndRedistributeYield() public {
        smartWallet.claimAndRedistributeYield(IAssetToken(address(mockAssetToken)));
        // Add assertions based on the expected behavior
    }


function testTransferYield() public {
    // Deploy mocks
    MockERC20 mockCurrencyToken = new MockERC20("Mock", "MCK"); // Use a proper ERC20 mock
    MockYieldReceiver mockReceiver = new MockYieldReceiver();
    
    // Setup
    smartWallet.deployAssetVault();
    address assetVault = address(smartWallet.getAssetVault());
    
    // Mint some tokens to the smart wallet for transfer
    mockCurrencyToken.mint(address(smartWallet), 1000);
    
    // Execute transfer
    vm.prank(assetVault);
    smartWallet.transferYield(
        IAssetToken(address(mockAssetToken)),
        address(mockReceiver),
        IERC20(address(mockCurrencyToken)),
        100
    );
}

    function testTransferYieldUnauthorized() public {
        vm.expectRevert(abi.encodeWithSelector(SmartWallet.UnauthorizedAssetVault.selector, address(this)));
        smartWallet.transferYield(
            IAssetToken(address(mockAssetToken)), address(mockYieldReceiver), IERC20(address(1)), 100
        );
    }

    function testReceiveYield() public {
        // Mock the transferFrom function
        vm.mockCall(
            address(1),
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(this), address(smartWallet), 100),
            abi.encode(true)
        );

        smartWallet.receiveYield(IAssetToken(address(0)), IERC20(address(1)), 100);
        // Add assertions based on the expected behavior
    }

    function testReceiveYieldTransferFailed() public {
        // Mock the transferFrom function to return false
        vm.mockCall(
            address(1),
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(this), address(smartWallet), 100),
            abi.encode(false)
        );

        vm.expectRevert(
            abi.encodeWithSelector(SmartWallet.TransferFailed.selector, address(this), IERC20(address(1)), 100)
        );
        smartWallet.receiveYield(IAssetToken(address(0)), IERC20(address(1)), 100);
    }

    function testUpgrade() public {
        vm.prank(address(smartWallet));
        smartWallet.upgrade(address(mockUserWallet));
    }

    function testUpgradeUnauthorized() public {
        //vm.expectRevert();
        vm.startPrank(address(0xdead));
        vm.expectRevert(abi.encodeWithSelector(WalletUtils.UnauthorizedCall.selector, address(0xdead)));
        smartWallet.upgrade(address(mockUserWallet));
        vm.stopPrank();
    }

    function testFallbackToUserWallet() public {
        vm.prank(address(smartWallet));
        smartWallet.upgrade(address(mockUserWallet));

        (bool success, bytes memory data) = address(smartWallet).call(abi.encodeWithSignature("customFunction()"));
        assertTrue(success, "Call to user wallet should succeed");
        assertTrue(abi.decode(data, (bool)), "Custom function should return true");
    }

    function testReceiveEther() public {
        (bool success,) = address(smartWallet).call{ value: 1 ether }("");
        assertTrue(success, "Receiving ether should succeed");
        assertEq(address(smartWallet).balance, 1 ether, "SmartWallet balance should be 1 ether");
    }

}
