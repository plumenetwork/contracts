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
$ forge coverage
```

### Deploy

```bash
$ forge script script/DeployDevnetContracts.s.sol --rpc-url $RPC_URL --broadcast \
    --verify --verifier blockscout --verifier-url $VERIFIER_URL -g 500 --legacy
```

### Slither (static analysis)

1. [Install slither](https://github.com/crytic/slither#how-to-install)

```bash
# Get list of issues
$ slither --config-file slither.config.json .
```



## Spin and Raffle specific:

### .env file
```
RPC_URL="https://phoenix-rpc.plumenetwork.xyz"
PRIVATE_KEY=<DEPLOY_WALLET_PRIVATE_KEY>

SPIN_PROXY_ADDRESS=<NEEDED_FOR_UPGRADE>
RAFFLE_PROXY_ADDRESS=<NEEDED_FOR_UPGRADE>

SUPRA_ROUTER_ADDRESS=0xE1062AC81e76ebd17b1e283CEed7B9E8B2F749A5
SUPRA_DEPOSIT_CONTRACT_ADDRESS=0x6DA36159Fe94877fF7cF226DBB164ef7f8919b9b
SUPRA_GENERATOR_CONTRACT_ADDRESS=0x8cC8bbE991d8B4371551B4e666Aa212f9D5f165e
DATETIME_ADDRESS=0x06a40Ec10d03998634d89d2e098F079D06A8FA83
BLOCKSCOUT_URL=https://phoenix-explorer.plumenetwork.xyz/api?
```

### Build
```
forge clean && forge build --via-ir --build-info
```

### Deploy (including the Supra whitelisting and added Role Creation)  

Run the command below, and then after you'll want to verify the contracts.  The output of the deploy scripts explains the verification command.

```
source .env && forge script script/DeploySpinRaffleContracts.s.sol --rpc-url https://phoenix-rpc.plumenetwork.xyz --broadcast --via-ir
```

### Upgrade (whichever you want to upgrade or both)

```
source .env && forge script script/UpgradeSpinContract.s.sol     --rpc-url https://phoenix-rpc.plumenetwork.xyz     --broadcast     --via-ir
source .env && forge script script/UpgradeRaffleContract.s.sol     --rpc-url https://phoenix-rpc.plumenetwork.xyz     --broadcast     --via-ir
```

### Next steps to launch Spin and Raffle

```
 - Raffle: addPrize() -- set up the prizes
 - Spin: setCampaignStartDate() -- set to start time for weekbased date calculations
 - Spin: setEnabledSpin(true)
```