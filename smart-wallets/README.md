## Plume Smart Wallet Contracts

These are the smart contracts that enable smart wallets on Plume.

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
$ forge script script/DeploySmartWallet.s.sol --rpc-url $RPC_URL --broadcast \
    --verify --verifier blockscout --verifier-url $VERIFIER_URL -g 500 --legacy
```
