# ISmartWallet
[Git Source](https://github.com/https://eyqs@plumenetwork/contracts/blob/b5edc4ed671c2231a27f7b5cb5598db490d2ae10/src/interfaces/ISmartWallet.sol)

**Inherits:**
[ISignedOperations](/src/interfaces/ISignedOperations.sol/interface.ISignedOperations.md), [IYieldReceiver](/src/interfaces/IYieldReceiver.sol/interface.IYieldReceiver.md)


## Functions
### deployAssetVault


```solidity
function deployAssetVault() external;
```

### getAssetVault


```solidity
function getAssetVault() external view returns (IAssetVault assetVault);
```

### getBalanceLocked


```solidity
function getBalanceLocked(IAssetToken assetToken) external view returns (uint256 balanceLocked);
```

### claimAndRedistributeYield


```solidity
function claimAndRedistributeYield(IAssetToken assetToken) external;
```

### transferYield


```solidity
function transferYield(
    IAssetToken assetToken,
    address beneficiary,
    IERC20 currencyToken,
    uint256 currencyTokenAmount
) external;
```

### upgrade


```solidity
function upgrade(address userWallet) external;
```

