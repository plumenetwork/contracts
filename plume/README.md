## Plume Smart Contracts

These smart contracts and scripts are used throughout Plume Network.

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
$ forge script script/DeployDevnetContracts.s.sol --rpc-url $RPC_URL --broadcast \
    --verify --verifier blockscout --verifier-url $VERIFIER_URL -g 500 --legacy
```
