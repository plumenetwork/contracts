# ISignedOperations
[Git Source](https://github.com/https://eyqs@plumenetwork/contracts/blob/b5edc4ed671c2231a27f7b5cb5598db490d2ae10/src/interfaces/ISignedOperations.sol)


## Functions
### isNonceUsed


```solidity
function isNonceUsed(bytes32 nonce) external view returns (bool used);
```

### cancelSignedOperations


```solidity
function cancelSignedOperations(bytes32 nonce) external;
```

### executeSignedOperations


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

