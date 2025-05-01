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



Spin and Raffle specific:

# Testnet 
source .env && forge script script/DeploySpinRaffleContracts.s.sol --rpc-url https://testnet-rpc.plumenetwork.xyz --broadcast --via-ir
source .env && forge script script/DeploySpinRaffleContracts.s.sol --rpc-url https://phoenix-rpc.plumenetwork.xyz --broadcast --via-ir

```
# Verify Spin implementation
forge verify-contract \
  --chain-id <chain-id> \
  --verifier blockscout \
  --verifier-url https://your-blockscout-instance.com/api? \
  <deployed-spin-implementation-address> \
  src/spin/Spin.sol:Spin

# Verify Raffle implementation
forge verify-contract \
  --chain-id <chain-id> \
  --verifier blockscout \
  --verifier-url https://your-blockscout-instance.com/api? \
  <deployed-raffle-implementation-address> \
  src/spin/Raffle.sol:Raffle

# Verify SpinProxy
forge verify-contract \
  --chain-id <chain-id> \
  --verifier blockscout \
  --verifier-url https://your-blockscout-instance.com/api? \
  <deployed-spin-proxy-address> \
  src/proxy/SPINProxy.sol:SpinProxy \
  --constructor-args $(cast abi-encode "constructor(address,bytes)" <spin-implementation-address> <spin-init-data>)

# Verify RaffleProxy
forge verify-contract \
  --chain-id <chain-id> \
  --verifier blockscout \
  --verifier-url https://your-blockscout-instance.com/api? \
  <deployed-raffle-proxy-address> \
  src/proxy/RaffleProxy.sol:RaffleProxy \
  --constructor-args $(cast abi-encode "constructor(address,bytes)" <raffle-implementation-address> <raffle-init-data>)
  ```


TESTNET 

== Logs ==
  Deploying from: 0x656625D42167068796B3665763D4Ed756df65Dc6
  Spin implementation deployed to: 0x782790e8C1E330b328FDaf0cECcc8bE2b443c899
  Spin Proxy deployed to: 0xaC7404178d1a5d642BCA587FE29EF94e7B412508
  Raffle implementation deployed to: 0xd0Fe854bd3380E0b9B1DAb0e0edf3c753fc6abE1
  Raffle Proxy deployed to: 0x96d53efF53477AeE51D80A1907Dd6985829B9F72
  Set Raffle contract in Spin



  ```
  ```

     curl -X POST https://phoenix-rpc.plumenetwork.xyz \
     -H "Content-Type: application/json" \
     --data '{"jsonrpc":"2.0","method":"eth_call","params":[{"to":"0xaC7404178d1a5d642BCA587FE29EF94e7B412508","data":"0xa96ae1d7"},"latest"],"id":1}'



prod:

~/poof/plume/contracts/plume: $  (spin-refactored) source .env && forge script script/DeploySpinRaffleContracts.s.sol --rpc-url https://phoenix-rpc.plumenetwork.xyz --broadcast --via-ir
[⠊] Compiling...
[⠊] Compiling 1 files with Solc 0.8.25
[⠒] Solc 0.8.25 finished in 8.03s
Compiler run successful!
Script ran successfully.

== Logs ==
  Deploying from: 0x656625D42167068796B3665763D4Ed756df65Dc6
  Spin implementation deployed to: 0x84F39F198238Ab6aeBadE91B92980A6f7751988D
  Spin init data (for verification): 0x485cc955000000000000000000000000e1062ac81e76ebd17b1e283ceed7b9e8b2f749a500000000000000000000000006a40ec10d03998634d89d2e098f079d06a8fa83
  Spin Proxy deployed to: 0x7D9bB888EdeD1b0CBd4Be9c8c67BD4b6c5E24059
  Raffle implementation deployed to: 0xCf0ab236D8aD3006dcf065C70583CE14473A010e
  Raffle init data (for verification): 0x485cc9550000000000000000000000007d9bb888eded1b0cbd4be9c8c67bd4b6c5e24059000000000000000000000000e1062ac81e76ebd17b1e283ceed7b9e8b2f749a5
  Raffle Proxy deployed to: 0x3739Be95F96bA14338DB119d8A60fd7c5f258F83
  Set Raffle contract in Spin

--- Blockscout Verification Commands ---
  Spin implementation verification:
  forge verify-contract --chain-id 98866 --verifier blockscout --verifier-url https://phoenix-explorer.plumenetwork.xyz/api 0x84F39F198238Ab6aeBadE91B92980A6f7751988D src/spin/Spin.sol:Spin

Raffle implementation verification:
  forge verify-contract --chain-id 98866 --verifier blockscout --verifier-url https://phoenix-explorer.plumenetwork.xyz/api 0xCf0ab236D8aD3006dcf065C70583CE14473A010e src/spin/Raffle.sol:Raffle

Spin Proxy verification:
  forge verify-contract --chain-id 98866 --verifier blockscout --verifier-url https://phoenix-explorer.plumenetwork.xyz/api 0x7D9bB888EdeD1b0CBd4Be9c8c67BD4b6c5E24059 src/proxy/SPINProxy.sol:SpinProxy --constructor-args 0x00000000000000000000000084f39f198238ab6aebade91b92980a6f7751988d00000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000044485cc955000000000000000000000000e1062ac81e76ebd17b1e283ceed7b9e8b2f749a500000000000000000000000006a40ec10d03998634d89d2e098f079d06a8fa8300000000000000000000000000000000000000000000000000000000

Raffle Proxy verification:
  forge verify-contract --chain-id 98866 --verifier blockscout --verifier-url https://phoenix-explorer.plumenetwork.xyz/api 0x3739Be95F96bA14338DB119d8A60fd7c5f258F83 src/proxy/RaffleProxy.sol:RaffleProxy --constructor-args 0x000000000000000000000000cf0ab236d8ad3006dcf065c70583ce14473a010e00000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000044485cc9550000000000000000000000007d9bb888eded1b0cbd4be9c8c67bd4b6c5e24059000000000000000000000000e1062ac81e76ebd17b1e283ceed7b9e8b2f749a500000000000000000000000000000000000000000000000000000000

## Setting up 1 EVM.

==========================

Chain 98866

Estimated gas price: 200.000000001 gwei

Estimated total gas used for script: 8925989

Estimated amount required: 1.785197800008925989 ETH

==========================

##### 98866
✅  [Success] Hash: 0xfe032b6db0f89b48c27ddf9213d2e4e995fb0734b603adbd8d3aa886c67ba324
Contract Address: 0x84F39F198238Ab6aeBadE91B92980A6f7751988D
Block: 1247568
Paid: 0.2597883 ETH (2597883 gas * 100 gwei)


##### 98866
✅  [Success] Hash: 0xf33419c42f7e80c89243fc721672273a222fd38230c4cbbc91f1719c22de4c2c
Contract Address: 0xCf0ab236D8aD3006dcf065C70583CE14473A010e
Block: 1247569
Paid: 0.2906193 ETH (2906193 gas * 100 gwei)


##### 98866
✅  [Success] Hash: 0x755c4d75dccff2583699e868618d7c29a2a3a95503a4f8758512952b450902ce
Contract Address: 0x7D9bB888EdeD1b0CBd4Be9c8c67BD4b6c5E24059
Block: 1247568
Paid: 0.0989089 ETH (989089 gas * 100 gwei)


##### 98866
✅  [Success] Hash: 0x11656d28f93d6bffcd1eb53683534df35780d9da0d14cfe7a90c1fb2dd268b55
Contract Address: 0x3739Be95F96bA14338DB119d8A60fd7c5f258F83
Block: 1247569
Paid: 0.031895 ETH (318950 gas * 100 gwei)


##### 98866
✅  [Success] Hash: 0x7bae4e46fd603c81276d78381dd718d596b7376ba3fa975f87b760b97ec1a87f
Block: 1247569
Paid: 0.0050855 ETH (50855 gas * 100 gwei)

✅ Sequence #1 on 98866 | Total Paid: 0.686297 ETH (6862970 gas * avg 100 gwei)

