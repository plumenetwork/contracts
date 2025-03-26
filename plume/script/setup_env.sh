#!/bin/bash

# Script to set up environment variables for debugging

echo "Setting up environment variables for debugging Spin contract..."

# Prompt for private key
read -p "Enter your private key (with 0x prefix): " PRIVATE_KEY
export PRIVATE_KEY

# Prompt for RPC URL
read -p "Enter the testnet RPC URL: " PLUME_TESTNET_RPC_URL
export PLUME_TESTNET_RPC_URL

echo "Environment variables set successfully."
echo "To run the debug script, execute: ./script/run_debug.sh" 