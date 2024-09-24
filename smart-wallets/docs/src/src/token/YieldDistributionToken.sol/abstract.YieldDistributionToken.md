# YieldDistributionToken
[Git Source](https://github.com/https://eyqs@plumenetwork/contracts/blob/b5edc4ed671c2231a27f7b5cb5598db490d2ae10/src/token/YieldDistributionToken.sol)

**Inherits:**
ERC20, Ownable, [IYieldDistributionToken](/src/interfaces/IYieldDistributionToken.sol/interface.IYieldDistributionToken.md)

**Author:**
Eugene Y. Q. Shen

ERC20 token that receives yield deposits and distributes yield
to token holders proportionally based on how long they have held the token


## State Variables
### YIELD_DISTRIBUTION_TOKEN_STORAGE_LOCATION

```solidity
bytes32 private constant YIELD_DISTRIBUTION_TOKEN_STORAGE_LOCATION =
    0x3d2d7d9da47f1055055838ecd982d8a93d7044b5f93759fc6e1ef3269bbc7000;
```


### _BASE

```solidity
uint256 private constant _BASE = 1e18;
```


## Functions
### _getYieldDistributionTokenStorage


```solidity
function _getYieldDistributionTokenStorage() internal pure returns (YieldDistributionTokenStorage storage $);
```

### constructor

Construct the YieldDistributionToken


```solidity
constructor(
    address owner,
    string memory name,
    string memory symbol,
    IERC20 currencyToken,
    uint8 decimals_,
    string memory tokenURI
) ERC20(name, symbol) Ownable(owner);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`owner`|`address`|Address of the owner of the YieldDistributionToken|
|`name`|`string`|Name of the YieldDistributionToken|
|`symbol`|`string`|Symbol of the YieldDistributionToken|
|`currencyToken`|`IERC20`|Token in which the yield is deposited and denominated|
|`decimals_`|`uint8`|Number of decimals of the YieldDistributionToken|
|`tokenURI`|`string`|URI of the YieldDistributionToken metadata|


### requestYield

Request to receive yield from the given SmartWallet


```solidity
function requestYield(address from) external virtual override(IYieldDistributionToken);
```

### decimals

Number of decimals of the YieldDistributionToken


```solidity
function decimals() public view override returns (uint8);
```

### _update

Update the balance of `from` and `to` after token transfer and accrue yield

*Invariant: the user has at most one balance at each timestamp*


```solidity
function _update(address from, address to, uint256 value) internal virtual override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`from`|`address`|Address to transfer tokens from|
|`to`|`address`|Address to transfer tokens to|
|`value`|`uint256`|Amount of tokens to transfer|


### setTokenURI

Set the URI for the YieldDistributionToken metadata

*Only the owner can call this setter*


```solidity
function setTokenURI(string memory tokenURI) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenURI`|`string`|New token URI|


### getCurrencyToken

CurrencyToken in which the yield is deposited and denominated


```solidity
function getCurrencyToken() external view returns (IERC20);
```

### getTokenURI

URI for the YieldDistributionToken metadata


```solidity
function getTokenURI() external view returns (string memory);
```

### _depositYield

Deposit yield into the YieldDistributionToken

*The sender must have approved the CurrencyToken to spend the given amount*


```solidity
function _depositYield(uint256 timestamp, uint256 currencyTokenAmount) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`timestamp`|`uint256`|Timestamp of the deposit, must not be less than the previous deposit timestamp|
|`currencyTokenAmount`|`uint256`|Amount of CurrencyToken to deposit as yield|


### claimYield

Claim all the remaining yield that has been accrued to a user

*Anyone can call this function to claim yield for any user*


```solidity
function claimYield(address user) public returns (IERC20 currencyToken, uint256 currencyTokenAmount);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|Address of the user to claim yield for|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`currencyToken`|`IERC20`|CurrencyToken in which the yield is deposited and denominated|
|`currencyTokenAmount`|`uint256`|Amount of CurrencyToken claimed as yield|


### accrueYield

Accrue yield to a user, which can later be claimed

*Anyone can call this function to accrue yield to any user.
The function does not do anything if it is called in the same block that a deposit is made.
This function accrues all the yield up until the most recent deposit and creates
a new balance at that deposit timestamp. All balances before that are then deleted.*


```solidity
function accrueYield(address user) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|Address of the user to accrue yield to|


## Events
### Deposited
Emitted when yield is deposited into the YieldDistributionToken


```solidity
event Deposited(address indexed user, uint256 timestamp, uint256 currencyTokenAmount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|Address of the user who deposited the yield|
|`timestamp`|`uint256`|Timestamp of the deposit|
|`currencyTokenAmount`|`uint256`|Amount of CurrencyToken deposited as yield|

### YieldClaimed
Emitted when yield is claimed by a user


```solidity
event YieldClaimed(address indexed user, uint256 currencyTokenAmount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|Address of the user who claimed the yield|
|`currencyTokenAmount`|`uint256`|Amount of CurrencyToken claimed as yield|

### YieldAccrued
Emitted when yield is accrued to a user


```solidity
event YieldAccrued(address indexed user, uint256 currencyTokenAmount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|Address of the user who accrued the yield|
|`currencyTokenAmount`|`uint256`|Amount of CurrencyToken accrued as yield|

## Errors
### InvalidTimestamp
Indicates a failure because the given timestamp is in the future


```solidity
error InvalidTimestamp(uint256 timestamp, uint256 currentTimestamp);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`timestamp`|`uint256`|Timestamp that was in the future|
|`currentTimestamp`|`uint256`|Current block.timestamp|

### ZeroAmount
Indicates a failure because the given amount is 0


```solidity
error ZeroAmount();
```

### InvalidDepositTimestamp
Indicates a failure because the given deposit timestamp is less than the last one


```solidity
error InvalidDepositTimestamp(uint256 timestamp, uint256 lastTimestamp);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`timestamp`|`uint256`|Deposit timestamp that was too old|
|`lastTimestamp`|`uint256`|Last deposit timestamp|

### TransferFailed
Indicates a failure because the transfer of CurrencyToken failed


```solidity
error TransferFailed(address user, uint256 currencyTokenAmount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|Address of the user who tried to transfer CurrencyToken|
|`currencyTokenAmount`|`uint256`|Amount of CurrencyToken that failed to transfer|

## Structs
### Balance
Balance of one user at one point in time


```solidity
struct Balance {
    uint256 amount;
    uint256 previousTimestamp;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`|Amount of YieldDistributionTokens held by the user at that time|
|`previousTimestamp`|`uint256`|Timestamp of the previous balance for that user|

### BalanceHistory
Linked list of balances for one user

*Invariant: the user has at most one balance at each timestamp,
i.e. balanceHistory[timestamp].previousTimestamp < timestamp.
Invariant: there is at most one balance whose timestamp is older or equal
to than the most recent deposit whose yield was accrued to each user.*


```solidity
struct BalanceHistory {
    uint256 lastTimestamp;
    mapping(uint256 timestamp => Balance balance) balances;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`lastTimestamp`|`uint256`|Timestamp of the last balance for that user|
|`balances`|`mapping(uint256 timestamp => Balance balance)`|Mapping of timestamps to balances|

### Deposit
Amount of yield deposited into the YieldDistributionToken at one point in time


```solidity
struct Deposit {
    uint256 currencyTokenAmount;
    uint256 totalSupply;
    uint256 previousTimestamp;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`currencyTokenAmount`|`uint256`|Amount of CurrencyToken deposited as yield|
|`totalSupply`|`uint256`|Total supply of the YieldDistributionToken at that time|
|`previousTimestamp`|`uint256`|Timestamp of the previous deposit|

### DepositHistory
Linked list of deposits into the YieldDistributionToken

*Invariant: the YieldDistributionToken has at most one deposit at each timestamp
i.e. depositHistory[timestamp].previousTimestamp < timestamp*


```solidity
struct DepositHistory {
    uint256 lastTimestamp;
    mapping(uint256 timestamp => Deposit deposit) deposits;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`lastTimestamp`|`uint256`|Timestamp of the last deposit|
|`deposits`|`mapping(uint256 timestamp => Deposit deposit)`|Mapping of timestamps to deposits|

### YieldDistributionTokenStorage

```solidity
struct YieldDistributionTokenStorage {
    IERC20 currencyToken;
    uint8 decimals;
    string tokenURI;
    DepositHistory depositHistory;
    mapping(address user => BalanceHistory balanceHistory) balanceHistory;
    mapping(address user => uint256 currencyTokenAmount) yieldAccrued;
    mapping(address user => uint256 currencyTokenAmount) yieldWithdrawn;
}
```

