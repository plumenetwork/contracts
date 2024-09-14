#!/bin/sh

forge script script/DeployToken.s.sol \
  --rpc-url https://ethereum-rpc.publicnode.com \
  --verify --verifier etherscan --verifier-url https://api.etherscan.io/api \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --gas-estimate-multiplier 200 --broadcast -i 1 --sig "run(address)" "$1"
