# WalletFactory
[Git Source](https://github.com/https://eyqs@plumenetwork/contracts/blob/b5edc4ed671c2231a27f7b5cb5598db490d2ae10/src/WalletFactory.sol)

**Inherits:**
Ownable

**Author:**
Eugene Y. Q. Shen

Factory contract for deploying and upgrading the SmartWallet implementation.
The WalletFactory is deployed to 0x71482d5de04ea98af2df339a14e8e03be463516c.

*The WalletProxy calls the WalletFactory to get the address of the SmartWallet.
The WalletFactory address must be fixed to make WalletProxy bytecode immutable.
Only the owner can upgrade the SmartWallet by updating the implementation address.*


## State Variables
### smartWallet
Address of the current SmartWallet implementation


```solidity
ISmartWallet public smartWallet;
```


## Functions
### constructor

Construct the WalletFactory

*The owner of the WalletFactory should be set to Plume Governance once ready*


```solidity
constructor(address owner_, ISmartWallet smartWallet_) Ownable(owner_);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`owner_`|`address`|Address of the owner of the WalletFactory|
|`smartWallet_`|`ISmartWallet`|Initial SmartWallet implementation|


### upgrade

Upgrade the SmartWallet implementation

*Only the WalletFactory owner can upgrade the SmartWallet implementation*


```solidity
function upgrade(ISmartWallet smartWallet_) public onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`smartWallet_`|`ISmartWallet`|New SmartWallet implementation|


