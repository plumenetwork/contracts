# IAggregateToken
[Git Source](https://github.com/https://eyqs@plumenetwork/contracts/blob/1eea2560282d3318cd062ba5ad80f7080ddff6b4/src/interfaces/IAggregateToken.sol)

**Inherits:**
[IComponentToken](/src/interfaces/IComponentToken.sol/interface.IComponentToken.md)


## Functions
### buyComponentToken


```solidity
function buyComponentToken(IComponentToken componentToken, uint256 currencyTokenAmount) external;
```

### sellComponentToken


```solidity
function sellComponentToken(IComponentToken componentToken, uint256 currencyTokenAmount) external;
```

### getAskPrice


```solidity
function getAskPrice() external view returns (uint256);
```

### getBidPrice


```solidity
function getBidPrice() external view returns (uint256);
```

### getTokenURI


```solidity
function getTokenURI() external view returns (string memory);
```

### getComponentTokenList


```solidity
function getComponentTokenList() external view returns (IComponentToken[] memory);
```

