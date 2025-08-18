#!/bin/bash

set -eu

# expected env vars:
# - ACCOUNT_NAME: foundry keystore wallet account
# - RPC_URL: base mainnet RPC

# check chain id of 
chainId=$(cast chain-id --rpc-url "$RPC_URL")
if [ "$chainId" != "8453" ]; then
  echo "Error: RPC reports chain ID $chainId, but we expect 8453 (Base)"
  exit 1
fi

echo "using account $ACCOUNT_NAME, RPC $RPC_URL"

# Factory address on Base
FACTORY="0x3DF8A6558073e973f4c3979138Cca836C993E285"
DEFAULT_CLIFFDATE=1771074000
DEFAULT_ENDDATE=1834146000

# Skip header
tail -n +2 schedules.csv | while IFS=, read -r type recipient tokens; do
  # Clean inputs
  type=$(echo "$type" | tr -d ' "\r')
  recipient=$(echo "$recipient" | tr -d ' "\r')
  tokens=$(echo "$tokens" | tr -d ' "\r')

  # Remove commas from tokens
  tokens=${tokens//,/}

  # Determine index
  if [ "$type" == "1" ]; then
    index=0
  elif [ "$type" == "2" ]; then
    index=1
  else
    echo "Error: Invalid type $type for $recipient"
    continue
  fi

  echo "==== PROCESSING $recipient ===="

  # Resolve ENS if recipient ends with .eth
  recipientAddr=$recipient
  if [[ $recipient == *.eth ]]; then
    recipientAddr=$(cast resolve-name "$recipient" --rpc-url https://eth-mainnet.rpc.x.superfluid.dev)
    echo "resolved ENS $recipient to $recipientAddr"
  fi

  # Assume 18 decimals
  amount=$(echo "scale=0; $tokens * 10^18" | bc)
  cliffAmount=$(echo "scale=0; $amount / 3" | bc)

  # cliffDate and endDate
  cliffDate=$DEFAULT_CLIFFDATE
  endDate=$DEFAULT_ENDDATE

  # Calldata
  calldata=$(cast calldata "createSupVestingContract(address,uint256,uint256,uint256,uint32,uint32)" "$recipientAddr" "$index" "$amount" "$cliffAmount" "$cliffDate" "$endDate")

  # log all the arguments
  echo "  address: $recipientAddr"
  echo "  index: $index"
  echo "  amount: $amount"
  echo "  cliffAmount: $cliffAmount"
  echo "  cliffDate: $cliffDate"
  echo "  endDate: $endDate"

  # Generate cast command
  echo "cast send --rpc-url $RPC_URL --account $ACCOUNT_NAME $FACTORY $calldata"

  # if env var DO_EXECUTE is set, execute the command
  if [ -n "${DO_EXECUTE:-}" ]; then
    cast send --rpc-url "$RPC_URL" --account "$ACCOUNT_NAME" "$FACTORY" "$calldata"
  fi
done 