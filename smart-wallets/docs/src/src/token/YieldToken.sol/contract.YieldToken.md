# YieldToken
[Git Source](https://github.com/https://eyqs@plumenetwork/contracts/blob/b5edc4ed671c2231a27f7b5cb5598db490d2ae10/src/token/YieldToken.sol)

**Inherits:**
[YieldDistributionToken](/src/token/YieldDistributionToken.sol/abstract.YieldDistributionToken.md), [IYieldToken](/src/interfaces/IYieldToken.sol/interface.IYieldToken.md)

**Author:**
Eugene Y. Q. Shen

ERC20 token that receives yield redistributions from an AssetToken


## State Variables
### YIELD_TOKEN_STORAGE_LOCATION

```solidity
bytes32 private constant YIELD_TOKEN_STORAGE_LOCATION =
    0xe0df32b9dab2596a95926c5b17cc961f10a49277c3685726d2657c9ac0b50e00;
```


### _BASE

```solidity
uint256 private constant _BASE = 1e18;
```


## Functions
### _getYieldTokenStorage


```solidity
function _getYieldTokenStorage() private pure returns (YieldTokenStorage storage $);
```

### constructor

Construct the YieldToken


```solidity
constructor(
    address owner,
    string memory name,
    string memory symbol,
    IERC20 currencyToken,
    uint8 decimals_,
    string memory tokenURI_,
    IAssetToken assetToken,
    uint256 initialSupply
) YieldDistributionToken(owner, name, symbol, currencyToken, decimals_, tokenURI_);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`owner`|`address`|Address of the owner of the YieldToken|
|`name`|`string`|Name of the YieldToken|
|`symbol`|`string`|Symbol of the YieldToken|
|`currencyToken`|`IERC20`|Token in which the yield is deposited and denominated|
|`decimals_`|`uint8`|Number of decimals of the YieldToken|
|`tokenURI_`|`string`|URI of the YieldToken metadata|
|`assetToken`|`IAssetToken`|AssetToken that redistributes yield to the YieldToken|
|`initialSupply`|`uint256`|Initial supply of the YieldToken|


### mint

Mint new YieldTokens to the user

*Only the owner can call this function*


```solidity
function mint(address user, uint256 yieldTokenAmount) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|Address of the user to mint YieldTokens to|
|`yieldTokenAmount`|`uint256`|Amount of YieldTokens to mint|


### receiveYield

Receive yield into the YieldToken

*Anyone can call this function to deposit yield from their AssetToken into the YieldToken*


```solidity
function receiveYield(IAssetToken assetToken, IERC20 currencyToken, uint256 currencyTokenAmount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assetToken`|`IAssetToken`|AssetToken that redistributes yield to the YieldToken|
|`currencyToken`|`IERC20`|CurrencyToken in which the yield is received and denominated|
|`currencyTokenAmount`|`uint256`|Amount of CurrencyToken to receive as yield|


### requestYield

Make the SmartWallet redistribute yield from their AssetToken into this YieldToken


```solidity
function requestYield(address from) external override(YieldDistributionToken, IYieldDistributionToken);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`from`|`address`|Address of the SmartWallet to request the yield from|


## Errors
### InvalidCurrencyToken
Indicates a failure because the given CurrencyToken does not match the actual CurrencyToken


```solidity
error InvalidCurrencyToken(IERC20 invalidCurrencyToken, IERC20 currencyToken);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`invalidCurrencyToken`|`IERC20`|CurrencyToken that does not match the actual CurrencyToken|
|`currencyToken`|`IERC20`|Actual CurrencyToken used to mint and burn the AggregateToken|

### InvalidAssetToken
Indicates a failure because the given AssetToken does not match the actual AssetToken


```solidity
error InvalidAssetToken(IAssetToken invalidAssetToken, IAssetToken assetToken);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`invalidAssetToken`|`IAssetToken`|AssetToken that does not match the actual AssetToken|
|`assetToken`|`IAssetToken`|Actual AssetToken that redistributes yield to the YieldToken|

## Structs
### YieldTokenStorage

```solidity
struct YieldTokenStorage {
    IAssetToken assetToken;
}
```

