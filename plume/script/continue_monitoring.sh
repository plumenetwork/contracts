#!/bin/bash

# Address and contract configuration
USER_ADDRESS="0x733F2F6A17A82a156a396D3428b6aCc7787655Ac"
SPIN_CONTRACT="0x5cFADCC362b7696CEBAeD6aC7b9dC5Bdc6f8789c"
TX_HASH="0xde2ed0478de7d27f764497a2184e40d2094c69bbedecfe3ab3bf34e142fd4da0"

# Ensure PLUME_TESTNET_RPC_URL is set
if [ -z "$PLUME_TESTNET_RPC_URL" ]; then
  echo "Error: PLUME_TESTNET_RPC_URL environment variable not set"
  echo "Please set it like: export PLUME_TESTNET_RPC_URL=https://your-testnet-url"
  exit 1
fi

# Function to fetch current block number
get_block_number() {
  curl -s -X POST \
    -H "Content-Type: application/json" \
    --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}" \
    $PLUME_TESTNET_RPC_URL | jq -r '.result' | xargs printf "%d\n" 2>/dev/null || echo "Error fetching block"
}

# Function to fetch user data from contract
fetch_user_data() {
  cast call --rpc-url $PLUME_TESTNET_RPC_URL $SPIN_CONTRACT "getUserData(address)(uint256,uint256,uint256,uint256,uint256,uint256,uint256)" $USER_ADDRESS
}

echo "Continuing to monitor for callback for transaction $TX_HASH..."
echo "USER ADDRESS: $USER_ADDRESS"
echo ""

# Get initial user data
echo "Initial user data:"
initial_data=$(fetch_user_data)
echo "$initial_data"
initial_timestamp=$(echo $initial_data | awk '{print $2}')
echo "Initial lastSpinTimestamp: $initial_timestamp"

# Start monitoring
start_time=$(date +%s)
start_block=$(get_block_number)
last_checked_block=$start_block
echo "Starting at block $start_block ($(date))"
echo "Will monitor for up to 10 minutes..."
echo ""

# Monitor for 10 minutes
while [ $(($(date +%s) - start_time)) -lt 600 ]; do
  current_time=$(date +%s)
  elapsed_time=$((current_time - start_time))
  current_block=$(get_block_number)
  
  if [ "$current_block" != "$last_checked_block" ]; then
    echo "New block: $current_block (+"$((current_block - start_block))" since start)"
    echo "Time elapsed: $elapsed_time seconds"
    last_checked_block=$current_block
    
    # Check if callback has happened
    current_data=$(fetch_user_data)
    current_timestamp=$(echo $current_data | awk '{print $2}')
    
    if [ "$current_timestamp" != "$initial_timestamp" ]; then
      echo "CALLBACK DETECTED! lastSpinTimestamp changed from $initial_timestamp to $current_timestamp"
      echo "Callback occurred after $elapsed_time seconds and $((current_block - start_block)) blocks"
      echo ""
      echo "Final user data:"
      echo "$current_data"
      exit 0
    fi
  fi
  
  # Only print status every 30 seconds to avoid too much output
  if [ $((elapsed_time % 30)) -eq 0 ]; then
    echo "Still monitoring... $elapsed_time seconds elapsed, at block $current_block (+$((current_block - start_block)))"
  fi
  
  sleep 5
done

echo "Monitoring timeout after 10 minutes. No callback detected."
echo "Current user data:"
fetch_user_data 