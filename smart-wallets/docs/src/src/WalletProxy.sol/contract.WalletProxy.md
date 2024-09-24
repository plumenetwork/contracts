# WalletProxy
[Git Source](https://github.com/https://eyqs@plumenetwork/contracts/blob/b5edc4ed671c2231a27f7b5cb5598db490d2ae10/src/WalletProxy.sol)

**Inherits:**
Proxy

**Author:**
Eugene Y. Q. Shen

Double proxy contract that is loaded into every smart wallet call.
The WalletProxy is deployed to 0x38F983FcC64217715e00BeA511ddf2525b8DC692.

*The bytecode of this contract is loaded whenever anyone uses `Call`
or `StaticCall` on an EOA (see `plumenetwork/go-ethereum` for details).
The bytecode must be static to minimize changes to geth, so everything
in this contract is immutable. The WalletProxy delegates all calls to
the SmartWallet implementation through the WalletFactory, which then
delegates calls to the user's wallet extensions, hence the double proxy.*


## State Variables
### walletFactory
Address of the WalletFactory that the WalletProxy delegates to


```solidity
WalletFactory public immutable walletFactory;
```


## Functions
### constructor

Construct the WalletProxy

*The WalletFactory is immutable and set at deployment*


```solidity
constructor(WalletFactory walletFactory_);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`walletFactory_`|`WalletFactory`|WalletFactory implementation|


### _implementation

Fallback function for the proxy implementation, which
delegates calls to the SmartWallet through the WalletFactory


```solidity
function _implementation() internal view virtual override returns (address impl);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`impl`|`address`|Address of the SmartWallet implementation|


### receive

Fallback function to receive ether


```solidity
receive() external payable;
```

