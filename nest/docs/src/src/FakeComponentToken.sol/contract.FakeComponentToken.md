# FakeComponentToken
[Git Source](https://github.com/https://eyqs@plumenetwork/contracts/blob/1eea2560282d3318cd062ba5ad80f7080ddff6b4/src/FakeComponentToken.sol)

**Inherits:**
Initializable, AccessControlUpgradeable, UUPSUpgradeable, ERC20Upgradeable, [IComponentToken](/src/interfaces/IComponentToken.sol/interface.IComponentToken.md)

**Author:**
Eugene Y. Q. Shen

Fake example of a ComponentToken that could be used in an AggregateToken when testing.
Users can buy and sell one FakeComponentToken by exchanging it with one CurrencyToken at any time.


## State Variables
### FAKE_COMPONENT_TOKEN_STORAGE_LOCATION

```solidity
bytes32 private constant FAKE_COMPONENT_TOKEN_STORAGE_LOCATION =
    0x2c4e9dd7fc35b7006b8a84e1ac11ecc9e53a0dd5c8824b364abab355c5037600;
```


### UPGRADER_ROLE
Role for the upgrader of the FakeComponentToken


```solidity
bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADE_ROLE");
```


## Functions
### _getFakeComponentTokenStorage


```solidity
function _getFakeComponentTokenStorage() private pure returns (FakeComponentTokenStorage storage $);
```

### initialize

Initialize the FakeComponentToken


```solidity
function initialize(
    address owner,
    string memory name,
    string memory symbol,
    IERC20 currencyToken,
    uint8 decimals_
) public initializer;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`owner`|`address`|Address of the owner of the FakeComponentToken|
|`name`|`string`|Name of the FakeComponentToken|
|`symbol`|`string`|Symbol of the FakeComponentToken|
|`currencyToken`|`IERC20`|CurrencyToken used to mint and burn the FakeComponentToken|
|`decimals_`|`uint8`|Number of decimals of the FakeComponentToken|


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

Number of decimals of the FakeComponentToken


```solidity
function decimals() public view override returns (uint8);
```

### buy

Buy FakeComponentToken using CurrencyToken

*The user must approve the contract to spend the CurrencyToken*


```solidity
function buy(IERC20 currencyToken_, uint256 amount) public returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`currencyToken_`|`IERC20`|CurrencyToken used to buy the FakeComponentToken|
|`amount`|`uint256`|Amount of CurrencyToken to pay to receive the same amount of FakeComponentToken|


### sell

Sell FakeComponentToken to receive CurrencyToken


```solidity
function sell(IERC20 currencyToken_, uint256 amount) public returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`currencyToken_`|`IERC20`|CurrencyToken received in exchange for the FakeComponentToken|
|`amount`|`uint256`|Amount of CurrencyToken to receive in exchange for the FakeComponentToken|


### setCurrencyToken

Set the CurrencyToken used to mint and burn the FakeComponentToken


```solidity
function setCurrencyToken(IERC20 currencyToken) public onlyRole(DEFAULT_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`currencyToken`|`IERC20`|New CurrencyToken|


### getCurrencyToken

CurrencyToken used to mint and burn the FakeComponentToken


```solidity
function getCurrencyToken() public view returns (IERC20);
```

## Events
### ComponentTokenBought
Emitted when a user buys FakeComponentToken using CurrencyToken


```solidity
event ComponentTokenBought(
    address indexed user, IERC20 indexed currencyToken, uint256 currencyTokenAmount, uint256 componentTokenAmount
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|Address of the user who bought the FakeComponentToken|
|`currencyToken`|`IERC20`|CurrencyToken used to buy the FakeComponentToken|
|`currencyTokenAmount`|`uint256`|Amount of CurrencyToken paid|
|`componentTokenAmount`|`uint256`|Amount of FakeComponentToken received|

### ComponentTokenSold
Emitted when a user sells FakeComponentToken to receive CurrencyToken


```solidity
event ComponentTokenSold(
    address indexed user, IERC20 indexed currencyToken, uint256 currencyTokenAmount, uint256 componentTokenAmount
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|Address of the user who sold the FakeComponentToken|
|`currencyToken`|`IERC20`|CurrencyToken received in exchange for the FakeComponentToken|
|`currencyTokenAmount`|`uint256`|Amount of CurrencyToken received|
|`componentTokenAmount`|`uint256`|Amount of FakeComponentToken sold|

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
|`currencyToken`|`IERC20`|Actual CurrencyToken used to mint and burn the FakeComponentToken|

### CurrencyTokenInsufficientBalance
Indicates a failure because the FakeComponentToken does not have enough CurrencyToken


```solidity
error CurrencyTokenInsufficientBalance(IERC20 currencyToken, uint256 amount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`currencyToken`|`IERC20`|CurrencyToken used to mint and burn the FakeComponentToken|
|`amount`|`uint256`|Amount of CurrencyToken required in the failed transfer|

### UserCurrencyTokenInsufficientBalance
Indicates a failure because the user does not have enough CurrencyToken


```solidity
error UserCurrencyTokenInsufficientBalance(IERC20 currencyToken, address user, uint256 amount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`currencyToken`|`IERC20`|CurrencyToken used to mint and burn the FakeComponentToken|
|`user`|`address`|Address of the user who is selling the CurrencyToken|
|`amount`|`uint256`|Amount of CurrencyToken required in the failed transfer|

## Structs
### FakeComponentTokenStorage

```solidity
struct FakeComponentTokenStorage {
    IERC20 currencyToken;
    uint8 decimals;
}
```

