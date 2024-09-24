# AssetVault
[Git Source](https://github.com/https://eyqs@plumenetwork/contracts/blob/b5edc4ed671c2231a27f7b5cb5598db490d2ae10/src/extensions/AssetVault.sol)

**Inherits:**
[IAssetVault](/src/interfaces/IAssetVault.sol/interface.IAssetVault.md)

**Author:**
Eugene Y. Q. Shen

Smart wallet extension on Plume that allows users to lock yield-bearing assets
in a vault, then take the yield distributed to those locked yield-bearing assets
and manage the redistribution of that yield to multiple beneficiaries.


## State Variables
### ASSET_VAULT_STORAGE_LOCATION

```solidity
bytes32 private constant ASSET_VAULT_STORAGE_LOCATION =
    0x8705cfd43fb7e30ae97a9cbbffbf82f7d6cb80ad243d5fc52988024cb47c5700;
```


### wallet
Address of the user smart wallet that contains this AssetVault extension


```solidity
address public immutable wallet;
```


### MAX_GAS_PER_ITERATION
*Maximum amount of gas used in each iteration of the loops.
We keep iterating until we have less than this much gas left,
then we stop the loop so that we do not reach the gas limit.*


```solidity
uint256 private constant MAX_GAS_PER_ITERATION = 50_000;
```


## Functions
### _getAssetVaultStorage


```solidity
function _getAssetVaultStorage() private pure returns (AssetVaultStorage storage $);
```

### onlyWallet

Only the user wallet can call this function


```solidity
modifier onlyWallet();
```

### constructor

Construct the AssetVault extension

*The sender of the transaction creates an AssetVault for themselves,
and their address is saved as the public immutable variable `wallet`.*


```solidity
constructor();
```

### updateYieldAllowance

Update the yield allowance of the given beneficiary

*Only the user wallet can update yield allowances for tokens in their own AssetVault*


```solidity
function updateYieldAllowance(
    IAssetToken assetToken,
    address beneficiary,
    uint256 amount,
    uint256 expiration
) external onlyWallet;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assetToken`|`IAssetToken`|AssetToken from which the yield is to be redistributed|
|`beneficiary`|`address`|Address of the beneficiary of the yield allowance|
|`amount`|`uint256`|Amount of assetTokens to be locked for this yield allowance|
|`expiration`|`uint256`|Timestamp at which the yield expires|


### redistributeYield

Redistribute yield to the beneficiaries of the AssetToken, using yield distributions

*Only the user wallet can initiate the yield redistribution. The yield redistributed
to each beneficiary is rounded down, and any remaining CurrencyToken are kept in the vault.*


```solidity
function redistributeYield(
    IAssetToken assetToken,
    IERC20 currencyToken,
    uint256 currencyTokenAmount
) external onlyWallet;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assetToken`|`IAssetToken`|AssetToken from which the yield is to be redistributed|
|`currencyToken`|`IERC20`|Token in which the yield is to be redistributed|
|`currencyTokenAmount`|`uint256`|Amount of CurrencyToken to redistribute|


### getBalanceLocked

Get the number of AssetTokens that are currently locked in the AssetVault


```solidity
function getBalanceLocked(IAssetToken assetToken) external view returns (uint256 balanceLocked);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assetToken`|`IAssetToken`|AssetToken from which the yield is to be redistributed|


### acceptYieldAllowance

Accept the yield allowance and create a new yield distribution

*The beneficiary must call this function to accept the yield allowance*


```solidity
function acceptYieldAllowance(IAssetToken assetToken, uint256 amount, uint256 expiration) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assetToken`|`IAssetToken`|AssetToken from which the yield is to be redistributed|
|`amount`|`uint256`|Amount of AssetTokens included in this yield allowance|
|`expiration`|`uint256`|Timestamp at which the yield expires|


### renounceYieldDistribution

Renounce the given amount of AssetTokens from the beneficiary's yield distributions

*The beneficiary must call this function to reduce the size of their yield distributions.
If there are too many yield distributions to process, the function will stop to avoid
reaching the gas limit, and the beneficiary must call the function again to renounce more.*


```solidity
function renounceYieldDistribution(
    IAssetToken assetToken,
    uint256 amount,
    uint256 expiration
) external returns (uint256 amountRenounced);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assetToken`|`IAssetToken`|AssetToken from which the yield is to be redistributed|
|`amount`|`uint256`|Amount of AssetTokens to renounce from from the yield distribution|
|`expiration`|`uint256`|Timestamp at which the yield expires|


### clearYieldDistributions

Clear expired yield distributions from the linked list

*Anyone can call this function to free up unused storage for gas refunds.
If there are too many yield distributions to process, the function will stop to avoid
reaching the gas limit, and the caller must call the function again to clear more.*


```solidity
function clearYieldDistributions(IAssetToken assetToken) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assetToken`|`IAssetToken`|AssetToken from which the yield is to be redistributed|


## Events
### YieldAllowanceUpdated
Emitted when the user wallet updates a yield allowance


```solidity
event YieldAllowanceUpdated(
    IAssetToken indexed assetToken, address indexed beneficiary, uint256 amount, uint256 expiration
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assetToken`|`IAssetToken`|AssetToken from which the yield is to be redistributed|
|`beneficiary`|`address`|Address of the beneficiary of the yield allowance|
|`amount`|`uint256`|Amount of AssetTokens that are locked for this yield|
|`expiration`|`uint256`|Timestamp at which the yield expires|

### YieldRedistributed
Emitted when the user wallet redistributes yield to the beneficiaries


```solidity
event YieldRedistributed(
    IAssetToken indexed assetToken, address indexed beneficiary, IERC20 indexed currencyToken, uint256 yieldShare
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assetToken`|`IAssetToken`|AssetToken from which the yield was redistributed|
|`beneficiary`|`address`|Address of the beneficiary that received the yield redistribution|
|`currencyToken`|`IERC20`|Token in which the yield was redistributed|
|`yieldShare`|`uint256`|Amount of CurrencyToken that was redistributed to the beneficiary|

### YieldDistributionCreated
Emitted when a beneficiary accepts a yield allowance and creates a new yield distribution


```solidity
event YieldDistributionCreated(
    IAssetToken indexed assetToken, address indexed beneficiary, uint256 amount, uint256 expiration
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assetToken`|`IAssetToken`|AssetToken from which the yield is to be redistributed|
|`beneficiary`|`address`|Address of the beneficiary of the yield distribution|
|`amount`|`uint256`|Amount of AssetTokens that are locked for this yield|
|`expiration`|`uint256`|Timestamp at which the yield expires|

### YieldDistributionRenounced
Emitted when a beneficiary renounces their yield distributions


```solidity
event YieldDistributionRenounced(IAssetToken indexed assetToken, address indexed beneficiary, uint256 amount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assetToken`|`IAssetToken`|AssetToken from which the yield is to be redistributed|
|`beneficiary`|`address`|Address of the beneficiary of the yield distribution|
|`amount`|`uint256`|Amount of AssetTokens that are renounced from the yield distributions of the beneficiary|

### YieldDistributionsCleared
Emitted when anyone clears expired yield distributions from the linked list


```solidity
event YieldDistributionsCleared(IAssetToken indexed assetToken, uint256 amountCleared);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assetToken`|`IAssetToken`|AssetToken from which the yield is to be redistributed|
|`amountCleared`|`uint256`|Amount of AssetTokens that were cleared from the yield distributions|

## Errors
### ZeroAddress
Indicates a failure because the given address is 0x0


```solidity
error ZeroAddress();
```

### ZeroAmount
Indicates a failure because the given amount is 0


```solidity
error ZeroAmount();
```

### InvalidExpiration
Indicates a failure because the given expiration timestamp is too old


```solidity
error InvalidExpiration(uint256 expiration, uint256 currentTimestamp);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`expiration`|`uint256`|Expiration timestamp that was too old|
|`currentTimestamp`|`uint256`|Current block.timestamp|

### MismatchedExpiration
Indicates a failure because the given expiration does not match the actual one


```solidity
error MismatchedExpiration(uint256 invalidExpiration, uint256 expiration);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`invalidExpiration`|`uint256`|Expiration timestamp that does not match the actual expiration|
|`expiration`|`uint256`|Actual expiration timestamp at which the yield expires|

### InsufficientYieldAllowance
Indicates a failure because the beneficiary does not have enough yield allowances


```solidity
error InsufficientYieldAllowance(IAssetToken assetToken, address beneficiary, uint256 allowanceAmount, uint256 amount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assetToken`|`IAssetToken`|AssetToken from which the yield is to be redistributed|
|`beneficiary`|`address`|Address of the beneficiary of the yield allowance|
|`allowanceAmount`|`uint256`|Amount of assetTokens included in this yield allowance|
|`amount`|`uint256`|Amount of assetTokens that the beneficiary tried to accept the yield of|

### InsufficientBalance
Indicates a failure because the user wallet does not have enough AssetTokens


```solidity
error InsufficientBalance(IAssetToken assetToken, uint256 amount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assetToken`|`IAssetToken`|AssetToken for which a new yield distribution is to be made|
|`amount`|`uint256`|Amount of assetTokens that the user wallet tried to add to the distribution|

### InsufficientYieldDistributions
Indicates a failure because the beneficiary does not have enough yield distributions


```solidity
error InsufficientYieldDistributions(
    IAssetToken assetToken, address beneficiary, uint256 amount, uint256 amountRenounced
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assetToken`|`IAssetToken`|AssetToken from which the yield is to be redistributed|
|`beneficiary`|`address`|Address of the beneficiary of the yield distributions|
|`amount`|`uint256`|Amount of assetTokens included in all of their yield distributions|
|`amountRenounced`|`uint256`|Amount of assetTokens that the beneficiary tried to renounce the yield of|

### UnauthorizedCall
Indicates a failure because the caller is not the user wallet


```solidity
error UnauthorizedCall(address invalidUser);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`invalidUser`|`address`|Address of the caller who tried to call a wallet-only function|

## Structs
### Yield
Yield of some amount that expires at some time

*Can be used to represent both yield allowances and yield distributions*


```solidity
struct Yield {
    uint256 amount;
    uint256 expiration;
}
```

### YieldDistributionListItem
Item in a linked list of yield distributions


```solidity
struct YieldDistributionListItem {
    address beneficiary;
    Yield yield;
    YieldDistributionListItem[] next;
}
```

### AssetVaultStorage

```solidity
struct AssetVaultStorage {
    mapping(IAssetToken assetToken => mapping(address beneficiary => Yield allowance)) yieldAllowances;
    mapping(IAssetToken assetToken => YieldDistributionListItem distribution) yieldDistributions;
}
```

