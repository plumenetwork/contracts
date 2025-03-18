#!/bin/bash

# Debug script for Faucet.getToken function
# This script helps generate a signature and calls the getToken function using cast

# Parameters
FAUCET_ADDRESS="0xEBa7Ee4c64a91B5dDb4631a66E541299f978fdd0"
RPC_URL=${PLUME_DEVNET_RPC_URL:-""}
OWNER_PRIVATE_KEY=${FAUCET_OWNER_PRIVATE_KEY:-""}
RECIPIENT_ADDRESS=${1:-"0x0000000000000000000000000000000000000000"}
TOKEN_NAME=${2:-"PLUME"}                                            
FLIGHT_CLASS=${3:-"1"}                                              
SALT=$(cast keccak $(date +%s))                                     

# Check if required parameters are set
if [ -z "$RPC_URL" ]; then
    echo "Error: PLUME_DEVNET_RPC_URL environment variable is not set"
    exit 1
fi

if [ -z "$OWNER_PRIVATE_KEY" ]; then
    echo "Error: FAUCET_OWNER_PRIVATE_KEY environment variable is not set"
    exit 1
fi

if [ "$RECIPIENT_ADDRESS" = "0x0000000000000000000000000000000000000000" ]; then
    echo "Warning: Using zero address as recipient. Provide a real address as the first argument."
fi

echo "Debug parameters:"
echo "- Faucet address: $FAUCET_ADDRESS"
echo "- Recipient: $RECIPIENT_ADDRESS"
echo "- Token: $TOKEN_NAME"
echo "- Flight class: $FLIGHT_CLASS"
echo "- Salt: $SALT"

# Step 1: Create the message hash using solidity encoding
# We're using cast to directly compute the hash from the Solidity contract's formula:
# keccak256(abi.encodePacked(msg.sender, token, flightClass, salt))
MESSAGE=$(cast call --rpc-url $RPC_URL $FAUCET_ADDRESS "hashMessage(address,string,uint256,bytes32)(bytes32)" "$RECIPIENT_ADDRESS" "$TOKEN_NAME" "$FLIGHT_CLASS" "$SALT" 2>/dev/null || echo "")

# If we got an error calling hashMessage (which likely doesn't exist), fallback to manual hash
if [ -z "$MESSAGE" ]; then
    echo "Couldn't call contract for hashing, falling back to manual method..."
    
    # Convert recipient address to hex without 0x prefix
    ADDR_HEX=$(echo $RECIPIENT_ADDRESS | sed 's/^0x//')
    
    # Convert token to hex
    TOKEN_HEX=$(echo -n "$TOKEN_NAME" | xxd -p)
    
    # Convert flight class to hex (uint256 is 32 bytes)
    CLASS_HEX=$(cast --to-uint256 $FLIGHT_CLASS | sed 's/^0x//')
    
    # Salt is already in hex format, just remove 0x if present
    SALT_HEX=$(echo $SALT | sed 's/^0x//')
    
    # Create packed bytes
    PACKED_HEX="0x${ADDR_HEX}${TOKEN_HEX}${CLASS_HEX}${SALT_HEX}"
    
    # Hash the packed bytes
    MESSAGE=$(cast keccak $PACKED_HEX)
fi

echo "- Message hash: $MESSAGE"

# Step 2: Create Ethereum signed message hash
# To create a proper eth_sign compatible message, we need to follow this format:
# "\x19Ethereum Signed Message:\n32" + messageHash
PREFIXED_MSG="\x19Ethereum Signed Message:\n32$MESSAGE"
ETH_SIGNED_MESSAGE=$(cast keccak $PREFIXED_MSG)
echo "- Ethereum signed message: $ETH_SIGNED_MESSAGE"

# Step 3: Sign the message with the owner's private key
SIGNATURE=$(cast wallet sign --private-key $OWNER_PRIVATE_KEY $MESSAGE)
echo "- Signature: $SIGNATURE"

# Step 4: Check contract view functions for verification
echo -e "\nContract verification:"
OWNER=$(cast call $FAUCET_ADDRESS "getOwner()(address)" --rpc-url $RPC_URL)
echo "- Contract owner: $OWNER"

OWNER_FROM_KEY=$(cast wallet address --private-key $OWNER_PRIVATE_KEY)
echo "- Derived address from private key: $OWNER_FROM_KEY"

TOKEN_ADDRESS=$(cast call $FAUCET_ADDRESS "getTokenAddress(string)(address)" "$TOKEN_NAME" --rpc-url $RPC_URL)
echo "- Token address: $TOKEN_ADDRESS"

BASE_DRIP_AMOUNT=$(cast call $FAUCET_ADDRESS "getDripAmount(string)(uint256)" "$TOKEN_NAME" --rpc-url $RPC_URL)
echo "- Base drip amount: $BASE_DRIP_AMOUNT"

FLIGHT_DRIP_AMOUNT=$(cast call $FAUCET_ADDRESS "getDripAmount(string,uint256)(uint256)" "$TOKEN_NAME" "$FLIGHT_CLASS" --rpc-url $RPC_URL)
echo "- Flight class drip amount: $FLIGHT_DRIP_AMOUNT"

# Step 5: Format the call data for getToken
echo -e "\nPreparing to call getToken..."

# Check if nonce is already used
IS_NONCE_USED=$(cast call $FAUCET_ADDRESS "isNonceUsed(bytes32)(bool)" "$MESSAGE" --rpc-url $RPC_URL)
echo "- Is nonce used: $IS_NONCE_USED"

if [ "$IS_NONCE_USED" = "true" ]; then
    echo "Error: Nonce is already used. Try again with a different salt."
    exit 1
fi

# Step 6: Call the getToken function
echo -e "\nCalling getToken function..."
echo "Command:"
echo "cast send --rpc-url $RPC_URL --private-key <PRIVATE_KEY> $FAUCET_ADDRESS \"getToken(string,uint256,bytes32,bytes)\" \"$TOKEN_NAME\" \"$FLIGHT_CLASS\" \"$SALT\" \"$SIGNATURE\" --from $RECIPIENT_ADDRESS"

echo -e "\nTo execute this transaction for real, copy the command, replace $PRIVATE_KEY with the private key for the recipient address, and run it."

