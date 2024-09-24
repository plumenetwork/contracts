# SmartWallet
[Git Source](https://github.com/https://eyqs@plumenetwork/contracts/blob/b5edc4ed671c2231a27f7b5cb5598db490d2ae10/src/SmartWallet.sol)

**Inherits:**
Proxy, [WalletUtils](/src/WalletUtils.sol/contract.WalletUtils.md), [SignedOperations](/src/extensions/SignedOperations.sol/contract.SignedOperations.md), [ISmartWallet](/src/interfaces/ISmartWallet.sol/interface.ISmartWallet.md)

**Author:**
Eugene Y. Q. Shen

Base implementation of smart wallets on Plume, which can be
upgraded by changing the SmartWallet implementation in the WalletFactory
and extended for each individual user by calling `upgrade`.

*The SmartWallet has a set of core functionalities, such as the AssetVault
and SignedOperations, but any functions that are not defined in the base
implementation are delegated to the custom implementation for each user.*


## State Variables
### SMART_WALLET_STORAGE_LOCATION

```solidity
bytes32 private constant SMART_WALLET_STORAGE_LOCATION =
    0xc74f5f530706068223c06633e3be3a7b2d2fced239e7caaa9b10e1da346c1a00;
```


## Functions
### _getSmartWalletStorage


```solidity
function _getSmartWalletStorage() private pure returns (SmartWalletStorage storage $);
```

### deployAssetVault

Deploy an AssetVault for this smart wallet if it does not already exist


```solidity
function deployAssetVault() public;
```

### getAssetVault

AssetVault associated with the smart wallet


```solidity
function getAssetVault() external view returns (IAssetVault assetVault);
```

### getBalanceLocked

Get the number of AssetTokens that are currently locked in the AssetVault


```solidity
function getBalanceLocked(IAssetToken assetToken) external view returns (uint256 balanceLocked);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assetToken`|`IAssetToken`|AssetToken from which the yield is to be redistributed|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`balanceLocked`|`uint256`|Amount of the AssetToken that is currently locked|


### claimAndRedistributeYield

Claim the yield from the AssetToken, then redistribute it through the AssetVault


```solidity
function claimAndRedistributeYield(IAssetToken assetToken) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assetToken`|`IAssetToken`|AssetToken from which the yield is to be redistributed|


### transferYield

Transfer yield to the given beneficiary

*Only the AssetVault can call this function*


```solidity
function transferYield(
    IAssetToken assetToken,
    address beneficiary,
    IERC20 currencyToken,
    uint256 currencyTokenAmount
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assetToken`|`IAssetToken`|AssetToken for which the yield is to be transferred|
|`beneficiary`|`address`|Address of the beneficiary to receive the yield transfer|
|`currencyToken`|`IERC20`|CurrencyToken in which the yield is to be transferred|
|`currencyTokenAmount`|`uint256`|Amount of CurrencyToken that is to be transferred|


### receiveYield

Receive yield into the SmartWallet

*Anyone can call this function to deposit yield into any SmartWallet.
The sender must have approved the CurrencyToken to spend the given amount.*


```solidity
function receiveYield(IAssetToken, IERC20 currencyToken, uint256 currencyTokenAmount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`IAssetToken`||
|`currencyToken`|`IERC20`|CurrencyToken in which the yield is received and denominated|
|`currencyTokenAmount`|`uint256`|Amount of CurrencyToken to receive as yield|


### upgrade

Upgrade the user wallet implementation

*Only the user can upgrade the implementation for their own wallet*


```solidity
function upgrade(address userWallet) external onlyWallet;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`userWallet`|`address`|Address of the new user wallet implementation|


### _implementation

Fallback function to the user wallet implementation if
the function is not implemented in the base SmartWallet implementation


```solidity
function _implementation() internal view virtual override returns (address impl);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`impl`|`address`|Address of the user wallet implementation|


### receive

Fallback function to receive ether


```solidity
receive() external payable;
```

## Events
### UserWalletUpgraded
Emitted when a user upgrades their user wallet implementation


```solidity
event UserWalletUpgraded(address indexed userWallet);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`userWallet`|`address`|Address of the new user wallet implementation|

## Errors
### UnauthorizedAssetVault
Indicates a failure because the sender is not the AssetVault


```solidity
error UnauthorizedAssetVault(address sender);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`sender`|`address`|Address of the sender that is not the AssetVault|

### AssetVaultAlreadyExists
Indicates a failure because the AssetVault for the user already exists


```solidity
error AssetVaultAlreadyExists(IAssetVault assetVault);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assetVault`|`IAssetVault`|Existing AssetVault for the user|

### TransferFailed
Indicates a failure because the transfer of CurrencyToken failed


```solidity
error TransferFailed(address from, IERC20 currencyToken, uint256 currencyTokenAmount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`from`|`address`|Address from which the CurrencyToken failed to transfer|
|`currencyToken`|`IERC20`|CurrencyToken that failed to transfer|
|`currencyTokenAmount`|`uint256`|Amount of CurrencyToken that failed to transfer|

## Structs
### SmartWalletStorage
Storage layout for the SmartWallet

*Because the WalletProxy applies to every EOA, every user has their own
SmartWalletStorage and their own storage slot to store their custom
user wallet implementation, on which they can add any extensions.*


```solidity
struct SmartWalletStorage {
    address userWallet;
    IAssetVault assetVault;
}
```

