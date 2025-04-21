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

## Faucet Contract

The Faucet contract provides a way to distribute tokens to users on the Plume Network. It is implemented as an upgradeable contract that supports both native tokens (PLUME) and ERC20 tokens.

### Features

- **Flight Class Multipliers**: Different flight classes receive different amounts of tokens based on a multiplier system.
- **Owner-Signed Requests**: All token requests must be signed by the contract owner to prevent abuse.
- **Nonce Protection**: Each signature can only be used once to prevent replay attacks.
- **Multiple Token Support**: The faucet can distribute both native PLUME tokens and any added ERC20 tokens.

### Implementation Details

The Faucet contract uses:
- `onlySignedByOwner` modifier to validate signatures
- `keccak256(abi.encodePacked(msg.sender, token, flightClass, salt))` for message hashing
- ERC1967 proxy pattern for upgradeability
- Flight class multipliers (Economy: 1x, Plus: 1.1x, Premium: 1.25x, Business: 2x, First: 3x, Private: 5x)

### Debug Script for getToken

The `debug_getToken.sh` script in the `script` directory helps generate valid signatures and debug the getToken function. This is especially useful for interacting with the deployed Faucet contract.

#### Prerequisites

- Set up environment variables:
  ```bash
  export PLUME_DEVNET_RPC_URL="<your_rpc_url>"
  export FAUCET_OWNER_PRIVATE_KEY="<faucet_owner_private_key>"
  ```

#### Usage

```bash
./script/debug_getToken.sh <recipient_address> <token_name> <flight_class>
```

Example:
```bash
./script/debug_getToken.sh 0xYourAddress PLUME 1
```

#### Script Features

1. **Signature Generation**: Creates a valid signature required by the contract
2. **Contract Verification**: Verifies contract parameters (owner, token address, drip amounts)
3. **Command Generation**: Outputs ready-to-use commands for transaction execution

#### Example Output

The script will output:
- All debug parameters
- The message hash and signature
- Contract verification details
- Ready-to-use commands for calling the function

#### Using the Generated Command

After running the script, you'll get a command like:

```bash
cast send --rpc-url $RPC_URL --private-key <PRIVATE_KEY> 0xEBa7Ee4c64a91B5dDb4631a66E541299f978fdd0 "getToken(string,uint256,bytes32,bytes)" "PLUME" "1" "0x123..." "0x456..."
```

Copy this command, replace `<PRIVATE_KEY>` with the private key for the recipient address, and run it to execute the transaction.
