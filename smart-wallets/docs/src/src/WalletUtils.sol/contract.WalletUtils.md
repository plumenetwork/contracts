# WalletUtils
[Git Source](https://github.com/https://eyqs@plumenetwork/contracts/blob/b5edc4ed671c2231a27f7b5cb5598db490d2ae10/src/WalletUtils.sol)

**Author:**
Eugene Y. Q. Shen

Common utilities for smart wallets on Plume


## Functions
### onlyWallet

Only the user wallet can call this function


```solidity
modifier onlyWallet();
```

### isContract

Checks if an address is a contract or smart wallet.

*This function uses the `extcodesize` opcode to check if the target address contains contract code.
It returns true for contracts and smart wallets, and false for EOAs that do not have smart wallets.*


```solidity
function isContract(address addr) internal view returns (bool hasCode);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`addr`|`address`|Address to check|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`hasCode`|`bool`|True if the address is a contract or smart wallet, and false if it is not|


## Errors
### UnauthorizedCall
Indicates a failure because the caller is not the user wallet


```solidity
error UnauthorizedCall(address invalidUser);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`invalidUser`|`address`|Address of the caller who tried to call a wallet-only function|

