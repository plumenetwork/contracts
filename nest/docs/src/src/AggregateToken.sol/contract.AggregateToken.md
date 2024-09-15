# AggregateToken
[Git Source](https://github.com/https://eyqs@plumenetwork/contracts/blob/1eea2560282d3318cd062ba5ad80f7080ddff6b4/src/AggregateToken.sol)

**Inherits:**
Initializable, AccessControlUpgradeable, UUPSUpgradeable, ERC20Upgradeable, [IAggregateToken](/src/interfaces/IAggregateToken.sol/interface.IAggregateToken.md)

**Author:**
Eugene Y. Q. Shen

ERC20 token that represents a basket of ComponentTokens

*Invariant: the total value of all AggregateTokens minted is approximately
equal to the total value of all of its constituent ComponentTokens*


## State Variables
### AGGREGATE_TOKEN_STORAGE_LOCATION

```solidity
bytes32 private constant AGGREGATE_TOKEN_STORAGE_LOCATION =
    0xd3be8f8d43881152ac95daeff8f4c57e01616286ffd74814a5517f422a6b6200;
```


### UPGRADER_ROLE
Role for the upgrader of the AggregateToken


```solidity
bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADE_ROLE");
```


### _BASE

```solidity
uint256 private constant _BASE = 1e18;
```


## Functions
### _getAggregateTokenStorage


```solidity
function _getAggregateTokenStorage() private pure returns (AggregateTokenStorage storage $);
```

### initialize

Initialize the AggregateToken


```solidity
function initialize(
    address owner,
    string memory name,
    string memory symbol,
    address currencyAddress,
    uint8 decimals_,
    uint256 askPrice,
    uint256 bidPrice,
    string memory tokenURI
) public initializer;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`owner`|`address`|Address of the owner of the AggregateToken|
|`name`|`string`|Name of the AggregateToken|
|`symbol`|`string`|Symbol of the AggregateToken|
|`currencyAddress`|`address`|Address of the CurrencyToken used to mint and burn the AggregateToken|
|`decimals_`|`uint8`|Number of decimals of the AggregateToken|
|`askPrice`|`uint256`|Price at which users can buy the AggregateToken using CurrencyToken, times the base|
|`bidPrice`|`uint256`|Price at which users can sell the AggregateToken to receive CurrencyToken, times the base|
|`tokenURI`|`string`|URI of the AggregateToken metadata|


### _authorizeUpgrade

Revert when `msg.sender` is not authorized to upgrade the contract


```solidity
function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newImplementation`|`address`|Address of the new implementation|


### decimals

Number of decimals of the AggregateToken


```solidity
function decimals() public view override returns (uint8);
```

### buy

Buy AggregateToken using CurrencyToken

*The user must approve the contract to spend the CurrencyToken*


```solidity
function buy(IERC20 currencyToken_, uint256 currencyTokenAmount) public returns (uint256 aggregateTokenAmount);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`currencyToken_`|`IERC20`|CurrencyToken used to buy the AggregateToken|
|`currencyTokenAmount`|`uint256`|Amount of CurrencyToken to pay for the AggregateToken|


### sell

Sell AggregateToken to receive CurrencyToken


```solidity
function sell(IERC20 currencyToken_, uint256 currencyTokenAmount) public returns (uint256 aggregateTokenAmount);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`currencyToken_`|`IERC20`|CurrencyToken received in exchange for the AggregateToken|
|`currencyTokenAmount`|`uint256`|Amount of CurrencyToken to receive in exchange for the AggregateToken|


### buyComponentToken

Buy ComponentToken using CurrencyToken

*Will revert if the AggregateToken does not have enough CurrencyToken to buy the ComponentToken*


```solidity
function buyComponentToken(
    IComponentToken componentToken,
    uint256 currencyTokenAmount
) public onlyRole(DEFAULT_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`componentToken`|`IComponentToken`|ComponentToken to buy|
|`currencyTokenAmount`|`uint256`|Amount of CurrencyToken to pay to receive the ComponentToken|


### sellComponentToken

Sell ComponentToken to receive CurrencyToken

*Will revert if the ComponentToken does not have enough CurrencyToken to sell to the AggregateToken*


```solidity
function sellComponentToken(
    IComponentToken componentToken,
    uint256 currencyTokenAmount
) public onlyRole(DEFAULT_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`componentToken`|`IComponentToken`|ComponentToken to sell|
|`currencyTokenAmount`|`uint256`|Amount of CurrencyToken to receive in exchange for the ComponentToken|


### setCurrencyToken

Set the CurrencyToken used to mint and burn the AggregateToken


```solidity
function setCurrencyToken(IERC20 currencyToken) public onlyRole(DEFAULT_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`currencyToken`|`IERC20`|New CurrencyToken|


### setAskPrice

Set the price at which users can buy the AggregateToken using CurrencyToken


```solidity
function setAskPrice(uint256 askPrice) public onlyRole(DEFAULT_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`askPrice`|`uint256`|New ask price|


### setBidPrice

Set the price at which users can sell the AggregateToken to receive CurrencyToken


```solidity
function setBidPrice(uint256 bidPrice) public onlyRole(DEFAULT_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bidPrice`|`uint256`|New bid price|


### setTokenURI

Set the URI for the AggregateToken metadata


```solidity
function setTokenURI(string memory tokenURI) public onlyRole(DEFAULT_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenURI`|`string`|New token URI|


### getCurrencyToken

CurrencyToken used to mint and burn the AggregateToken


```solidity
function getCurrencyToken() public view returns (IERC20);
```

### getAskPrice

Price at which users can buy the AggregateToken using CurrencyToken, times the base


```solidity
function getAskPrice() public view returns (uint256);
```

### getBidPrice

Price at which users can sell the AggregateToken to receive CurrencyToken, times the base


```solidity
function getBidPrice() public view returns (uint256);
```

### getTokenURI

URI for the AggregateToken metadata


```solidity
function getTokenURI() public view returns (string memory);
```

### getComponentToken

Check if the given ComponentToken has ever been added to the AggregateToken


```solidity
function getComponentToken(IComponentToken componentToken) public view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`componentToken`|`IComponentToken`|ComponentToken to check|


### getComponentTokenList

Get all ComponentTokens that have ever been added to the AggregateToken


```solidity
function getComponentTokenList() public view returns (IComponentToken[] memory);
```

## Events
### AggregateTokenBought
Emitted when a user buys AggregateToken using CurrencyToken


```solidity
event AggregateTokenBought(
    address indexed user, IERC20 indexed currencyToken, uint256 currencyTokenAmount, uint256 aggregateTokenAmount
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|Address of the user who bought the AggregateToken|
|`currencyToken`|`IERC20`|CurrencyToken used to buy the AggregateToken|
|`currencyTokenAmount`|`uint256`|Amount of CurrencyToken paid|
|`aggregateTokenAmount`|`uint256`|Amount of AggregateToken received|

### AggregateTokenSold
Emitted when a user sells AggregateToken to receive CurrencyToken


```solidity
event AggregateTokenSold(
    address indexed user, IERC20 indexed currencyToken, uint256 currencyTokenAmount, uint256 aggregateTokenAmount
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|Address of the user who sold the AggregateToken|
|`currencyToken`|`IERC20`|CurrencyToken received in exchange for the AggregateToken|
|`currencyTokenAmount`|`uint256`|Amount of CurrencyToken received|
|`aggregateTokenAmount`|`uint256`|Amount of AggregateToken sold|

### ComponentTokenBought
Emitted when the admin buys ComponentToken using CurrencyToken


```solidity
event ComponentTokenBought(
    address indexed admin, IERC20 indexed currencyToken, uint256 currencyTokenAmount, uint256 componentTokenAmount
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`admin`|`address`|Address of the admin who bought the ComponentToken|
|`currencyToken`|`IERC20`|CurrencyToken used to buy the ComponentToken|
|`currencyTokenAmount`|`uint256`|Amount of CurrencyToken paid|
|`componentTokenAmount`|`uint256`|Amount of ComponentToken received|

### ComponentTokenSold
Emitted when the admin sells ComponentToken to receive CurrencyToken


```solidity
event ComponentTokenSold(
    address indexed admin, IERC20 indexed currencyToken, uint256 currencyTokenAmount, uint256 componentTokenAmount
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`admin`|`address`|Address of the admin who sold the ComponentToken|
|`currencyToken`|`IERC20`|CurrencyToken received in exchange for the ComponentToken|
|`currencyTokenAmount`|`uint256`|Amount of CurrencyToken received|
|`componentTokenAmount`|`uint256`|Amount of ComponentToken sold|

## Errors
### InvalidCurrencyToken
Indicates a failure because the given CurrencyToken does not match actual CurrencyToken


```solidity
error InvalidCurrencyToken(IERC20 invalidCurrencyToken, IERC20 currencyToken);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`invalidCurrencyToken`|`IERC20`|CurrencyToken that does not match the actual CurrencyToken|
|`currencyToken`|`IERC20`|Actual CurrencyToken used to mint and burn the AggregateToken|

### CurrencyTokenInsufficientBalance
Indicates a failure because the AggregateToken does not have enough CurrencyToken


```solidity
error CurrencyTokenInsufficientBalance(IERC20 currencyToken, uint256 amount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`currencyToken`|`IERC20`|CurrencyToken used to mint and burn the AggregateToken|
|`amount`|`uint256`|Amount of CurrencyToken required in the failed transfer|

### UserCurrencyTokenInsufficientBalance
Indicates a failure because the user does not have enough CurrencyToken


```solidity
error UserCurrencyTokenInsufficientBalance(IERC20 currencyToken, address user, uint256 amount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`currencyToken`|`IERC20`|CurrencyToken used to mint and burn the AggregateToken|
|`user`|`address`|Address of the user who is selling the CurrencyToken|
|`amount`|`uint256`|Amount of CurrencyToken required in the failed transfer|

## Structs
### AggregateTokenStorage

```solidity
struct AggregateTokenStorage {
    mapping(IComponentToken componentToken => bool exists) componentTokenMap;
    IComponentToken[] componentTokenList;
    IERC20 currencyToken;
    uint8 decimals;
    uint256 askPrice;
    uint256 bidPrice;
    string tokenURI;
}
```

