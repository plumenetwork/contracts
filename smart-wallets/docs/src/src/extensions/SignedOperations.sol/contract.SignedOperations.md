# SignedOperations
[Git Source](https://github.com/https://eyqs@plumenetwork/contracts/blob/b5edc4ed671c2231a27f7b5cb5598db490d2ae10/src/extensions/SignedOperations.sol)

**Inherits:**
EIP712, [WalletUtils](/src/WalletUtils.sol/contract.WalletUtils.md), [ISignedOperations](/src/interfaces/ISignedOperations.sol/interface.ISignedOperations.md)

**Author:**
Eugene Y. Q. Shen

Smart wallet extension that allows users to sign multiple operations that
anyone can execute in a single transaction, enabling gasless and batched transactions.


## State Variables
### SIGNED_OPERATIONS_STORAGE_LOCATION

```solidity
bytes32 private constant SIGNED_OPERATIONS_STORAGE_LOCATION =
    0xa214e6b2b11ce39c204dc2aea686baa972436835f62e4470fcd8ece0d36fae00;
```


### SIGNED_OPERATIONS_TYPEHASH
*EIP712 typehash for the SignedOperations struct.*


```solidity
bytes32 private constant SIGNED_OPERATIONS_TYPEHASH = keccak256(
    "SignedOperations(address[] targets,bytes[] calls,uint256[] values,bytes32 nonce,bytes32 nonceDependency,uint256 expiration)"
);
```


## Functions
### _getSignedOperationsStorage


```solidity
function _getSignedOperationsStorage() private pure returns (SignedOperationsStorage storage $);
```

### constructor

Construct the SignedOperations contract

*Set the EIP721 domain separator to "Plume" and version to "1"*


```solidity
constructor() EIP712("Plume", "1");
```

### isNonceUsed

Check if a nonce has been used before


```solidity
function isNonceUsed(bytes32 nonce) public view returns (bool used);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nonce`|`bytes32`|Nonce to check|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`used`|`bool`|True if the nonce has been used before, false otherwise|


### cancelSignedOperations

Cancel pending SignedOperations that have not yet been executed

*This function can only be called by the user that signed the SignedOperations.
After this, the affected SignedOperations will revert when trying to be executed.*


```solidity
function cancelSignedOperations(bytes32 nonce) public onlyWallet;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nonce`|`bytes32`|Nonce of the SignedOperations to cancel|


### executeSignedOperations

Execute multiple SignedOperations on behalf of the user that signed them

*This function is called by anyone, but the user wallet must sign the operations.
The user wallet can sign the operations using the `signTypedData` method in Web3.
The `targets`, `calls`, and `values` arrays must all have the same length.*


```solidity
function executeSignedOperations(
    address[] calldata targets,
    bytes[] calldata calls,
    uint256[] calldata values,
    bytes32 nonce,
    bytes32 nonceDependency,
    uint256 expiration,
    uint8 v,
    bytes32 r,
    bytes32 s
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`targets`|`address[]`|Contract addresses to call|
|`calls`|`bytes[]`|Calldata to send to each contract address|
|`values`|`uint256[]`|Value to send to each contract address|
|`nonce`|`bytes32`|Arbitrary value to prevent replay attacks on SignedOperations|
|`nonceDependency`|`bytes32`|Nonce that the SignedOperations depend on, must be positive|
|`expiration`|`uint256`|Timestamp at which the SignedOperations expire|
|`v`|`uint8`|Recovery ID of the signer|
|`r`|`bytes32`|r signature of the signer|
|`s`|`bytes32`|s signature of the signer|


## Events
### SignedOperationsCanceled
Emitted when a user cancels pending SignedOperations


```solidity
event SignedOperationsCanceled(bytes32 nonce);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nonce`|`bytes32`|Nonce of the SignedOperations that were canceled|

### SignedOperationsExecuted
Emitted when someone successfully executes SignedOperations for a user


```solidity
event SignedOperationsExecuted(address indexed executor, bytes32 nonce);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`executor`|`address`|Address that executed the SignedOperations|
|`nonce`|`bytes32`|Nonce of the SignedOperations that were executed|

## Errors
### ExpiredSignature
Indicates a failure because the SignedOperations have expired


```solidity
error ExpiredSignature(bytes32 nonce, uint256 expiration);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nonce`|`bytes32`|Nonce of the expired SignedOperations|
|`expiration`|`uint256`|Timestamp at which the SignedOperations expired|

### InvalidParameters
Indicates a failure because the SignedOperations were constructed
using `targets`, `calls`, or `values` that have different lengths


```solidity
error InvalidParameters(bytes32 nonce);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nonce`|`bytes32`|Nonce of the invalid SignedOperations|

### InvalidNonce
Indicates a failure because the nonce has already been used


```solidity
error InvalidNonce(bytes32 nonce);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nonce`|`bytes32`|Nonce that was already used|

### NonceDependencyNotMet
Indicates a failure because the nonce that the SignedOperations
depend on has not yet been used


```solidity
error NonceDependencyNotMet(bytes32 nonce, bytes32 nonceDependency);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nonce`|`bytes32`|Nonce of the invalid SignedOperations|
|`nonceDependency`|`bytes32`|Nonce that the SignedOperations depends on|

### InvalidSigner
Indicates a failure because the signer of the SignedOperations does
not match the user wallet that the SignedOperations is being executed on


```solidity
error InvalidSigner(bytes32 nonce, address signer);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nonce`|`bytes32`|Nonce of the invalid SignedOperations|
|`signer`|`address`|Address of the signer|

### FailedCall
Indicates a failure because the call to the target contract failed


```solidity
error FailedCall(bytes32 nonce, address target, bytes call, uint256 value);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nonce`|`bytes32`|Nonce of the SignedOperations that failed|
|`target`|`address`|Address of the contract that was called|
|`call`|`bytes`|Calldata that was sent to the contract|
|`value`|`uint256`|Value that was sent to the contract|

## Structs
### SignedOperationsStorage

```solidity
struct SignedOperationsStorage {
    mapping(bytes32 nonce => uint256 used) nonces;
}
```

