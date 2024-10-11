pragma solidity ^0.8.25;

import "../interfaces/ISmartWallet.sol";
import "forge-std/console.sol";

// Mock SmartWallet for testing
contract MockSmartWallet is ISmartWallet {
    mapping(IAssetToken => uint256) public lockedBalances;

    // Implementing ISmartWallet functions

    function getBalanceLocked(
        IAssetToken token
    ) external view override returns (uint256) {
        return lockedBalances[token];
    }

    function claimAndRedistributeYield(IAssetToken token) external override {
        // For testing purposes, we'll simulate claiming yield
        token.claimYield(address(this));
    }

    function deployAssetVault() external override {
        // Mock implementation
    }

    function getAssetVault()
        external
        view
        override
        returns (IAssetVault assetVault)
    {
        // Mock implementation
        return IAssetVault(address(0));
    }


function transferYield(
    IAssetToken assetToken,
    address beneficiary,
    IERC20 currencyToken,
    uint256 currencyTokenAmount
) external {
    //require(msg.sender == IAssetVault(address(0)), "Only AssetVault can call transferYield");
    require(currencyToken.transfer(beneficiary, currencyTokenAmount), "Transfer failed");
    console.log("MockSmartWallet: Transferred yield to beneficiary");
    console.log("Beneficiary:", beneficiary);
    console.log("Amount:", currencyTokenAmount);
}


    function upgrade(address userWallet) external override {
        // Mock implementation
    }

    // Implementing ISignedOperations functions

    function isNonceUsed(
        bytes32 nonce
    ) external view override returns (bool used) {
        // Mock implementation
        return false;
    }

    function cancelSignedOperations(bytes32 nonce) external override {
        // Mock implementation
    }

    function executeSignedOperations(
        address[] calldata targets,
        bytes[] calldata calls,
        uint256[] calldata values,
        bytes32 nonce,
        bytes32 nonceDependency,
        uint256 expiration,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        // Mock implementation
    }

    // Implementing IYieldReceiver function

    function receiveYield(
        IAssetToken assetToken,
        IERC20 currencyToken,
        uint256 currencyTokenAmount
    ) external override {
        // Mock implementation
    }

    // Additional functions for testing

    function lockTokens(IAssetToken token, uint256 amount) public {
        lockedBalances[token] += amount;
    }

    function unlockTokens(IAssetToken token, uint256 amount) public {
        require(lockedBalances[token] >= amount, "Insufficient locked balance");
        lockedBalances[token] -= amount;
    }

    function approveToken(
        IERC20 token,
        address spender,
        uint256 amount
    ) public {
        token.approve(spender, amount);
    }
}
