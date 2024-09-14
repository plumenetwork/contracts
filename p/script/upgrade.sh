#!/bin/sh

forge script script/UpgradeToken.s.sol \
  --rpc-url https://ethereum-sepolia-rpc.publicnode.com \
  --verify --verifier etherscan --verifier-url https://api-sepolia.etherscan.io/api \
  --broadcast -i 1 --sig "run(address)" "$1"
