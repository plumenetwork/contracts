#!/bin/bash

# Ensure PRIVATE_KEY is set
if [ -z "$PRIVATE_KEY" ]; then
  echo "Error: PRIVATE_KEY environment variable not set"
  echo "Please set it like: export PRIVATE_KEY=0xYourPrivateKeyHere"
  exit 1
fi

# Ensure PLUME_TESTNET_RPC_URL is set
if [ -z "$PLUME_TESTNET_RPC_URL" ]; then
  echo "Error: PLUME_TESTNET_RPC_URL environment variable not set"
  echo "Please set it like: export PLUME_TESTNET_RPC_URL=https://your-testnet-url"
  exit 1
fi

# Select which script to run
echo "Select a script to run:"
echo "1) Basic Test (TestSpin.s.sol) - Simple call to startSpin"
echo "2) Debug Script (DebugSpin.s.sol) - Detailed logging of contract state"
echo "3) Trace Supra Call (TraceSupraCall.s.sol) - Trace the external call to Supra Router"
echo "4) Gas Monitor (GasMonitor.s.sol) - Test with different gas limits to find optimal setting"
echo "5) Monitor Callback (MonitorCallback.s.sol) - Monitor for the callback after startSpin"
echo "6) Arbitrum Block Monitor - Track block production and transaction status"
read -p "Enter your choice (1-6): " choice

case $choice in
  1)
    script="script/TestSpin.s.sol:TestSpinScript"
    forge script $script --rpc-url $PLUME_TESTNET_RPC_URL --broadcast -vvvv
    ;;
  2)
    script="script/DebugSpin.s.sol:DebugSpinScript"
    forge script $script --rpc-url $PLUME_TESTNET_RPC_URL --broadcast -vvvv
    ;;
  3)
    script="script/TraceSupraCall.s.sol:TraceSupraCallScript"
    forge script $script --rpc-url $PLUME_TESTNET_RPC_URL --broadcast -vvvv
    ;;
  4)
    script="script/GasMonitor.s.sol:GasMonitorScript"
    forge script $script --rpc-url $PLUME_TESTNET_RPC_URL --broadcast -vvvv
    ;;
  5)
    script="script/MonitorCallback.s.sol:MonitorCallbackScript"
    forge script $script --rpc-url $PLUME_TESTNET_RPC_URL --broadcast -vvvv
    ;;
  6)
    ./script/arbitrum_block_monitor.sh
    ;;
  *)
    echo "Invalid choice. Exiting."
    exit 1
    ;;
esac 