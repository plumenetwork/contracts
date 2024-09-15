# NestStaking
[Git Source](https://github.com/https://eyqs@plumenetwork/contracts/blob/1eea2560282d3318cd062ba5ad80f7080ddff6b4/src/NestStaking.sol)

**Inherits:**
Initializable, AccessControlUpgradeable, UUPSUpgradeable

**Author:**
Eugene Y. Q. Shen

Contract for creating AggregateTokens


## State Variables
### UPGRADER_ROLE
Role for the upgrader of the AggregateToken


```solidity
bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADE_ROLE");
```


## Functions
### initialize

Initialize the AggregateToken


```solidity
function initialize(address owner) public initializer;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`owner`|`address`|Address of the owner of the AggregateToken|


### _authorizeUpgrade

Revert when `msg.sender` is not authorized to upgrade the contract


```solidity
function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newImplementation`|`address`|Address of the new implementation|


### createAggregateToken

Create a new AggregateToken


```solidity
function createAggregateToken(
    address owner,
    string memory name,
    string memory symbol,
    address currencyAddress,
    uint8 decimals_,
    uint256 askPrice,
    uint256 bidPrice,
    string memory tokenURI
) public;
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


## Events
### TokenCreated
Emitted when a new AggregateToken is created


```solidity
event TokenCreated(address indexed owner, AggregateTokenProxy indexed aggregateTokenProxy);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`owner`|`address`|Address of the owner of the AggregateToken|
|`aggregateTokenProxy`|`AggregateTokenProxy`|Address of the proxy of the new AggregateToken|

