#!/bin/bash

# fetch all recipient,contract pairs for existing SUP vestings from the factory contract
# and outputs them in csv format
# requires cast (foundry) and jq
# can take a few minutes because it does range log queries.
# NOTE: May not work with public RPCs due to rate limiting.

RPC=${RPC:-"https://mainnet.base.org"}
ADDR="0x3DF8A6558073e973f4c3979138Cca836C993E285"
SIG="SupVestingCreated(address indexed,address indexed)"
START=${START:-33631769}
CHUNK=${CHUNK:-20000}  # Adjust if RPC limits are hit

LATEST=${LATEST:-$(cast block-number --rpc-url $RPC)}
#echo "scanning from $START to $LATEST"
CURRENT=$START

echo "recipient,contract"

while [ $CURRENT -le $LATEST ]; do
  END=$((CURRENT + CHUNK - 1))
  #echo "scanning $CURRENT...$END"
  if [ $END -gt $LATEST ]; then END=$LATEST; fi

  LOGS=$(cast logs --rpc-url $RPC --address $ADDR --from-block $CURRENT --to-block $END "$SIG" --json)

  while IFS= read -r line; do
    recipient=$(echo "$line" | jq -r '.topics[1]')
    contract=$(echo "$line" | jq -r '.topics[2]')
    short_recipient="0x${recipient:26}"
    short_contract="0x${contract:26}"
    echo "$short_recipient,$short_contract"
  done < <(echo "$LOGS" | jq -c '.[]')
  CURRENT=$((END + 1))
done