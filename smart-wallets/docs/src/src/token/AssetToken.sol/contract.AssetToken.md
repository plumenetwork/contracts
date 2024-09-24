# AssetToken
[Git Source](https://github.com/https://eyqs@plumenetwork/contracts/blob/b5edc4ed671c2231a27f7b5cb5598db490d2ae10/src/token/AssetToken.sol)

**Inherits:**
[WalletUtils](/src/WalletUtils.sol/contract.WalletUtils.md), [YieldDistributionToken](/src/token/YieldDistributionToken.sol/abstract.YieldDistributionToken.md), [IAssetToken](/src/interfaces/IAssetToken.sol/interface.IAssetToken.md)

**Author:**
Eugene Y. Q. Shen

ERC20 token that represents a tokenized real world asset
and distributes yield proportionally to token holders


## State Variables
### ASSET_TOKEN_STORAGE_LOCATION

```solidity
bytes32 private constant ASSET_TOKEN_STORAGE_LOCATION =
    0x726dfad64e66a3008dc13dfa01e6342ee01974bb72e1b2f461563ca13356d800;
```


## Functions
### _getAssetTokenStorage


```solidity
function _getAssetTokenStorage() private pure returns (AssetTokenStorage storage $);
```

### constructor

Construct the AssetToken


```solidity
constructor(
    address owner,
    string memory name,
    string memory symbol,
    ERC20 currencyToken,
    uint8 decimals_,
    string memory tokenURI_,
    uint256 initialSupply,
    uint256 totalValue_
) YieldDistributionToken(owner, name, symbol, currencyToken, decimals_, tokenURI_);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`owner`|`address`|Address of the owner of the AssetToken|
|`name`|`string`|Name of the AssetToken|
|`symbol`|`string`|Symbol of the AssetToken|
|`currencyToken`|`ERC20`|Token in which the yield is deposited and denominated|
|`decimals_`|`uint8`|Number of decimals of the AssetToken|
|`tokenURI_`|`string`|URI of the AssetToken metadata|
|`initialSupply`|`uint256`|Initial supply of the AssetToken|
|`totalValue_`|`uint256`|Total value of all circulating AssetTokens|


### _update

Update the balance of `from` and `to` after token transfer and accrue yield

*Require that both parties are whitelisted and `from` has enough tokens*


```solidity
function _update(address from, address to, uint256 value) internal override(YieldDistributionToken);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`from`|`address`|Address to transfer tokens from|
|`to`|`address`|Address to transfer tokens to|
|`value`|`uint256`|Amount of tokens to transfer|


### setTotalValue

Update the total value of all circulating AssetTokens

*Only the owner can call this function*


```solidity
function setTotalValue(uint256 totalValue) external onlyOwner;
```

### enableWhitelist

Enable the whitelist

*Only the owner can call this function*


```solidity
function enableWhitelist() external onlyOwner;
```

### addToWhitelist

Add a user to the whitelist

*Only the owner can call this function*


```solidity
function addToWhitelist(address user) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|Address of the user to add to the whitelist|


### removeFromWhitelist

Remove a user from the whitelist

*Only the owner can call this function*


```solidity
function removeFromWhitelist(address user) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|Address of the user to remove from the whitelist|


### mint

Mint new AssetTokens to the user

*Only the owner can call this function*


```solidity
function mint(address user, uint256 assetTokenAmount) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|Address of the user to mint AssetTokens to|
|`assetTokenAmount`|`uint256`|Amount of AssetTokens to mint|


### depositYield

Deposit yield into the AssetToken

*Only the owner can call this function, and the owner must have
approved the CurrencyToken to spend the given amount*


```solidity
function depositYield(uint256 timestamp, uint256 currencyTokenAmount) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`timestamp`|`uint256`|Timestamp of the deposit, must not be less than the previous deposit timestamp|
|`currencyTokenAmount`|`uint256`|Amount of CurrencyToken to deposit as yield|


### requestYield

Make the SmartWallet redistribute yield from this token


```solidity
function requestYield(address from) external override(YieldDistributionToken, IYieldDistributionToken);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`from`|`address`|Address of the SmartWallet to request the yield from|


### getTotalValue

Total value of all circulating AssetTokens


```solidity
function getTotalValue() external view returns (uint256);
```

### isWhitelistEnabled

Check if the whitelist is enabled


```solidity
function isWhitelistEnabled() external view returns (bool);
```

### getWhitelist

Whitelist of users that are allowed to hold AssetTokens


```solidity
function getWhitelist() external view returns (address[] memory);
```

### isAddressWhitelisted

Check if the user is whitelisted


```solidity
function isAddressWhitelisted(address user) external view returns (bool isWhitelisted);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|Address of the user to check|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`isWhitelisted`|`bool`|Boolean indicating if the user is whitelisted|


### getHolders

List of all users that have ever held AssetTokens


```solidity
function getHolders() external view returns (address[] memory);
```

### hasBeenHolder

Check if the user has ever held AssetTokens


```solidity
function hasBeenHolder(address user) external view returns (bool held);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|Address of the user to check|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`held`|`bool`|Boolean indicating if the user has ever held AssetTokens|


### getPricePerToken

Price of an AssetToken based on its total value and total supply


```solidity
function getPricePerToken() external view returns (uint256);
```

### getBalanceAvailable

Get the available unlocked AssetToken balance of a user

*Calls `getBalanceLocked`, which reverts if the user is not a contract or a smart wallet*


```solidity
function getBalanceAvailable(address user) public view returns (uint256 balanceAvailable);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|Address of the user to get the available balance of|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`balanceAvailable`|`uint256`|Available unlocked AssetToken balance of the user|


### totalYield

Total yield distributed to all AssetTokens for all users


```solidity
function totalYield() public view returns (uint256 amount);
```

### claimedYield

Claimed yield across all AssetTokens for all users


```solidity
function claimedYield() public view returns (uint256 amount);
```

### unclaimedYield

Unclaimed yield across all AssetTokens for all users


```solidity
function unclaimedYield() external view returns (uint256 amount);
```

### totalYield

Total yield distributed to a specific user


```solidity
function totalYield(address user) external view returns (uint256 amount);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|Address of the user for which to get the total yield|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`|Total yield distributed to the user|


### claimedYield

Amount of yield that a specific user has claimed


```solidity
function claimedYield(address user) external view returns (uint256 amount);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|Address of the user for which to get the claimed yield|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`|Amount of yield that the user has claimed|


### unclaimedYield

Amount of yield that a specific user has not yet claimed


```solidity
function unclaimedYield(address user) external view returns (uint256 amount);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|Address of the user for which to get the unclaimed yield|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`|Amount of yield that the user has not yet claimed|


## Events
### AddressAddedToWhitelist
Emitted when a user is added to the whitelist


```solidity
event AddressAddedToWhitelist(address indexed user);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|Address of the user that is added to the whitelist|

### AddressRemovedFromWhitelist
Emitted when a user is removed from the whitelist


```solidity
event AddressRemovedFromWhitelist(address indexed user);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|Address of the user that is removed from the whitelist|

## Errors
### Unauthorized
Indicates a failure because the user is not whitelisted


```solidity
error Unauthorized(address user);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|Address of the user that is not whitelisted|

### InsufficientBalance
Indicates a failure because the user has insufficient balance


```solidity
error InsufficientBalance(address user);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|Address of the user that has insufficient balance|

### InvalidAddress
Indicates a failure because the given address is 0x0


```solidity
error InvalidAddress();
```

### AddressAlreadyWhitelisted
Indicates a failure because the user is already whitelisted


```solidity
error AddressAlreadyWhitelisted(address user);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|Address of the user that is already whitelisted|

### AddressNotWhitelisted
Indicates a failure because the user is not whitelisted


```solidity
error AddressNotWhitelisted(address user);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|Address of the user that is not whitelisted|

### SmartWalletCallFailed
Indicates a failure because the user's SmartWallet call failed


```solidity
error SmartWalletCallFailed(address user);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|Address of the user whose SmartWallet call failed|

## Structs
### AssetTokenStorage

```solidity
struct AssetTokenStorage {
    uint256 totalValue;
    bool isWhitelistEnabled;
    address[] whitelist;
    mapping(address user => bool whitelisted) isWhitelisted;
    address[] holders;
    mapping(address user => bool held) hasHeld;
}
```

