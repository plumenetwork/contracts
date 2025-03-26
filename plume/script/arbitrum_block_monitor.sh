#!/bin/bash

# Ensure PLUME_TESTNET_RPC_URL is set
if [ -z "$PLUME_TESTNET_RPC_URL" ]; then
  echo "Error: PLUME_TESTNET_RPC_URL environment variable not set"
  echo "Please set it like: export PLUME_TESTNET_RPC_URL=https://your-testnet-url"
  exit 1
fi

# Set contract addresses
SPIN_CONTRACT="0x5cFADCC362b7696CEBAeD6aC7b9dC5Bdc6f8789c"

# Function to fetch current block number
get_block_number() {
  curl -s -X POST \
    -H "Content-Type: application/json" \
    --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}" \
    $PLUME_TESTNET_RPC_URL | jq -r '.result' | xargs printf "%d\n" 2>/dev/null || echo "Error fetching block"
}

# Function to monitor block production
monitor_blocks() {
  echo "Starting Arbitrum block monitoring..."
  
  # Get initial block
  initial_block=$(get_block_number)
  current_block=$initial_block
  last_block=$initial_block
  start_time=$(date +%s)
  block_timestamps=()
  
  echo "Initial block: $initial_block at $(date)"
  
  # Monitor for 3 minutes
  while [ $(($(date +%s) - start_time)) -lt 180 ]; do
    current_block=$(get_block_number)
    
    if [ "$current_block" != "$last_block" ]; then
      # New block found
      now=$(date +%s)
      time_since_start=$((now - start_time))
      block_timestamps+=($time_since_start)
      
      echo "New block $current_block produced after $time_since_start seconds"
      last_block=$current_block
    fi
    
    # Sleep for 2 seconds before checking again
    sleep 2
  done
  
  # Calculate block production statistics
  blocks_produced=$((current_block - initial_block))
  total_time=$(($(date +%s) - start_time))
  
  echo ""
  echo "=== Block Production Statistics ==="
  echo "Monitoring duration: $total_time seconds"
  echo "Initial block: $initial_block"
  echo "Final block: $current_block"
  echo "Blocks produced: $blocks_produced"
  
  if [ $blocks_produced -gt 0 ]; then
    avg_time=$(echo "scale=2; $total_time / $blocks_produced" | bc)
    echo "Average time between blocks: $avg_time seconds"
    
    # Print block timestamps
    echo "Block production timeline (seconds since start):"
    for timestamp in "${block_timestamps[@]}"; do
      echo "  $timestamp"
    done
  else
    echo "No new blocks were produced during the monitoring period!"
    echo "This confirms that block production on this Arbitrum testnet is very sparse."
  fi
}

# Function to run a test spin transaction and monitor state
test_spin_transaction() {
  echo "Running monitoring Forge script..."
  
  forge script script/MonitorCallback.s.sol:MonitorCallbackScript \
    --rpc-url $PLUME_TESTNET_RPC_URL \
    --broadcast \
    -vv
}

# Function to fetch user data from contract
fetch_user_data() {
  local user_address=$1
  echo "Fetching user data for address: $user_address"
  
  cast call --rpc-url $PLUME_TESTNET_RPC_URL $SPIN_CONTRACT "getUserData(address)(uint256,uint256,uint256,uint256,uint256,uint256,uint256)" $user_address
}

# Function to actually monitor a real transaction's callback
real_monitor() {
  echo "Starting real transaction monitoring..."
  
  # Ensure PRIVATE_KEY is set
  if [ -z "$PRIVATE_KEY" ]; then
    echo "Error: PRIVATE_KEY environment variable not set"
    echo "Please set it like: export PRIVATE_KEY=0xYourPrivateKeyHere"
    exit 1
  fi
  
  # Get the address from the private key
  wallet_address=$(cast wallet address --private-key $PRIVATE_KEY)
  echo "Using wallet address: $wallet_address"
  
  # Get user data before spin
  echo "User data BEFORE spin:"
  fetch_user_data $wallet_address
  
  # Send a transaction to startSpin with more debugging
  echo "Sending startSpin transaction..."
  echo "Command: cast send --private-key \$PRIVATE_KEY --rpc-url $PLUME_TESTNET_RPC_URL $SPIN_CONTRACT \"startSpin()\""
  
  tx_output=$(cast send --private-key $PRIVATE_KEY --rpc-url $PLUME_TESTNET_RPC_URL $SPIN_CONTRACT "startSpin()" 2>&1)
  echo "Transaction output:"
  echo "$tx_output"
  
  # Extract transaction hash more reliably
  tx_hash=$(echo "$tx_output" | grep -i "transaction hash" | awk '{print $NF}')
  
  if [ -z "$tx_hash" ]; then
    echo "Failed to get transaction hash. Showing full output for debugging:"
    echo "$tx_output"
    exit 1
  fi
  
  echo "Transaction sent with hash: $tx_hash"
  echo "Waiting for transaction to be mined..."
  
  # Wait for transaction to be mined
  cast receipt --rpc-url $PLUME_TESTNET_RPC_URL $tx_hash
  
  echo "Transaction mined. Now monitoring for callback..."
  
  # Monitor blocks and check for callback
  start_time=$(date +%s)
  start_block=$(get_block_number)
  last_checked_block=$start_block
  initial_timestamp=0
  
  # Get initial timestamp 
  initial_data=$(cast call --rpc-url $PLUME_TESTNET_RPC_URL $SPIN_CONTRACT "getUserData(address)(uint256,uint256,uint256,uint256,uint256,uint256,uint256)" $wallet_address)
  initial_timestamp=$(echo $initial_data | awk '{print $2}')
  echo "Initial lastSpinTimestamp: $initial_timestamp"
  
  # Monitor for 5 minutes
  while [ $(($(date +%s) - start_time)) -lt 300 ]; do
    current_block=$(get_block_number)
    elapsed_time=$(($(date +%s) - start_time))
    
    if [ "$current_block" != "$last_checked_block" ]; then
      echo "New block: $current_block (+"$((current_block - start_block))" since tx)"
      echo "Time elapsed: $elapsed_time seconds"
      last_checked_block=$current_block
      
      # Check if callback has happened by comparing lastSpinTimestamp
      current_data=$(cast call --rpc-url $PLUME_TESTNET_RPC_URL $SPIN_CONTRACT "getUserData(address)(uint256,uint256,uint256,uint256,uint256,uint256,uint256)" $wallet_address)
      current_timestamp=$(echo $current_data | awk '{print $2}')
      
      if [ "$current_timestamp" != "$initial_timestamp" ]; then
        echo "CALLBACK DETECTED! lastSpinTimestamp changed from $initial_timestamp to $current_timestamp"
        echo "Callback occurred after $elapsed_time seconds and $((current_block - start_block)) blocks"
        echo ""
        echo "Final user data:"
        echo "$current_data"
        return
      fi
    fi
    
    sleep 5
  done
  
  echo "Monitoring complete. No callback detected after 5 minutes."
  echo "Current user data:"
  fetch_user_data $wallet_address
}

# Main menu
echo "Arbitrum Testnet Block Production Monitor"
echo "1) Monitor block production"
echo "2) Test spin transaction and monitor callback (Forge script)"
echo "3) Real transaction monitor with Cast (most accurate)"
echo "4) Run full test suite"
read -p "Enter your choice (1-4): " choice

case $choice in
  1)
    monitor_blocks
    ;;
  2)
    test_spin_transaction
    ;;
  3)
    real_monitor
    ;;
  4)
    monitor_blocks
    echo ""
    echo "Now testing spin transaction..."
    test_spin_transaction
    ;;
  *)
    echo "Invalid choice. Exiting."
    exit 1
    ;;
esac 