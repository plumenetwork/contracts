## Staking Smart Contracts

These are the smart contracts for RWA staking.

### Setup

```bash
$ foundryup
$ forge install
```

### Compile

```bash
$ forge compile
```

### Test

```bash
$ forge test
$ forge coverage --ir-minimum
```

### Deploy

```bash
$ forge script script/DeployStakingContracts.s.sol --rpc-url $RPC_URL --broadcast \
    --verify --verifier blockscout --verifier-url $VERIFIER_URL -g 500 --legacy
```
