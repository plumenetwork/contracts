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

# for generating an detailed easy-to-read report on coverage
$ forge coverage --ir-minimum --report lcov   
$ genhtml -o report --branch-coverage lcov.info                                 ✔  08:29:50  
# if genhtml gives you an error like this:
# Reading tracefile lcov.info.
# genhtml: ERROR: (corrupt) unable to read trace file 'lcov.info': genhtml: ERROR: (inconsistent) "src/token/YieldDistributionToken.sol":62:  function YieldDistributionToken._getYieldDistributionTokenStorage found on line but no corresponding 'line' coverage data point.  Cannot derive function end line.  See lcovrc man entry for 'derive_function_end_line'.
#         (use "genhtml --ignore-errors inconsistent ..." to bypass this error)
# then use this to generate the report
$ genhtml -o report --branch-coverage --ignore-errors inconsistent --ignore-errors corrupt lcov.info
# open up report/index.html in your editor and open the preview to navigate through the coverage report
```

### Deploy

```bash
$ forge script script/DeploySmartWallet.s.sol --rpc-url $RPC_URL --broadcast \
    --verify --verifier blockscout --verifier-url $VERIFIER_URL -g 500 --legacy
```

### Slither (static analysis)

1. [Install slither](https://github.com/crytic/slither#how-to-install)

```bash
# Get list of issues
$ slither --config-file slither.config.json .
```
