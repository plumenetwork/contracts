# IAssetVault
[Git Source](https://github.com/https://eyqs@plumenetwork/contracts/blob/b5edc4ed671c2231a27f7b5cb5598db490d2ae10/src/interfaces/IAssetVault.sol)


## Functions
### updateYieldAllowance


```solidity
function updateYieldAllowance(
    IAssetToken assetToken,
    address beneficiary,
    uint256 amount,
    uint256 expiration
) external;
```

### redistributeYield


```solidity
function redistributeYield(IAssetToken assetToken, IERC20 currencyToken, uint256 currencyTokenAmount) external;
```

### wallet


```solidity
function wallet() external view returns (address wallet);
```

### getBalanceLocked


```solidity
function getBalanceLocked(IAssetToken assetToken) external view returns (uint256 balanceLocked);
```

### acceptYieldAllowance


```solidity
function acceptYieldAllowance(IAssetToken assetToken, uint256 amount, uint256 expiration) external;
```

### renounceYieldDistribution


```solidity
function renounceYieldDistribution(
    IAssetToken assetToken,
    uint256 amount,
    uint256 expiration
) external returns (uint256 amountRenounced);
```

### clearYieldDistributions


```solidity
function clearYieldDistributions(IAssetToken assetToken) external;
```

