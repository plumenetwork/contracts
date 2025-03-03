# Arc Token System

A comprehensive token system for representing company shares with built-in yield distribution, whitelisting, and sales functionality.

## Source Files
- [`ArcToken.sol`](src/token/ArcToken.sol) - Core token implementation with yield distribution
- [`ArcTokenFactory.sol`](src/token/ArcTokenFactory.sol) - Factory for deploying new token instances
- [`ArcTokenPurchase.sol`](src/token/ArcTokenPurchase.sol) - Token sale and storefront management

## Table of Contents
1. [Overview](#overview)
2. [Contracts](#contracts)
   - [ArcToken](#arctoken)
   - [ArcTokenFactory](#arctokenfactory)
   - [ArcTokenPurchase](#arctokenpurchase)
3. [Usage Examples](#usage-examples)
   - [Deploying a New Token](#1-deploying-a-new-token)
   - [Setting Up Token Sale](#2-setting-up-token-sale)
   - [Distributing Yield](#3-distributing-yield)
4. [Example Scenario: Yield Distribution Mechanics](#example-scenario-yield-distribution-mechanics)
5. [System Architecture](#system-architecture)
6. [Token Lifecycle](#token-lifecycle)
7. [Token Creation Flow](#token-creation-flow)
8. [Purchase Flow](#purchase-flow)
9. [Error Scenarios](#comprehensive-error-scenarios)
10. [Gas Optimization Considerations](#gas-optimization-considerations)
11. [Edge Cases and Recovery](#edge-cases-and-recovery)
12. [Security Considerations](#security-considerations)
13. [Events](#events)
14. [Development](#development)

## Overview

The Arc Token System consists of three main contracts:
1. `ArcToken`: The core ERC20 token contract with yield distribution and transfer restrictions
2. `ArcTokenFactory`: Factory contract for deploying new ArcToken instances
3. `ArcTokenPurchase`: Handles token sales and storefront configuration

## Contracts

### ArcToken

An ERC20 token representing company shares with advanced features:

#### Key Features
- Whitelist-controlled transfers
- Configurable transfer restrictions
- Yield distribution to token holders
- Asset valuation tracking
- Minting/burning by issuer
- Upgradeable design using EIP-7201 namespaced storage

#### Yield Distribution
Supports two distribution methods:
1. **Direct Distribution**: Immediately transfers yield tokens to holders
2. **Claimable Distribution**: Holders must claim their yield

#### Functions

**Initialization**
```solidity
function initialize(
    string memory name_,
    string memory symbol_,
    string memory assetName_,
    uint256 assetValuation_,
    uint256 initialSupply_,
    address yieldToken_
) public initializer
```

**Whitelist Management**
```solidity
function addToWhitelist(address account) external onlyOwner
function batchAddToWhitelist(address[] calldata accounts) external onlyOwner
function removeFromWhitelist(address account) external onlyOwner
function isWhitelisted(address account) external view returns (bool)
```

**Transfer Controls**
```solidity
function setTransfersAllowed(bool allowed) external onlyOwner
function transfersAllowed() external view returns (bool)
```

**Supply Management**
```solidity
function mint(address to, uint256 amount) external onlyOwner
function burn(address from, uint256 amount) external onlyOwner
```

**Yield Distribution**
```solidity
function distributeYield(uint256 amount) external onlyOwner nonReentrant
function claimYield() external nonReentrant
function setYieldToken(address yieldTokenAddr) external onlyOwner
function setYieldDistributionMethod(bool isDirectDistribution) external onlyOwner
```

### ArcTokenFactory

Factory contract for deploying new ArcToken instances with proper initialization.

#### Key Features
- Creates upgradeable token instances using ERC1967 proxy pattern
- Implementation whitelisting for security
- Access control for administrative functions

#### Functions

**Initialization**
```solidity
function initialize(address _initialImplementation) public initializer
```

**Token Creation**
```solidity
function createToken(
    string memory name,
    string memory symbol,
    string memory assetName,
    uint256 assetValuation,
    uint256 initialSupply,
    address yieldToken
) external returns (address)
```

**Implementation Management**
```solidity
function whitelistImplementation(address newImplementation) external onlyRole(DEFAULT_ADMIN_ROLE)
function removeWhitelistedImplementation(address implementation) external onlyRole(DEFAULT_ADMIN_ROLE)
function isImplementationWhitelisted(address implementation) external view returns (bool)
```

### ArcTokenPurchase

Handles token sales and storefront configuration for ArcTokens.

#### Key Features
- Token sale management
- Storefront configuration
- Purchase token management
- Access control for administrative functions

#### Functions

**Sale Management**
```solidity
function enableToken(
    address _tokenContract,
    uint256 _numberOfTokens,
    uint256 _tokenPrice
) external onlyTokenOwner(_tokenContract)

function buy(
    address _tokenContract,
    uint256 _purchaseAmount
) external
```

**Storefront Configuration**
```solidity
function setStorefrontConfig(
    address _tokenContract,
    string memory _domain,
    string memory _title,
    string memory _description,
    string memory _ogImageUrl,
    string memory _accentColor,
    string memory _backgroundColor,
    string memory _companyLogoUrl,
    bool _showPlumeBadge
) external onlyTokenOwner(_tokenContract)
```

## Usage Examples

### 1. Deploying a New Token

```solidity
// 1. Deploy factory
ArcTokenFactory factory = new ArcTokenFactory();
factory.initialize(arcTokenImplementation);

// 2. Create new token
address tokenAddress = factory.createToken(
    "Arc Token",
    "ARC",
    "Company Shares",
    1000000e18, // valuation
    1000e18,    // initial supply
    address(usdc) // yield token
);
```

### 2. Setting Up Token Sale

```solidity
// 1. Enable token for sale
arcTokenPurchase.enableToken(
    tokenAddress,
    100e18,     // tokens for sale
    10e18       // price per token
);

// 2. Configure storefront
arcTokenPurchase.setStorefrontConfig(
    tokenAddress,
    "company.arc",
    "Company Token Sale",
    "Description",
    "image.url",
    "#FFFFFF",
    "#000000",
    "logo.url",
    true
);
```

### 3. Distributing Yield

```solidity
// 1. Set distribution method
arcToken.setYieldDistributionMethod(true); // direct distribution

// 2. Approve yield tokens
yieldToken.approve(address(arcToken), amount);

// 3. Distribute yield
arcToken.distributeYield(amount);
```

## Example Scenario: Yield Distribution Mechanics

Let's walk through a detailed example of how yield distribution and token transfers interact:

### Initial State
```
Total Supply: 1000 tokens
Alice has: 100 tokens (10%)
Bob has: 0 tokens
yieldPerToken = 0
```

### Step 1: First Yield Distribution (100 USDC)
```
Contract distributes 100 USDC yield
yieldPerToken increases by: (100 * 1e18) / 1000 = 0.1e18

Alice's entitlement: 10 USDC (10% of distribution)
Bob's entitlement: 0 USDC (no tokens held)
```

### Step 2: Alice Transfers to Bob
```
Alice transfers 50 tokens to Bob

Before transfer:
- Alice's unclaimed yield: 10 USDC
- Bob's unclaimed yield: 0 USDC

After transfer:
- Alice: 50 tokens, 10 USDC unclaimed (preserves previous yield)
- Bob: 50 tokens, 0 USDC unclaimed (starts fresh)
```

### Step 3: Second Yield Distribution (200 USDC)
```
Contract distributes 200 USDC yield
yieldPerToken increases by: (200 * 1e18) / 1000 = 0.2e18

New yield entitlements:
- Alice: 10 USDC (previous) + (50 tokens * 0.2e18) = 20 USDC
- Bob: 0 USDC (previous) + (50 tokens * 0.2e18) = 10 USDC
```

### Key Points
1. **Yield Preservation**: When tokens are transferred, the sender keeps their unclaimed yield
2. **Fresh Start**: New token recipients start accumulating yield from their acquisition point
3. **Proportional Distribution**: Yield is always distributed proportionally to token holdings
4. **Precision**: All calculations use 1e18 scaling to handle fractional amounts accurately

### Direct vs Claimable Distribution
The above example uses claimable distribution. In direct distribution mode:
- Yield tokens would be immediately transferred to holders
- No need to track unclaimed amounts
- Slightly higher gas costs for distribution but no separate claim step

## Security Considerations

1. **Access Control**
   - Token owner controls minting, burning, and whitelist
   - Factory admin controls implementation whitelisting
   - Purchase contract admin controls purchase token

2. **Transfer Restrictions**
   - Transfers can be restricted to whitelisted addresses
   - Whitelist status checked in transfer hooks

3. **Yield Distribution**
   - Reentrancy protection on yield distribution and claims
   - Accurate accounting during transfers
   - Protection against precision loss

4. **Upgradability**
   - Uses EIP-7201 namespaced storage
   - Implementation whitelisting in factory
   - Proper initialization checks

## Events

### ArcToken Events
```solidity
event WhitelistStatusChanged(address indexed account, bool isWhitelisted)
event TransfersRestrictionToggled(bool transfersAllowed)
event YieldDistributed(uint256 amount, bool directDistribution)
event YieldClaimed(address indexed account, uint256 amount)
event YieldTokenUpdated(address indexed newYieldToken)
event AssetValuationUpdated(uint256 newValuation)
event AssetNameUpdated(string newAssetName)
event YieldDistributionMethodUpdated(bool isDirectDistribution)
```

### Factory Events
```solidity
event TokenCreated(address indexed tokenAddress, address indexed owner, string name, string symbol, string assetName)
event ImplementationWhitelisted(address indexed implementation)
event ImplementationRemoved(address indexed implementation)
```

### Purchase Events
```solidity
event PurchaseMade(address indexed buyer, address indexed tokenContract, uint256 amount, uint256 pricePaid)
event TokenSaleEnabled(address indexed tokenContract, uint256 numberOfTokens, uint256 tokenPrice)
event StorefrontConfigSet(address indexed tokenContract, string domain)
event PurchaseTokenUpdated(address indexed newPurchaseToken)
```

## Development

### Prerequisites
- Solidity ^0.8.25
- OpenZeppelin Contracts
- Node.js and npm/yarn

### Testing
```bash
forge test
```

### Deployment
```bash
forge script scripts/deploy.s.sol:Deploy --rpc-url <your_rpc_url> --broadcast
```

## System Architecture

```mermaid
graph TB
    classDef core fill:#f9f,stroke:#333,stroke-width:2px
    classDef security fill:#bbf,stroke:#333,stroke-width:2px
    classDef management fill:#bfb,stroke:#333,stroke-width:2px
    classDef external fill:#fbb,stroke:#333,stroke-width:2px

    subgraph Factory["Factory (Deployment Layer)"]
        F[ArcTokenFactory]:::core
        I[Implementation Registry]:::security
        P[Proxy Management]:::security
    end

    subgraph Token["Token (Core Layer)"]
        T[ArcToken]:::core
        W[Whitelist]:::security
        Y[Yield Distribution]:::core
        V[Valuation Tracking]:::management
        H[Holder Registry]:::management
    end

    subgraph Purchase["Purchase (Interface Layer)"]
        S[Sale Management]:::management
        C[Storefront Config]:::management
        PT[Purchase Token]:::external
    end

    F -->|deploys| T
    F -->|manages| I
    F -->|creates| P
    T -->|controls| W
    T -->|manages| Y
    T -->|updates| V
    T -->|tracks| H
    S -->|configures| C
    S -->|uses| PT
    T ---|interacts| S

    style Factory fill:#f5f5f5,stroke:#333,stroke-width:2px
    style Token fill:#e8e8e8,stroke:#333,stroke-width:2px
    style Purchase fill:#f0f0f0,stroke:#333,stroke-width:2px
```

## Token Lifecycle

```mermaid
stateDiagram-v2
    [*] --> Initialized: Factory Creates Token
    Initialized --> Active: Owner Setup
    Active --> TransferRestricted: Enable Restrictions
    Active --> TransferUnrestricted: Disable Restrictions
    TransferRestricted --> TransferUnrestricted: setTransfersAllowed(true)
    TransferUnrestricted --> TransferRestricted: setTransfersAllowed(false)
    
    state Active {
        [*] --> NoYield
        NoYield --> YieldConfigured: Set Yield Token
        YieldConfigured --> DirectDistribution: Set Direct
        YieldConfigured --> ClaimableDistribution: Set Claimable
        DirectDistribution --> ClaimableDistribution: Toggle
        ClaimableDistribution --> DirectDistribution: Toggle
    }

    Active --> Paused: Owner Pause
    Paused --> Active: Owner Unpause
    Active --> [*]: Owner Shutdown
```

## Token Creation Flow

```mermaid
sequenceDiagram
    participant A as Admin
    participant F as Factory
    participant P as Proxy
    participant I as Implementation
    participant T as Token Instance

    Note over A,T: Deployment Process
    A->>F: initialize(implementation)
    activate F
    F->>I: verify implementation
    F->>F: whitelist implementation
    deactivate F

    A->>F: createToken(name, symbol, ...)
    activate F
    F->>F: verify parameters
    F->>P: deploy new proxy
    F->>T: initialize proxy
    Note over T: Setup initial state
    T->>T: whitelist owner
    T->>T: mint initial supply
    F-->>A: return token address
    deactivate F
```

## Purchase Flow

```mermaid
sequenceDiagram
    participant B as Buyer
    participant P as Purchase Contract
    participant T as Token
    participant PT as Purchase Token
    participant W as Whitelist

    Note over B,W: Purchase Process
    B->>P: buy(tokenContract, amount)
    activate P
    
    alt Not Whitelisted
        P->>W: check whitelist
        W-->>P: not whitelisted
        P-->>B: revert "Not whitelisted"
    else Insufficient Balance
        P->>PT: check balance
        PT-->>P: insufficient
        P-->>B: revert "Insufficient balance"
    else Success
        P->>PT: transferFrom(buyer, price)
        P->>T: transfer tokens
        Note over P: Emit PurchaseMade
    end
    deactivate P
```

## Comprehensive Error Scenarios

```mermaid
sequenceDiagram
    participant U as User
    participant T as Token
    participant Y as Yield Token
    participant W as Whitelist
    participant P as Purchase
    participant F as Factory

    rect rgb(255, 200, 200)
        Note over U,W: Access Control Errors
        U->>T: mint(to, amount)
        T-->>U: revert "Only owner"
        U->>W: addToWhitelist(account)
        T-->>U: revert "Only owner"
    end

    rect rgb(200, 255, 200)
        Note over U,Y: Yield Token Errors
        U->>T: distributeYield(amount)
        T->>Y: transferFrom
        Y-->>T: revert "ERC20: Insufficient allowance"
        U->>T: claimYield()
        T->>Y: transfer
        Y-->>T: revert "ERC20: Transfer failed"
    end

    rect rgb(200, 200, 255)
        Note over U,P: Purchase Errors
        U->>P: buy(token, amount)
        P->>T: checkWhitelist
        T-->>P: revert "Not whitelisted"
        U->>P: buy(token, amount)
        P->>T: checkBalance
        T-->>P: revert "Insufficient balance"
    end

    rect rgb(255, 255, 200)
        Note over U,F: Factory Errors
        U->>F: createToken(...)
        F-->>U: revert "Implementation not whitelisted"
        U->>F: createToken(...)
        F-->>U: revert "Invalid parameters"
    end
```

## Enhanced Token Lifecycle

```mermaid
stateDiagram-v2
    classDef core fill:#f9f,stroke:#333,stroke-width:2px
    classDef security fill:#bbf,stroke:#333,stroke-width:2px
    classDef management fill:#bfb,stroke:#333,stroke-width:2px
    classDef error fill:#fbb,stroke:#333,stroke-width:2px

    [*] --> Uninitialized
    Uninitialized --> Initialized: Factory Deployment

    state Initialized {
        [*] --> BasicSetup
        BasicSetup --> WhitelistConfig: Configure Whitelist
        WhitelistConfig --> YieldConfig: Setup Yield
        YieldConfig --> Ready: Complete Setup
    }

    state Ready {
        [*] --> Active
        Active --> Restricted: Enable Restrictions
        Restricted --> Active: Disable Restrictions
        
        state Active {
            [*] --> NoYield
            NoYield --> YieldConfigured: Set Yield Token
            YieldConfigured --> DirectYield: Enable Direct
            YieldConfigured --> ClaimableYield: Enable Claimable
            DirectYield --> ClaimableYield: Toggle Mode
            ClaimableYield --> DirectYield: Toggle Mode
        }

        Active --> ForSale: Enable Sales
        ForSale --> Active: Disable Sales
    }

    Ready --> Paused: Emergency Pause
    Paused --> Ready: Resume
    Ready --> Upgraded: Owner Upgrade
    Upgraded --> Ready: Complete Upgrade

    state ErrorStates {
        InvalidConfig
        UnauthorizedAccess
        FailedOperation
    }

    Ready --> InvalidConfig: Invalid Parameters
    Ready --> UnauthorizedAccess: Access Control
    Ready --> FailedOperation: Operation Error
    
    InvalidConfig --> Ready: Fix Config
    UnauthorizedAccess --> Ready: Grant Access
    FailedOperation --> Ready: Resolve Error
```

## Gas Optimization Considerations

```mermaid
graph TB
    classDef high fill:#ff9999,stroke:#333,stroke-width:2px
    classDef medium fill:#ffff99,stroke:#333,stroke-width:2px
    classDef low fill:#99ff99,stroke:#333,stroke-width:2px

    subgraph HighGas["High Gas Operations"]
        D[Direct Distribution]:::high
        M[Mass Whitelist]:::high
        U[Contract Upgrade]:::high
    end

    subgraph MediumGas["Medium Gas Operations"]
        Y[Yield Claim]:::medium
        W[Whitelist Single]:::medium
        T[Token Transfer]:::medium
    end

    subgraph LowGas["Low Gas Operations"]
        C[Check Balance]:::low
        V[View Functions]:::low
        S[Status Checks]:::low
    end

    D -->|Optimization| DO[Batch Processing]
    M -->|Optimization| MO[Merkle Tree]
    Y -->|Optimization| YO[Accumulator Pattern]
    T -->|Optimization| TO[Minimal Storage]

    style HighGas fill:#ffefef,stroke:#333,stroke-width:2px
    style MediumGas fill:#ffffef,stroke:#333,stroke-width:2px
    style LowGas fill:#efffef,stroke:#333,stroke-width:2px
```

## Edge Cases and Recovery

```mermaid
sequenceDiagram
    participant O as Owner
    participant T as Token
    participant H as Holder
    participant Y as Yield

    rect rgb(255, 220, 220)
        Note over O,Y: Edge Case: Stuck Yield
        O->>T: distributeYield
        T->>Y: transferFrom
        Y-->>T: transfer failed
        Note over O: Recovery
        O->>Y: rescue tokens
        O->>T: retry distribution
    end

    rect rgb(220, 255, 220)
        Note over H,T: Edge Case: Lost Access
        H->>T: transfer
        Note over H: Key Lost
        Note over O: Recovery
        O->>T: recover account
        T->>H: restore access
    end

    rect rgb(220, 220, 255)
        Note over T,Y: Edge Case: Decimal Mismatch
        O->>T: setYieldToken
        Note over T: Token decimals != Yield decimals
        Note over O: Recovery
        O->>T: adjust scaling
        O->>T: update configuration
    end
```
