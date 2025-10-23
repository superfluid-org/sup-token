#!/bin/bash

set -eu

# expects an argument: filename with the tsv (tab separated values) file listing the schedules
filename=$1

# expected env vars:
# - ACCOUNT_NAME: foundry keystore wallet account
# - RPC_URL: base mainnet RPC
# - MODE (optional): SIMULATE (default), TESTING, EXECUTE.
#        in TESTING mode, env var ADMIN_ADDR must be set

# Optional env var overrides:
# - CLIFF_DATE: override cliffDate (unix seconds)
# - END_DATE: override endDate (unix seconds)
# - CLIFF_AMOUNT: override cliffAmount (wei)

MODE=${MODE:-"SIMULATE"}

# check chain id of 
chainId=$(cast chain-id --rpc-url "$RPC_URL")
if [ "$chainId" != "8453" ]; then
  echo "Error: RPC reports chain ID $chainId, but we expect 8453 (Base)"
  exit 1
fi

echo "using account $ACCOUNT_NAME, RPC $RPC_URL"

# Factory address on Base
FACTORY="0x3DF8A6558073e973f4c3979138Cca836C993E285"
DEFAULT_CLIFFDATE=1771459200
DEFAULT_ENDDATE=1834531200

# Skip header
row=1
tail -n +2 $filename | while IFS=$'\t' read -r type recipient tokens category cliffonly; do
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
  elif [ "$type" == "3" ]; then
    index=2
  else
    echo "Error: Invalid type $type for $recipient"
    exit 1
    #continue
  fi

  echo "==== PROCESSING #$row: $recipient ===="

  # Resolve ENS if recipient ends with .eth
  recipientAddr=$recipient
  if [[ $recipient == *.eth ]]; then
    recipientAddr=$(cast resolve-name "$recipient" --rpc-url https://eth-mainnet.rpc.x.superfluid.dev)
    echo "resolved ENS $recipient to $recipientAddr"
  fi

  # Assume 18 decimals
  amount=$(echo "scale=0; $tokens * 10^18" | bc)
  defaultCliffAmount=$(echo "scale=0; $amount / 3" | bc)

  # Dates and amounts with optional env var overrides
  cliffDate=${CLIFF_DATE:-$DEFAULT_CLIFFDATE}
  endDate=${END_DATE:-$DEFAULT_ENDDATE}
  cliffAmount=${CLIFF_AMOUNT:-$defaultCliffAmount}

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

  if [ "$MODE" == "EXECUTE" ]; then
    cast send --rpc-url "$RPC_URL" --account "$ACCOUNT_NAME" "$FACTORY" "$calldata"
  elif [ "$MODE" == "TESTING" ]; then
    cast send --quiet --rpc-url "$RPC_URL" --from $ADMIN_ADDR --unlocked "$FACTORY" "$calldata"
  else
    echo "SIMULATING: skipping execution"
  fi

  # Increment row counter at the end of the loop
  ((row++))
done 