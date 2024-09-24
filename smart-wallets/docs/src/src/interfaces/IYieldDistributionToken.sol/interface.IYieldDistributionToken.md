# IYieldDistributionToken
[Git Source](https://github.com/https://eyqs@plumenetwork/contracts/blob/b5edc4ed671c2231a27f7b5cb5598db490d2ae10/src/interfaces/IYieldDistributionToken.sol)

**Inherits:**
IERC20


## Functions
### getCurrencyToken


```solidity
function getCurrencyToken() external returns (IERC20 currencyToken);
```

### claimYield


```solidity
function claimYield(address user) external returns (IERC20 currencyToken, uint256 currencyTokenAmount);
```

### accrueYield


```solidity
function accrueYield(address user) external;
```

### requestYield


```solidity
function requestYield(address from) external;
```

